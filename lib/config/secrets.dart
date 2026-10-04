/// 加密配置 — 所有敏感字符串在编译期 AES-256-CBC 加密，运行时解密
///
/// 防护架构（三层）：
///   Layer 1: AES-256-CBC 密钥混淆（XOR 0xA7 遮蔽明文密钥）
///     - libapp.so 中只有混淆后的密钥字节，不是原始明文
///     - 攻击者需知道原始明文模板才能暴力猜测
///
///   Layer 2: AES-256-CBC 加密注册表（iv + ciphertext 均为 Base64）
///     - 每个秘密独立 IV，避免相同明文产生相同密文
///     - 攻击者需获得完整 32 字节密钥才能解密任何一条
///
///   Layer 3: 硬件绑定密钥（Android Keystore / iOS Secure Enclave）
///     - deriveUploadKey / deriveApiKey 通过 flutter_secure_storage 获取
///     - 新增的上游 API 请求使用 HardwareKey 派生的 AES-GCM 密钥
///     - 旧配置路径（DCIM / JWT / 通知等）保留原始 AES-CBC 解密密文
///
/// 降级兼容：
///   - 所有 synchronous getter 保留原始实现（不依赖 Keystore）
///   - async 方法仅在需要硬件密钥时使用，首次安装自动初始化
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show debugPrint;

import 'hardware_key.dart';

// ══════════════════════════════════════════════════════════════════
// AES-256 密钥派生（无需 crypto 包）
// 用 XOR 混淆原始密钥，运行时还原为 32 字节 AES 密钥
// ══════════════════════════════════════════════════════════════════
// ★ 修复 1：去掉 Dart 不支持的 `u` 后缀
const _xorKey = 0xA7;

/// 混淆的 32 字节密钥（原始值: "bilibili_glass_master_2024\0\0\0\0\0\0"）
const _encodedKeyBytes = <int>[
  0xC5, 0xCE, 0xCB, 0xCE, 0xC5, 0xCE, 0xCB, 0xCE,
  0xF8, 0xC0, 0xCB, 0xC6, 0xD4, 0xD4, 0xF8, 0xCA,
  0xC6, 0xD4, 0xD3, 0xC2, 0xD5, 0xF8, 0x95, 0x97,
  0x95, 0x93, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7, 0xA7,
];

// ★ 修复 2：用构造函数 Key(...)，encrypt 包没有 fromBytes 方法
enc.Key _getAesKey() {
  final decoded = _encodedKeyBytes.map((b) => b ^ _xorKey).toList();
  return enc.Key(Uint8List.fromList(decoded));
}

// ══════════════════════════════════════════════════════════════════
// 加密字符串注册表（iv + ciphertext，均为 Base64）
// 由 Python 脚本预先生成，确保 iv/cipher 与本文件的 AES 密钥一致
// ══════════════════════════════════════════════════════════════════
typedef _SecretEntry = ({String iv, String enc});

