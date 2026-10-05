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

  const AppDisabledScreen({
    super.key,
    required this.reason,
    this.onRetry,
    this.retrying = false,
    this.onDebugUnlock,
  });

  @override
  State<AppDisabledScreen> createState() => _AppDisabledScreenState();
}

class _AppDisabledScreenState extends State<AppDisabledScreen> {
  /// ★ 是否显示调试弹窗（纯 Stack 实现，不用 showDialog）
  bool _showDebugDialog = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  onTap: () {
                    setState(() => _showDebugDialog = true);
                  },
                ),
              ),
            ),

          // ── ★ 调试弹窗（纯 Stack 实现，不依赖 Navigator）──
          if (_showDebugDialog)
            Positioned.fill(
              child: _DebugDialog(
                onClose: () {
                  setState(() => _showDebugDialog = false);
                },
                onUnlock: (duration) async {
                  setState(() => _showDebugDialog = false);
                  if (widget.onDebugUnlock != null) {
                    await widget.onDebugUnlock!(duration);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ★ 调试弹窗（完全用 Stack 实现，不用 showDialog）
// ══════════════════════════════════════════════════════════════
class _DebugDialog extends StatefulWidget {
  final VoidCallback onClose;
  final Future<void> Function(Duration duration) onUnlock;

  const _DebugDialog({
    required this.onClose,
    required this.onUnlock,
  });

  @override
  State<_DebugDialog> createState() => _DebugDialogState();
}

class _DebugDialogState extends State<_DebugDialog> {
  final _keyController = TextEditingController();
  final _customHoursController = TextEditingController();

  String? _errorText;
  Duration _selectedDuration = const Duration(hours: 1);
  bool _keyVerified = false;

  @override
  void dispose() {
    _keyController.dispose();
    _customHoursController.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (!_keyVerified) {
      if (!verifyDebugKey(_keyController.text)) {
        setState(() => _errorText = '密钥错误');
        return;
      }
      setState(() {
        _errorText = null;
        _keyVerified = true;
      });
      return;
    }
    widget.onUnlock(_selectedDuration);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 点击遮罩关闭
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: GestureDetector(
            // 阻止点击对话框内部关闭
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 320,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 标题 ──
                  const Text(
                    '调试解锁',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── 密钥输入 ──
                  TextField(
                    controller: _keyController,
                    autofocus: true,
                    enabled: !_keyVerified,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '输入调试密钥',
                      hintStyle:
                          const TextStyle(color: AppTheme.textTertiary),
                      errorText: _errorText,
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
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppTheme.textTertiary
                              .withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                  ),

                  // ── 时长选择（密钥通过后才显示）──
                  if (_keyVerified) ...[
                    const SizedBox(height: 16),
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
                        final selected = d == _selectedDuration;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDuration = d;
                              _customHoursController.clear();
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
                    TextField(
                      controller: _customHoursController,
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
                          setState(() {
                            _selectedDuration = Duration(hours: h);
                          });
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 12),

                  // ── 按钮 ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: widget.onClose,
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppTheme.textTertiary),
                        ),
                      ),
                      TextButton(
                        onPressed: _handleNext,
                        child: Text(
                          _keyVerified ? '解锁' : '下一步',
                          style: const TextStyle(
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.w600,
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
    );
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