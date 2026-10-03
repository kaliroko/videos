/// 远程配置管理器 —— 读取 Supabase 里的 app_config 表
/// - 公告开关 + 内容
/// - App 远程开关
///
/// ★ 复用 AnalyticsManager 已初始化的 Supabase 客户端
/// ★ fetch() 返回 AppConfig? —— null 表示"没拉到"（网络失败/超时）
///   调用方必须区分：null → 什么都不做；非 null 才按配置处理
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_config.dart';
import 'analytics_manager.dart';

class RemoteConfigManager {
  RemoteConfigManager._();

  static const String _kTableName = 'app_config';
  static const String _kLastAnnouncementKey =
      'last_announcement_updated_at';

  /// ★ 拉取配置。
  /// 成功 → 返回 AppConfig
  /// 失败/超时/表空 → 返回 null（调用方不要做任何判断）
  static Future<AppConfig?> fetch() async {
    try {
      await AnalyticsManager.instance.init();

      final data = await Supabase.instance.client
          .from(_kTableName)
          .select()
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (data == null) {
        debugPrint('[RemoteConfig] ⚠️ app_config 表里没有 id=1 的行');
        return null;
      }

      final cfg = AppConfig.fromMap(data);
      debugPrint('[RemoteConfig] ✅ 已加载: '
          'app_enabled=${cfg.appEnabled}, '
          'announcement=${cfg.announcementEnabled}');
      return cfg;
    } catch (e) {
      debugPrint('[RemoteConfig] ❌ 拉取失败: $e');
      return null;   // ★ 明确返回 null，不做 fallback
    }
  }

  static Future<bool> shouldShowAnnouncement(AppConfig cfg) async {
    if (!cfg.announcementEnabled) return false;
    if (cfg.announcementContent.trim().isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_kLastAnnouncementKey);
    return last != cfg.updatedAt;
  }

  static Future<void> markAnnouncementShown(AppConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastAnnouncementKey, cfg.updatedAt);
  }
}