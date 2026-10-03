import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';

import '../config/debug_secret.dart';
import '../theme/app_theme.dart';

/// App 被远程禁用时显示的全屏页面
class AppDisabledScreen extends StatefulWidget {
  final String reason;
  final VoidCallback? onRetry;
  final bool retrying;

  /// 密钥验证通过时调用，参数是用户选择的放行时长
  final Future<bool> Function(Duration duration)? onDebugUnlock;

  /// ★ 用于 showDialog（因为本 widget 在 MaterialApp.builder 之上，
  ///   自身 context 拿不到 Navigator）
  final GlobalKey<NavigatorState>? navigatorKey;

  const AppDisabledScreen({
    super.key,
    required this.reason,
    this.onRetry,
    this.retrying = false,
    this.onDebugUnlock,
    this.navigatorKey,
  });

  @override
  State<AppDisabledScreen> createState() => _AppDisabledScreenState();
}

class _AppDisabledScreenState extends State<AppDisabledScreen> {
  /// ★ 获取可用的 dialog context
  /// 优先用 navigatorKey（Navigator 内部的 context），
  /// 因为本 widget 位于 builder 层，自身 context 没有 Navigator
  BuildContext? get _dialogContext {
    final navCtx = widget.navigatorKey?.currentContext;
    if (navCtx != null && navCtx.mounted) return navCtx;
    // 兜底：用自身 context（可能失败，但至少尝试一次）
    return mounted ? context : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Stack(
        children: [
          // ── 主内容 ──
          Center(
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
                    widget.reason.isEmpty ? '请稍后再试' : widget.reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (widget.onRetry != null)
                    FilledButton.icon(
                      onPressed: widget.retrying ? null : widget.onRetry,
                      icon: widget.retrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(widget.retrying ? '检查中…' : '重新加载'),
                    ),
                ],
              ),
            ),
          ),

          // ── 调试入口（底部居中）──
          if (widget.onDebugUnlock != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: _DebugEntry(
                  onTap: _openDebugDialog,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openDebugDialog() async {
    debugPrint('[Debug] 打开调试解锁弹窗');

    // ★ 关键：用 navigatorKey 的 context
    final ctx = _dialogContext;
    if (ctx == null) {
      debugPrint('[Debug] ❌ 没有可用的 context，无法弹窗');
      return;
    }

    final controller = TextEditingController();
    String? errorText;
    Duration selectedDuration = const Duration(hours: 1);
    bool keyVerified = false;
    final customHoursController = TextEditingController();

    await showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                '调试解锁',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 密钥输入 ──
                    TextField(
                      controller: controller,
                      autofocus: true,
                      enabled: !keyVerified,
                      obscureText: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: '输入调试密钥',
                        hintStyle:
                            const TextStyle(color: AppTheme.textTertiary),
                        errorText: errorText,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppTheme.textTertiary
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 时长选择（密钥通过后才显示）──
                    if (keyVerified) ...[
                      const Text(
                        '选择放行时长（最长 24 小时）',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kBypassPresets.map((d) {
                          final selected = d == selectedDuration;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedDuration = d;
                                customHoursController.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.accentColor
                                        .withValues(alpha: 0.18)
                                    : AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.accentColor
                                      : AppTheme.textTertiary
                                          .withValues(alpha: 0.3),
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                '${d.inHours}h',
                                style: TextStyle(
                                  color: selected
                                      ? AppTheme.accentColor
                                      : AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // 自定义小时输入
                      TextField(
                        controller: customHoursController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: '或输入小时数（1~24）',
                          hintStyle: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppTheme.textTertiary
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppTheme.accentColor,
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          final h = int.tryParse(v.trim());
                          if (h != null && h >= 1 && h <= 24) {
                            setDialogState(() {
                              selectedDuration = Duration(hours: h);
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // 第一步：验证密钥
                    if (!keyVerified) {
                      if (!verifyDebugKey(controller.text)) {
                        setDialogState(() => errorText = '密钥错误');
                        return;
                      }
                      setDialogState(() {
                        errorText = null;
                        keyVerified = true;
                      });
                      return;
                    }
                    // 第二步：解锁
                    Navigator.of(dialogCtx).pop();
                    _unlock(selectedDuration);
                  },
                  child: Text(
                    keyVerified ? '解锁' : '下一步',
                    style: const TextStyle(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _unlock(Duration duration) async {
    if (widget.onDebugUnlock == null) return;
    await widget.onDebugUnlock!(duration);
  }
}

/// 调试入口按钮（纯文字，无图标）
class _DebugEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _DebugEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.accentColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.accentColor,
            width: 1.2,
          ),
        ),
        child: Text(
          '调试',
          style: TextStyle(
            color: AppTheme.accentColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}