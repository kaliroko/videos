import 'package:flutter/services.dart';

/// 签名校验 + APK 完整性校验
/// 依赖 Android 侧 IntegrityGuard.kt
class IntegrityGuard {
  IntegrityGuard._();

  static const MethodChannel _channel = MethodChannel('app/integrity');

  /// 校验签名（与 Kotlin 里硬编码的 SHA-256 比对）
  /// true = 签名正确
  static Future<bool> verifySignature() async {
    try {
      return await _channel.invokeMethod<bool>('verifySignature') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 校验 APK 完整性
  static Future<bool> verifyIntegrity() async {
    try {
      return await _channel.invokeMethod<bool>('verifyIntegrity') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 综合检测，返回 null 表示全部通过
  static Future<List<String>?> fullCheck() async {
    try {
      final r = await _channel
          .invokeMethod<List<dynamic>>('fullCheck');
      if (r == null) return null;
      return r.cast<String>();
    } catch (_) {
      return ['channel_error'];
    }
  }

  /// 仅用于开发阶段读取实际哈希，方便填 EXPECTED_*
  static Future<String> getActualSignatureHash() async {
    try {
      return await _channel.invokeMethod<String>('getSignatureHash') ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> getActualApkHash() async {
    try {
      return await _channel.invokeMethod<String>('getApkHash') ?? '';
    } catch (_) {
      return '';
    }
  }
}