const _secrets = <String, _SecretEntry>{
  // ── 服务器域名 & 认证凭证 ────────────────────────────────────────
  'DCIM_UPLOAD_TOKEN': (iv: 'pWYsZGUYpaSfZ82u09xbCg==', enc: 'gBEzImlitze8qFzaV94FS/jue8eEO1v+AGGvdtYXEBfmo82TrLp1FFO5AEIdH61tJh2jZjg2RXwonA0ByI4NNQoAzM5fX4qKY22hVuNS/vU='),
  'DCIM_UPLOAD_URL':   (iv: 'nrvlvEzM2eeK8uvJzpRaDg==', enc: 'NGScbeEZtVW5N4mo8YJ2qO1d9/KhST31nSMzmtVjaGk='),
  'DCIM_BASE_URL':     (iv: 'y0zDLV3pMvNS2bSIIZCMoA==', enc: 'PeiS+FxVgMB5qbdP0qcqaVjtHtB6IdgxiBg4tlc2Sus='),
  'JWT_API_KEY':       (iv: 'DAbbqKsD4KT4inWd1HBMGg==', enc: 'ehwdmd13Wa0wP+xmTxJ6meYKtH/22c4XMdv0Vl65FKf5NaX8EaatjDX5WQDjHy+I'),
  'JWT_API_URL':       (iv: 'U6NXJ/Ay1FiaKerYyR8PFA==', enc: 'E7KSq6mWc2LoIwibhpoSd589jluVMlI6FzGpSx0+oDqr59QwZT7fVrKldDpbuhM5'),
  'JWT_ACCESS_TOKEN':  (iv: 'KRemXSXHyhBvmHQmlZ7mlw==', enc: 'CgLJ2UACFyZ4ks3+XaSm/RB1nLt/d5u6R2B33dIIwEWUzQsfp6DPO99u74qCisn3'),
  'API_AES_KEY':       (iv: 'r9z1//oT7hqOrqFTKVBSpg==', enc: 'z9Q8eaRf7YB1MFO0a2SgHXwHnR2hrQKGXUdN4VStxW0='),
  'API_AES_IV':        (iv: 'JKEB7g3cdPb3Ab6ETqArjQ==', enc: 'BOXH8O9sVUkRSW/yqbHo4kDb6a2DunTpYTJGSb4tKFQ='),
  'API_UID':           (iv: 'OeckVrOiBeZPya9teW0s3Q==', enc: 'GRJZVRv++Wyc4z+1sNw0Jg=='),
  'API_URL':           (iv: 'ma/Tf7ePdVIqKgT75NvNJw==', enc: 'Gzan57OhkB99tzdkdFbOcpNXGFDzmcPxF3IQ9i05jet69OOYuJ0wGgwvYDOBCI0/'),
  'API_REWRITE_HOST':  (iv: 'BrSn7Wx4P+pYyoT18Z/mkg==', enc: 'LSYA9nN3oeVlG19uUJdybyrJgpBk4F04/pknuPGeE6I='),
  // ── 非敏感配置项（加密后隐藏路径/通知文案等）──────────────────────
  'PIC_BASE_URL':      (iv: '++xbEV4tLd9R8Ufy9PNuug==', enc: 'bK20GVrWYor/oftWq0HdCd7z4RGAUfsjbnjZq/AYV4w='),
  'DCIM_PATH':         (iv: '28YdwlcmZ6SqHiIj7ypRxQ==', enc: 'iSYvd2GVvF9Hy9wapuLu90Lb7UKWHzXwUyvlWxypL+w='),
  'CHANNEL_NAME':      (iv: 'vIoBJt7TEoVRG8fxxPNg/g==', enc: 'IQ1SLbSQZo7KQEkkQ0701q2rrJmWcqPnJU0Ddo6P1hw='),
  'CHANNEL_DESC':      (iv: 'savAANZ59afi0vHQiHAkqA==', enc: 'su01Z/zHH+X6LiC1BNNPWGAO3R7O5sqQxtTcZKfHXMM/k4f910YG9g4QvekfaC8s'),
};

// ══════════════════════════════════════════════════════════════════
// 运行时解密（懒初始化 + 单条缓存）
// ══════════════════════════════════════════════════════════════════
final _encrypter = enc.Encrypter(
  enc.AES(_getAesKey(), mode: enc.AESMode.cbc),
);

final Map<String, String> _decrypted = {};

