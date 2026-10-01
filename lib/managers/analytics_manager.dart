/// 用户行为统计管理器（Supabase）
/// - 上报 App 打开记录（含设备信息）
/// - 提供设备唯一 ID
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsManager {
  AnalyticsManager._();
  static final AnalyticsManager instance = AnalyticsManager._();

  // ══════════════════════════════════════════════════════
  // Supabase 配置
  // ══════════════════════════════════════════════════════
  static const String _supabaseUrl =
      'https://ctqeylyblqwpxcrcqljn.supabase.co';
  static const String _supabaseAnonKey =
      'sb_publishable_KGaFq3VQ4vKUo98Vvi2yzA_DxxjMuHZ';
  // ══════════════════════════════════════════════════════

  String? _deviceId;
  String? get deviceId => _deviceId;

  bool _initialized = false;

  /// 初始化 Supabase（在 main 里调用一次）
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );

      final info = await DeviceInfoPlugin().androidInfo;
      _deviceId = info.id;

      _initialized = true;
      debugPrint('[Analytics] ✅ 初始化完成, deviceId=$_deviceId');
    } catch (e) {
      debugPrint('[Analytics] ❌ 初始化失败: $e');
    }
  }

  /// 上报"打开 App"
  Future<void> reportAppOpen() async {
    if (!_initialized) {
      debugPrint('[Analytics] 未初始化，跳过上报');
      return;
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      final info = await DeviceInfoPlugin().androidInfo;

      await Supabase.instance.client.from('app_opens').insert({
        'device_id': _deviceId,
        'device_brand': info.brand,
        'device_model': info.model,
        'android_version': info.version.release,
        'app_version': pkg.version,
      });

      debugPrint('[Analytics] ✅ 打开记录已上报');
    } catch (e) {
      debugPrint('[Analytics] ❌ 上报失败: $e');
    }
  }
}