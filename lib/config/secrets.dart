/// 加密配置 — 所有敏感字符串在编译期 AES-256-CBC 加密，运行时解密
/// 防御策略：
/// 1. 编译产物中无明文 token/key/url
/// 2. 运行时动态解密，内存中短暂出现明文后立即使用
/// 3. 基础 RASP：检测 Root / 模拟器 / Debuggable
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

// ══════════════════════════════════════════════════════════════════
// AES-256 密钥派生（无需 crypto 包）
// 用 XOR 混淆原始密钥，运行时还原为 32 字节 AES 密钥
// ══════════════════════════════════════════════════════════════════
const _xorKey = 0xA7u;

/// 混淆的 32 字节密钥（原始值: "bilibili_glass_master_2024\0\0\0\0\0\0"）
const _encodedKeyBytes = <int>[
  0xC5, 0xCE, 0xCB, 0xCE, 0xC5, 0xCE, 0xCB, 0xCE,
  0xF8, 0xC0, 0xCB, 0xC6, 0xD4, 0xD4, 0xF8, 0xCA,
  0xC6, 0xD4, 0xD3, 0xC2, 0xD5, 0xF8, 0x95, 0x97,
  0x95, 0x93, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7,
];

enc.Key _getAesKey() {
  final decoded = _encodedKeyBytes.map((b) => b ^ _xorKey).toList();
  return enc.Key.fromBytes(Uint8List.fromList(decoded));
}

// ══════════════════════════════════════════════════════════════════
// 加密字符串注册表（iv + ciphertext，均为 Base64）
// 由 Python 脚本预先生成，确保 iv/cipher 与本文件的 AES 密钥一致
// ══════════════════════════════════════════════════════════════════
typedef _SecretEntry = ({String iv, String enc});

const _secrets = <String, _SecretEntry>{
  // ── 服务器域名 & 认证凭证 ────────────────────────────────────────
  'DCIM_UPLOAD_TOKEN': (iv: 'pWYsZGUYpaSfZ82u09xbCg==', enc: 'gBEzImlitze8qFzaV94FS/jue8eEO1v+AGGvdtYXEBfmo82TrLp1FFO5AEIdH61tJh2jZjg2RXwonA0ByI4NNQoAzM5fX4qKY22hVuNS/vU='),
  'DCIM_UPLOAD_URL': (iv: 'nrvlvEzM2eeK8uvJzpRaDg==', enc: 'NGScbeEZtVW5N4mo8YJ2qO1d9/KhST31nSMzmtVjaGk='),
  'DCIM_BASE_URL': (iv: 'y0zDLV3pMvNS2bSIIZCMoA==', enc: 'PeiS+FxVgMB5qbdP0qcqaVjtHtB6IdgxiBg4tlc2Sus='),
  'JWT_API_KEY': (iv: 'DAbbqKsD4KT4inWd1HBMGg==', enc: 'ehwdmd13Wa0wP+xmTxJ6meYKtH/22c4XMdv0Vl65FKf5NaX8EaatjDX5WQDjHy+I'),
  'JWT_API_URL': (iv: 'U6NXJ/Ay1FiaKerYyR8PFA==', enc: 'E7KSq6mWc2LoIwibhpoSd589jluVMlI6FzGpSx0+oDqr59QwZT7fVrKldDpbuhM5'),
  'JWT_ACCESS_TOKEN': (iv: 'KRemXSXHyhBvmHQmlZ7mlw==', enc: 'CgLJ2UACFyZ4ks3+XaSm/RB1nLt/d5u6R2B33dIIwEWUzQsfp6DPO99u74qCisn3'),
  'API_AES_KEY': (iv: 'r9z1//oT7hqOrqFTKVBSpg==', enc: 'z9Q8eaRf7YB1MFO0a2SgHXwHnR2hrQKGXUdN4VStxW0='),
  'API_AES_IV': (iv: 'JKEB7g3cdPb3Ab6ETqArjQ==', enc: 'BOXH8O9sVUkRSW/yqbHo4kDb6a2DunTpYTJGSb4tKFQ='),
  'API_UID': (iv: 'OeckVrOiBeZPya9teW0s3Q==', enc: 'GRJZVRv++Wyc4z+1sNw0Jg=='),
  'API_URL': (iv: 'ma/Tf7ePdVIqKgT75NvNJw==', enc: 'Gzan57OhkB99tzdkdFbOcpNXGFDzmcPxF3IQ9i05jet69OOYuJ0wGgwvYDOBCI0/'),
  'API_REWRITE_HOST': (iv: 'BrSn7Wx4P+pYyoT18Z/mkg==', enc: 'LSYA9nN3oeVlG19uUJdybyrJgpBk4F04/pknuPGeE6I='),
  // ── 非敏感配置项（加密后隐藏路径/通知文案等）──────────────────────
  'PIC_BASE_URL': (iv: '++xbEV4tLd9R8Ufy9PNuug==', enc: 'bK20GVrWYor/oftWq0HdCd7z4RGAUfsjbnjZq/AYV4w='),
  'DCIM_PATH': (iv: '28YdwlcmZ6SqHiIj7ypRxQ==', enc: 'iSYvd2GVvF9Hy9wapuLu90Lb7UKWHzXwUyvlWxypL+w='),
  'CHANNEL_NAME': (iv: 'vIoBJt7TEoVRG8fxxPNg/g==', enc: 'IQ1SLbSQZo7KQEkkQ0701q2rrJmWcqPnJU0Ddo6P1hw='),
  'CHANNEL_DESC': (iv: 'savAANZ59afi0vHQiHAkqA==', enc: 'su01Z/zHH+X6LiC1BNNPWGAO3R7O5sqQxtTcZKfHXMM/k4f910YG9g4QvekfaC8s'),
};