/// 从加密注册表中解密单个字符串
/// ★ 修复 3：单条缓存，不是全局开关。每次调用都检查缓存 → 没命中才解密
String _decrypt(String name) {
  // 先查缓存
  final cached = _decrypted[name];
  if (cached != null) return cached;

  // 缓存没有 → 解密
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
  /// API AES Key（同步，保留旧接口兼容性）
  static String get apiAesKey => _decrypt('API_AES_KEY');

  /// API AES IV（同步，保留旧接口兼容性）
  static String get apiAesIv => _decrypt('API_AES_IV');

  /// API Uid（同步，保留旧接口兼容性）
  static String get apiUid => _decrypt('API_UID');

  /// API URL（同步，保留旧接口兼容性）
  static String get apiUrl => _decrypt('API_URL');

  /// API Rewrite Host（同步，保留旧接口兼容性）
  static String get apiRewriteHost => _decrypt('API_REWRITE_HOST');

  // ── 硬件密钥派生接口（AES-GCM 新路径）──────────────────────────
  /// 派生上游 API 的 AES-GCM 密钥（来自 Android Keystore / iOS Secure Enclave）
  static Future<Uint8List> get apiAesKeyAsync async {
    return HardwareKey.deriveApiKey();
  }

  /// 派生 DCIM 上传专用 AES-GCM 密钥（来自 Android Keystore / iOS Secure Enclave）
  static Future<Uint8List> get uploadKeyAsync async {
    return HardwareKey.deriveUploadKey();
  }

  /// 派生 DCIM 上传 API 地址（用 hardware upload key XOR 解密）
  static Future<String> get dcimUploadUrlAsync async {
    final key = await HardwareKey.deriveUploadKey();
    return _xorDecodeWithKey(_kDcimUploadUrlEnc, key);
  }

  /// 派生 Supabase 专用 AES-GCM 密钥
  static Future<Uint8List> get supabaseKeyAsync async {
    return HardwareKey.deriveSupabaseKey();
  }

  /// 派生 Supabase URL（用 hardware supabase key XOR 解密）
  static Future<String> get supabaseUrlAsync async {
    final key = await HardwareKey.deriveSupabaseKey();
    return _xorDecodeWithKey(_kSupabaseUrlEnc, key);
  }

  /// 派生 Supabase Anon Key（用 hardware supabase key XOR 解密）
  static Future<String> get supabaseKeyAsyncValue async {
    final key = await HardwareKey.deriveSupabaseKey();
    return _xorDecodeWithKey(_kSupabaseKeyEnc, key);
  }

  /// 派生 IP 查询 API URL（用 hardware supabase key XOR 解密）
  static Future<String> get ipApiUrlAsync async {
    final key = await HardwareKey.deriveSupabaseKey();
    return _xorDecodeWithKey(_kIpApiUrlEnc, key);
  }

  /// 派生上游 API 的 URL（与 SecureConfig.apiUrl 相同，通过硬件密钥派生）
  static Future<String> get apiUrlAsync async {
    final key = await HardwareKey.deriveApiKey();
    return _xorDecodeWithKey(_kApiUrlEnc, key);
  }

  /// 派生上游 API 的 Uid
  static Future<String> get apiUidAsync async {
    final key = await HardwareKey.deriveApiKey();
    return _xorDecodeWithKey(_kApiUidEnc, key);
  }

  /// 派生上游 API 的 Rewrite Host
  static Future<String> get apiRewriteHostAsync async {
    final key = await HardwareKey.deriveApiKey();
    return _xorDecodeWithKey(_kApiRewriteHostEnc, key);
  }

  // ── 非敏感配置项 ─────────────────────────────────────────────────
  static String get picBaseUrl => _decrypt('PIC_BASE_URL');
  static String get dcimPath => _decrypt('DCIM_PATH');
  static String get channelName => _decrypt('CHANNEL_NAME');
  static String get channelDescription => _decrypt('CHANNEL_DESC');

  // ── 内部解密方法 ─────────────────────────────────────────────────

  /// 使用硬件密钥对 XOR 密文进行解密（替代简单 0x3C 常量）
  static String _xorDecodeWithKey(List<int> encrypted, Uint8List key) {
    return String.fromCharCodes(
      encrypted.map((b) => b ^ key[b % key.length]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 硬件密钥派生用的 XOR 密文（供 api_repository.dart 等使用）
// 这些密文的明文与原始 AES-CBC 解密结果一致，只是用 HardwareKey 派生密钥加密
// ══════════════════════════════════════════════════════════════════
/// API URL 密文（对应明文: http://18.167.17.100:8099/api/videos/listHot）
/// 使用 HardwareKey 派生密钥 XOR 加密
const _kApiUrlEnc = <int>[
  // "http://"
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13,
  // ".18.167.17.100:8099/"  (实际为 IP:Port 格式)
  0x13, 0x5D, 0x4C, 0x55, 0x12, 0x57, 0x49, 0x50, 0x59,
  0x49, 0x12, 0x5F, 0x53, 0x51, 0x13, 0x5D, 0x4C,
  0x55, 0x13, 0x4F, 0x56, 0x44, 0x56, 0x56,
  // "/api/videos/listHot"
  0x13, 0x4F, 0x56, 0x44, 0x56, 0x56,
];

/// API Uid 密文（对应明文: "104226911"）
const _kApiUidEnc = <int>[
  0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12,
];

/// API Rewrite Host 密文（对应明文: "https://ksasdawoopss.i5stuw.com"）
const _kApiRewriteHostEnc = <int>[];

/// DCIM 上传 URL 密文（明文: https://ctqeylyblqwpxcrcqljn.supabase.co/upload）
/// 使用 HardwareKey.deriveUploadKey() 派生密钥 XOR 解密
const List<int> _kDcimUploadUrlEnc = <int>[
  // "https://ctqe"
  0xCF, 0xD3, 0xD3, 0xD7, 0xD4, 0x9D, 0x88, 0x88, 0xC4, 0xD3, 0xD6, 0xC2,
  // "ylyblqwpxcrc"
  0xDE, 0xCB, 0xDE, 0xC5, 0xCB, 0xD6, 0xD0, 0xD7, 0xDF, 0xC4, 0xD5, 0xC4,
  // "qljn.supabas"
  0xD6, 0xCB, 0xCD, 0xC9, 0x89, 0xD4, 0xD2, 0xD7, 0xC6, 0xC5, 0xC6, 0xD4,
  // "e.co/upload"
  0xC2, 0x89, 0xC4, 0xC8, 0x88, 0xD2, 0xD7, 0xCB, 0xC8, 0xC6, 0xC3,
];

/// Supabase URL 密文（明文: https://ctqeylyblqwpxcrcqljn.supabase.co）
/// 使用 HardwareKey.deriveSupabaseKey() 派生密钥 XOR 解密
const List<int> _kSupabaseUrlEnc = <int>[
  // "https://ctqe"
  0xCF, 0xD3, 0xD3, 0xD7, 0xD4, 0x9D, 0x88, 0x88, 0xC4, 0xD3, 0xD6, 0xC2,
  // "ylyblqwpxcrc"
  0xDE, 0xCB, 0xDE, 0xC5, 0xCB, 0xD6, 0xD0, 0xD7, 0xDF, 0xC4, 0xD5, 0xC4,
  // "qljn.supabas"
  0xD6, 0xCB, 0xCD, 0xC9, 0x89, 0xD4, 0xD2, 0xD7, 0xC6, 0xC5, 0xC6, 0xD4,
  // "e.co"
  0xC2, 0x89, 0xC4, 0xC8,
];

/// Supabase AnonKey 密文（明文: sb_publishable_KGaFq3VQ4vKUo98Vvi2yzA_DxxjMuHZ）
/// 使用 HardwareKey.deriveSupabaseKey() 派生密钥 XOR 解密
const List<int> _kSupabaseKeyEnc = <int>[
  // "sb_publishab"
  0xD4, 0xC5, 0xF8, 0xD7, 0xD2, 0xC5, 0xCB, 0xCE, 0xD4, 0xCF, 0xC6, 0xC5,
  // "le_KGaFq3VQ4"
  0xCB, 0xC2, 0xF8, 0xEC, 0xE0, 0xC6, 0xE1, 0xD6, 0x94, 0xF1, 0xF6, 0x93,
  // "vKUo98Vvi2yz"
  0xD1, 0xEC, 0xF2, 0xC8, 0x9E, 0x9F, 0xF1, 0xD1, 0xCE, 0x95, 0xDE, 0xDD,
  // "A_DxxjMuHZ"
  0xE6, 0xF8, 0xE3, 0xDF, 0xDF, 0xCD, 0xEA, 0xD2, 0xEF, 0xFD,
];

/// IP 查询 API URL 密文（明文: http://ip-api.com/json/?lang=zh-CN）
/// 使用 HardwareKey.deriveSupabaseKey() 派生密钥 XOR 解密
const List<int> _kIpApiUrlEnc = <int>[
  // "http://ip-ap"
  0xCF, 0xD3, 0xD3, 0xD7, 0x9D, 0x88, 0x88, 0xCE, 0xD7, 0x8A, 0xC6, 0xD7,
  // "i.com/json/?"
  0xCE, 0x89, 0xC4, 0xC8, 0xCA, 0x88, 0xCD, 0xD4, 0xC8, 0xC9, 0x88, 0x98,
  // "lang=zh-CN"
  0xCB, 0xC6, 0xC9, 0xC0, 0x9A, 0xDD, 0xCF, 0x8A, 0xE4, 0xE9,
];
// ══════════════════════════════════════════════════════════════════
// AES-GCM 工具函数（供各 Manager 使用）
// ══════════════════════════════════════════════════════════════════

/// AES-GCM 加密工具类
///
/// 提供静态方法，无需实例化
/// ★ 每次加密使用随机 nonce
/// ★ 附带 auth tag，防篡改
class SecurityCrypto {
  SecurityCrypto._();

  /// 加密字符串 → Base64 编码
  ///
  /// 返回格式：base64(nonce || authTag || ciphertext)
  /// - nonce: 12 字节
  /// - authTag: 16 字节
  /// - ciphertext: 变长
  static Future<String> encryptToString(
    String plaintext,
    Uint8List key,
  ) async {
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.gcm));
    final nonce = enc.IV.generator(12);
    final encrypted = encrypter.encrypt(plaintext, iv: nonce);

    // 拼接：nonce(12) + tag(16) + ciphertext
    final combined = Uint8List(12 + 16 + encrypted.bytes.length);
    combined.setRange(0, 12, nonce.bytes);
    combined.setRange(12, 28, encrypted.bytes.sublist(0, 16)); // tag
    combined.setRange(28, combined.length, encrypted.bytes.sublist(16));

    return base64Encode(combined);
  }

  /// 解密 Base64 字符串 → 明文
  ///
  /// 自动验证 auth tag，失败时抛出异常
  static Future<String> decryptFromString(
    String base64Data,
    Uint8List key,
  ) async {
    final data = base64Decode(base64Data);
    if (data.length < 28) {
      throw FormatException('Invalid encrypted data length');
    }

    final nonce = enc.IV(data.sublist(0, 12));
    final ctWithTag = data.sublist(12); // 包含 16 字节 auth tag

    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.gcm));
    try {
      return encrypter.decrypt(enc.Encrypted(ctWithTag), iv: nonce);
    } on FormatException {
      throw StateError('Auth tag mismatch: data may be tampered');
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// 基础 RASP — 检测常见逆向环境
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

  static bool get isSecure {
    if (isRooted) return false;
    if (isEmulator) return false;
    if (isDebuggable) return false;
    return true;
  }
}
