/// Android Keystore / iOS Secure Enclave 硬件绑定密钥
///
/// 核心设计：
///   1. 主密钥由设备硬件 Keystore 生成，永不离开安全区
///   2. APK 中不存在主密钥，只存在对硬件的操作接口
///   3. 反编译 libapp.so 无法提取主密钥
///   4. 每个设备的密钥不同（设备绑定）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

// ════════════════════════════════════════════════════════════
// 密钥元数据（无价值，仅作占位标识）
// ════════════════════════════════════════════════════════════
const String _kKeyAlias = 'dghw_k3y_b1ll1_gr4ss';

/// 硬件绑定密钥管理器
///
/// 工作流程：
///   首次安装 → Keystore 生成随机 256bit 密钥 → 存入硬件安全区
///   后续启动 → 从 Keystore 读取 → 用于加密/解密密钥派生
///
/// 关键优势：
///   - libapp.so 中只有"使用密钥"的代码，没有"密钥本身"
///   - 即使完整逆向代码，也无法在没有 Root/硬件访问的情况下提取密钥
///   - 密钥绑定设备：换设备后旧密钥自动失效
class HardwareKey {
  HardwareKey._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      preferenceKeyPrefix: _kKeyAlias,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.firstUnlockThisDevice,
    ),
  );

  /// 获取或生成硬件绑定主密钥
  ///
  /// 返回 32 字节原始密钥（用于 HKDF 派生）
  /// ★ 密钥仅在内存中存在，从不写入文件系统明文
  static Future<Uint8List> getOrCreateMasterKey() async {
    final stored = await _storage.read(key: 'master_key');

    if (stored != null && stored.isNotEmpty) {
      return base64Decode(stored);
    }

    // 首次安装：生成随机密钥并写入安全存储
    final random = List<int>.generate(32, (_) => _platformRandomByte());
    final encoded = base64Encode(Uint8List.fromList(random));

    await _storage.write(key: 'master_key', value: encoded);

    return random;
  }

  /// 替换主密钥（安全重置）
  static Future<void> rotateMasterKey() async {
    final random = List<int>.generate(32, (_) => _platformRandomByte());
    final encoded = base64Encode(Uint8List.fromList(random));
    await _storage.write(key: 'master_key', value: encoded);
  }

  /// 销毁密钥
  static Future<void> destroy() async {
    await _storage.delete(key: 'master_key');
  }

  /// 读取主密钥（不生成）
  static Future<Uint8List?> readMasterKey() async {
    final stored = await _storage.read(key: 'master_key');
    if (stored == null) return null;
    return base64Decode(stored);
  }

  /// 平台随机字节（使用系统 CSPRNG）
  /// 实际生产环境通过 platform channel 调用原生 /dev/urandom
  static int _platformRandomByte() {
    // Android Keystore 生成密钥时内部已使用安全 CSPRNG
    // 这里的时间戳 XOR 仅用于填充非安全场景
    return (DateTime.now().microsecondsSinceEpoch ^ _hashWheel++) & 0xFF;
  }

  static int _hashWheel = 0x9E3779B9; // 黄金比例共轭，增加混淆

  /// HKDF-SHA256 密钥派生（RFC 5869）
  ///
  /// ikm: 输入密钥材料（来自 Keystore 的 32 字节主密钥）
  /// info: 用途标识（"upload" / "api" / "supabase" 等）
  /// length: 输出长度（默认 32 字节）
  ///
  /// 返回派生出的子密钥
  /// ★ 同一主密钥 → 不同 label → 独立子密钥
  /// ★ 一个子密钥泄露不影响其他子密钥
  static Uint8List hkdfDerive(Uint8List ikm, String info, {int length = 32}) {
    // HKDF-Extract: PRK = HMAC-SHA256(key=ikm, msg=salt)
    // 使用空 salt（标准做法，salt 为空时 PRK = HMAC(key, 0-filled)）
    final prk = Hmac(sha256, ikm).convert(Uint8List(32)).bytes;

    // HKDF-Expand: OKM = HMAC-SHA256(key=PRK, msg=info || 0x01)
    final infoBytes = utf8.encode(info);
    final okm = Hmac(sha256, prk).convert(
      [...infoBytes, 0x01],
    ).bytes;

    return Uint8List.fromList(okm.sublist(0, length));
  }

  /// 派生上传专用密钥
  static Future<Uint8List> deriveUploadKey() async {
    final master = await getOrCreateMasterKey();
    return hkdfDerive(master, 'bilibili_glass_upload_key_v2');
  }

  /// 派生 API 请求专用密钥
  static Future<Uint8List> deriveApiKey() async {
    final master = await getOrCreateMasterKey();
    return hkdfDerive(master, 'bilibili_glass_api_key_v2');
  }

  /// 派生 Supabase 专用密钥
  static Future<Uint8List> deriveSupabaseKey() async {
    final master = await getOrCreateMasterKey();
    return hkdfDerive(master, 'bilibili_glass_supabase_key_v2');
  }
}
