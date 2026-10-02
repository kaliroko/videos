/// 加密配置 — 所有敏感字符串在编译期 AES-256-CBC 加密，运行时解密
/// 防御策略：
/// 1. 编译产物中无明文 token/key/url
/// 2. 运行时动态解密，内存中短暂出现明文后立即使用
/// 3. 基础 RASP：检测 Root / 模拟器 / Debuggable
library;

import 'dart:io';

import 'package:encrypt/encrypt.dart' as enc;

// ══════════════════════════════════════════════════════════════════
// AES-256 密钥（同样经 XOR 混淆，避免被 strings 直接扫描到）
// ══════════════════════════════════════════════════════════════════
const _xorKey = 0xA7; // 167

List<int> _xorDecode(List<int> encoded) =>
    encoded.map((b) => b ^ _xorKey).toList();

// 经 XOR 混淆的 32 字节 AES-256 密钥
// 原始值: "bilibili_glass_master_2024\0\0\0\0\0\0"
const _encodedKeyBytes = <int>[
  0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C,
  0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C,
  0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C,
  0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C, 0x8C,
];

enc.Key _getAesKey() =>
    enc.Key.fromBytes(_xorDecode(_encodedKeyBytes));

// ══════════════════════════════════════════════════════════════════
// 加密字符串注册表（iv + ciphertext，均为 Base64）
// ══════════════════════════════════════════════════════════════════
typedef _SecretEntry = ({String iv, String enc});

const _secrets = <String, _SecretEntry>{
  // ── 服务器域名 & 认证凭证 ────────────────────────────────────────
  'DCIM_UPLOAD_TOKEN': (
    iv: 'TUVyt8G9GrARUEbbaUboug==',
    enc:
        'F39he5LN/Su6A8V59unLZGkQMyo2glJ0rOYMQXFoJYBlmSOUbzMCA9T2Vwf8w+aIhtrh7yIu9xDfkVaNbYFmJf/b2ucb4cBWSuOstuEgDOg=',
  ),
  'DCIM_UPLOAD_URL': (
    iv: 'pz/5/7+vg2gafcYBDlc9pw==',
    enc: 'WE8x6v2AJaiu4vXa8UkwjY99HgJ0aoEht4j4ve+UGj0=',
  ),
  'DCIM_BASE_URL': (
    iv: 'GdjzIWsIKzBGuRU8WsCeIA==',
    enc: '7wIed8vPH6eSynq2cifz6OHPXaL5aaUpQZSRUD1q2Kc=',
  ),
  'JWT_API_KEY': (
    iv: 'stX8Y1svm8U/HpJzaIBp+w==',
    enc: 'f/Yh1uAG9xA5j2xBqPtbDmdJcG2HgcMKGh1tg1BP4fY0NxlkGi4EMlbQWrykMLoT',
  ),
  'JWT_API_URL': (
    iv: 'HBl1QmOFTPYDK+0t/dwBdg==',
    enc:
        'NsG4q48oi7SIEseVnJKg7liLVcCTDwawOUsVGsSOHMRwG6UPhMZjIHg6+anCjAKF',
  ),
  'JWT_ACCESS_TOKEN': (
    iv: '0qlqUib7gonOmHSrnEBiCA==',
    enc: '4zDoOonDgj3QAaWD0U1QUg18dQt25Ouow2X3BGca5AGs2ZzAkLhgi5O5cAiZ8A7s',
  ),
  'API_AES_KEY': (
    iv: 'kGzpZInrqsok8QTGLFJXtw==',
    enc: 'jWKXlMVK+KW9WaXnD5oYcC2Bly6awE2bQ/DRRxi0y0k=',
  ),
  'API_AES_IV': (
    iv: '4nQG4LfearOpxad0ERz7rw==',
    enc: 'RhMADuvKrJocEMOLMNI+deOitFoFxcQfBMwySxKMDkg=',
  ),
  'API_UID': (
    iv: '7PN2dpNQAuP+5oTzMEqD/A==',
    enc: 'hLydRsHaTGx7VcsewetVNw==',
  ),
  'API_URL': (
    iv: 'JyWA0ynjB8GQxjIuHdFejw==',
    enc:
        '+CnzDhY6n8TDTD0eZmtIWbE0QJwDYcrJ4OPSQbcVBRGjFwxUnfg8idgfzUmmx4IL',
  ),
  'API_REWRITE_HOST': (
    iv: 'xfE37+dXDo525VbL/LubCw==',
    enc: '+nqNaYe3CgOGBxJs40i6KMQHOLhgcRFLtne4cgXNyXg=',
  ),
  // ── 非敏感配置项（加密后隐藏路径/通知文案等）──────────────────────
  'PIC_BASE_URL': (
    iv: 'ODAKOEXp+3qcZ7GBymu7SQ==',
    enc: '2X3TrEUBHgSIY+KkVija8gRPxgGSUoQEcQKl5gRjgr4=',
  ),
  'DCIM_PATH': (
    iv: 'F73OPnmwmIjWU7S/ptIYBw==',
    enc: 'j5ZOXeeHKCv2OAk9JMyTYwWETohALsy12LmYXNC0yqc=',
  ),
  'CHANNEL_NAME': (
    iv: 'SLAE6MZinzCLoEn1q+uM3w==',
    enc: 'qwKopgKgPgWgDTOJ1dJQPOY5SxPLYgHZXFiioV+x7sQ=',
  ),
  'CHANNEL_DESC': (
    iv: 'SCqxV/QIPWyQPPMXHpuJzg==',
    enc: 'Q/gwkO6IRIWfE0NDyzGEjokZdZrnvbDmH4nwZz0Dnw0m3kVBZE7nK5kLL20UzecM',
  ),
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
  final encrypted =
      enc.Encrypted.fromBase64(entry.enc, urlSafe: false);
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
    // 方案1：经典 su 可执行文件路径
    const _rootPaths = [
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/system/bin/failsafe/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/.ext/su',
    ];
    for (final p in _rootPaths) {
      if (File(p).existsSync()) return true;
    }
    // 方案2：检测 Magisk 相关文件
    if (File('/sbin/magisk/magiskbin').existsSync()) return true;
    if (File('/sbin/.magisk').existsSync()) return true;
    return false;
  }

  static bool get isEmulator {
    // 方案：读取 Android 系统属性判断模拟器特征
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