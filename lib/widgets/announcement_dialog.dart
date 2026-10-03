import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../theme/app_theme.dart';

/// 远程公告弹窗（info / warning / error 三种配色）
class AnnouncementDialog extends StatelessWidget {
  final AppConfig config;
  const AnnouncementDialog({super.key, required this.config});

  Color get _accent {
    switch (config.announcementLevel) {
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.redAccent;
      default:
        return AppTheme.accentColor;
    }
  }

  IconData get _icon {
    switch (config.announcementLevel) {
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.campaign_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, color: _accent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.announcementTitle.isEmpty
                        ? '公告'
                        : config.announcementTitle,
                    style: TextStyle(
                      color: _accent,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              config.announcementContent,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '知道了',
                  style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}