library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_config.dart';
import 'analytics_manager.dart';

class RemoteConfigManager {
  RemoteConfigManager._();

  static const String _kTableName = 'app_config';
  static const String _kLastAnnouncementKey = 'last_announcement_updated_at';

  // ★ 禁用状态缓存
  static const String _kCachedDisabledKey = 'cached_disabled';
  static const String _kCachedDisabledReasonKey = 'cached_disabled_reason';

  // ── 拉取远程配置 ────────────────────────────────────────────────
  static Future<AppConfig?> fetch() async {
    try {
      await AnalyticsManager.instance.init();

      final data = await Supabase.instance.client
          .from(_kTableName)
          .select()
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (data == null) return null;
      return AppConfig.fromMap(data);
    } catch (e) {
      debugPrint('[RemoteConfig] ❌ 拉取失败: $e');
      return null;
    }
  }

  // ── ★ 禁用状态缓存读写 ────────────────────────────────────────
  static Future<bool> isCachedDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCachedDisabledKey) ?? false;
  }

  static Future<String> cachedDisabledReason() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCachedDisabledReasonKey) ?? '服务已暂停，请稍后再试';
  }

  static Future<void> saveDisabledState(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCachedDisabledKey, true);
    await prefs.setString(_kCachedDisabledReasonKey, reason);
    debugPrint('[RemoteConfig] 💾 缓存禁用状态: $reason');
  }

  static Future<void> clearDisabledState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedDisabledKey);
    await prefs.remove(_kCachedDisabledReasonKey);
    debugPrint('[RemoteConfig] 🧹 清除禁用缓存');
  }

  // ── 公告相关 ────────────────────────────────────────────────────
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