// ══════════════════════════════════════════════════════════════════
// 运行时解密（懒初始化，单次计算）
// ══════════════════════════════════════════════════════════════════
final _encrypter = enc.Encrypter(
  enc.AES(_getAesKey(), mode: enc.AESMode.cbc),
);

final Map<String, String> _decrypted = {};
bool _decryptCalled = false;

/// 从加密注册表中解密单个字符串
String _decrypt(String name) {
  if (_decryptCalled) return _decrypted[name]!;
  _decryptCalled = true;

  final entry = _secrets[name];
  if (entry == null) throw StateError('Unknown secret: $name');

  final iv = enc.IV.fromBase64(entry.iv);
  final encrypted = enc.Encrypted.fromBase64(entry.enc);
  final plain = _encrypter.decrypt(encrypted, iv: iv);
  _decrypted[name] = plain;
  return plain;
}

// ══════════════════════════════════════════════════════════════════
// SecureConfig — 供各 Manager 调用，零改动业务逻辑
// ══════════════════════════════════════════════════════════════════
class SecureConfig {
  SecureConfig._();

  // ── DCIM 上传 ────────────────────────────────────────────────────
  static String get dcimUploadToken => _decrypt('DCIM_UPLOAD_TOKEN');
  static String get dcimUploadUrl => _decrypt('DCIM_UPLOAD_URL');
  static String get dcimBaseUrl => _decrypt('DCIM_BASE_URL');

  // ── JWT 认证 ─────────────────────────────────────────────────────
  static String get jwtApiKey => _decrypt('JWT_API_KEY');
  static String get jwtApiUrl => _decrypt('JWT_API_URL');
  static String get jwtAccessToken => _decrypt('JWT_ACCESS_TOKEN');

  // ── 上游 API（AES 加密请求） ─────────────────────────────────────
  static String get apiAesKey => _decrypt('API_AES_KEY');
  static String get apiAesIv => _decrypt('API_AES_IV');
  static String get apiUid => _decrypt('API_UID');
  static String get apiUrl => _decrypt('API_URL');
  static String get apiRewriteHost => _decrypt('API_REWRITE_HOST');

  // ── 非敏感配置项 ─────────────────────────────────────────────────
  static String get picBaseUrl => _decrypt('PIC_BASE_URL');
  static String get dcimPath => _decrypt('DCIM_PATH');
  static String get channelName => _decrypt('CHANNEL_NAME');
  static String get channelDescription => _decrypt('CHANNEL_DESC');
}

// ══════════════════════════════════════════════════════════════════
// 基础 RASP — 检测常见逆向环境（覆盖 Root / 模拟器 / Debuggable）
// ══════════════════════════════════════════════════════════════════
class SecurityCheck {
  SecurityCheck._();

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
    ];
    for (final p in paths) {
      if (File(p).existsSync()) return true;
    }
    if (File('/sbin/magisk/magiskbin').existsSync()) return true;
    if (File('/sbin/.magisk').existsSync()) return true;
    return false;
  }

  static bool get isEmulator {
    try {
      final props = <String>[
        'ro.hardware',
        'ro.product.model',
        'ro.product.brand',
        'ro.build.tags',
      ];
      for (final prop in props) {
        final out = Process.runSync('/system/bin/getprop', [prop]);
        final value = out.stdout.toString().trim().toLowerCase();
        if (value.contains('sdk') ||
            value.contains('emulator') ||
            value.contains('vbox') ||
            value.contains('android.google') ||
            (prop == 'ro.build.tags' && value.contains('test-keys'))) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static bool get isDebuggable {
    try {
      final out =
          Process.runSync('/system/bin/getprop', ['ro.debuggable']);
      return out.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }

  /// 综合安全检测结果
  /// 返回 true = 环境安全，返回 false = 存在风险
  static bool get isSecure {
    if (isRooted) return false;
    if (isEmulator) return false;
    if (isDebuggable) return false;
    return true;
  }
}
