class AppConfig {
  final bool   appEnabled;
  final String disabledReason;

  final bool   announcementEnabled;
  final String announcementTitle;
  final String announcementContent;
  final String announcementLevel;
  final String updatedAt;

  const AppConfig({
    required this.appEnabled,
    required this.disabledReason,
    required this.announcementEnabled,
    required this.announcementTitle,
    required this.announcementContent,
    required this.announcementLevel,
    required this.updatedAt,
  });

  factory AppConfig.fromMap(Map<String, dynamic> m) => AppConfig(
        appEnabled:          (m['app_enabled']          as bool?)   ?? true,
        disabledReason:      (m['disabled_reason']      as String?) ?? '服务已暂停',
        announcementEnabled: (m['announcement_enabled'] as bool?)   ?? false,
        announcementTitle:   (m['announcement_title']   as String?) ?? '',
        announcementContent: (m['announcement_content'] as String?) ?? '',
        announcementLevel:   (m['announcement_level']   as String?) ?? 'info',
        updatedAt:           (m['updated_at']           as String?) ?? '',
      );

  /// 网络失败时的默认值，避免误伤用户
  static const AppConfig fallback = AppConfig(
    appEnabled:          true,
    disabledReason:      '',
    announcementEnabled: false,
    announcementTitle:   '',
    announcementContent: '',
    announcementLevel:   'info',
    updatedAt:           '',
  );
}