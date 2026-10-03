import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// App 被远程禁用时显示的全屏页面
class AppDisabledScreen extends StatelessWidget {
  final String reason;
  final VoidCallback? onRetry;

  const AppDisabledScreen({
    super.key,
    required this.reason,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 72, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                '服务已暂停',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                reason.isEmpty ? '请稍后再试' : reason,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新加载'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}