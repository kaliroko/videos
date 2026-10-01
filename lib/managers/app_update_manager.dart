/// App 更新检测管理器
/// - 启动时静默请求 GitHub Releases API
/// - 无更新：静默返回
/// - 有更新：弹出 MD3 + 弹簧 + 毛玻璃风格的弹窗
library;

import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateManager {
  AppUpdateManager._();
  static final AppUpdateManager instance = AppUpdateManager._();

  // ══════════════════════════════════════════════════════
  // 你的 GitHub 仓库信息
  // ══════════════════════════════════════════════════════
  static const String _owner = 'kaliroko';
  static const String _repo = 'videos';
  // ══════════════════════════════════════════════════════

  /// 检查间隔（避免频繁请求 GitHub API）
  static const Duration _checkInterval = Duration(hours: 6);
  static const String _kLastCheck = 'app_update_last_check';

  // ── 检查更新 ──────────────────────────────────────────
  /// 返回 UpdateInfo（有更新）；null（无更新或检查失败）
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    try {
      // 1. 节流：距上次检查不足 6h 就跳过
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final lastCheck = prefs.getInt(_kLastCheck) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastCheck < _checkInterval.inMilliseconds) {
          debugPrint('[AppUpdate] 距上次检查不足 '
              '${_checkInterval.inHours}h，跳过');
          return null;
        }
        await prefs.setInt(_kLastCheck, now);
      }

      // 2. 本地版本
      final local = await PackageInfo.fromPlatform();
      debugPrint('[AppUpdate] 本地版本: ${local.version}+${local.buildNumber}');

      // 3. 请求 GitHub API
      final url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final resp = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'bilibili-glass',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('[AppUpdate] GitHub API 返回 ${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final remoteVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;
      debugPrint('[AppUpdate] 远程版本: $remoteVersion (tag=$tagName)');

      // 4. 版本比对
      if (!_isNewerVersion(remoteVersion, local.version)) {
        debugPrint('[AppUpdate] 已是最新版本');
        return null;
      }

      // 5. 找 APK 附件
      final assets = data['assets'] as List<dynamic>? ?? [];
      String? downloadUrl;
      int apkSize = 0;
      for (final a in assets) {
        final asset = a as Map<String, dynamic>;
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }

      if (downloadUrl == null) {
        debugPrint('[AppUpdate] Release 里没找到 .apk 附件');
        return null;
      }

      return UpdateInfo(
        version: remoteVersion,
        releaseNotes: data['body'] as String? ?? '',
        downloadUrl: downloadUrl,
        apkSize: apkSize,
      );
    } catch (e) {
      debugPrint('[AppUpdate] 检查更新失败（静默）: $e');
      return null;
    }
  }

  /// 语义版本比较：remote > local 返回 true
  /// 支持任意段数，如 "2.1.0.42" vs "2.1.0.41"
  bool _isNewerVersion(String remote, String local) {
    try {
      final r = remote.split('.').map(int.parse).toList();
      final l = local.split('.').map(int.parse).toList();
      final maxLen = r.length > l.length ? r.length : l.length;
      for (int i = 0; i < maxLen; i++) {
        final rv = i < r.length ? r[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (rv > lv) return true;
        if (rv < lv) return false;
      }
      return false;
    } catch (e) {
      debugPrint('[AppUpdate] 版本号解析失败: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════
  // 弹窗：MD3 + 弹簧动画 + 毛玻璃
  // ══════════════════════════════════════════════════════
  Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'update',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (ctx, _, __) => _UpdateDialog(info: info),
      transitionBuilder: (ctx, anim, _, child) {
        // 弹簧曲线：先冲过头再回弹
        final springCurve = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );
        final scale = Tween<double>(begin: 0.7, end: 1.0).animate(springCurve);
        final fade = CurvedAnimation(
          parent: anim,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
        );

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 更新信息数据类
// ══════════════════════════════════════════════════════════════
class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final int apkSize;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.apkSize,
  });
}

// ══════════════════════════════════════════════════════════════
// MD3 + 毛玻璃 + 弹簧弹窗本体
// ══════════════════════════════════════════════════════════════
class _UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final glassColor = isDark
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.78);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.55);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 380,
              decoration: BoxDecoration(
                color: glassColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部图标 + 标题
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer
                                  .withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.system_update_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '发现新版本',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'v${info.version}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // 版本信息小卡片
                      if (info.apkSize > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.sd_storage_rounded,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${(info.apkSize / 1024 / 1024).toStringAsFixed(1)} MB',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 更新内容
                      if (info.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '更新内容',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: SingleChildScrollView(
                            child: Text(
                              info.releaseNotes.trim(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // 按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                            child: const Text('稍后'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              final uri = Uri.parse(info.downloadUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('立即更新'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}