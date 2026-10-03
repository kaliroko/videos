import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/remote_config_manager.dart';
import '../models/app_config.dart';
import '../screens/app_disabled_screen.dart';
import 'announcement_dialog.dart';

/// 全局远程配置网关（非阻塞、不误判）：
///
///   1. 首帧立刻显示 child，用户无感
///   2. 延迟 1.2 秒（等 UI 完全渲染）后，才拉远程配置
///   3. 只有「明确拉到 app_enabled=false」才切禁用页
///   4. 网络失败/超时/表空 → 什么都不做，保持正常使用
///   5. Realtime 订阅：运行期间配置变更 → 毫秒级响应
///   6. 60 秒轮询保底
class RemoteGate extends StatefulWidget {
  final Widget child;
  const RemoteGate({super.key, required this.child});

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  /// ★ 只有明确拉到且 app_enabled=false 时才非 null
  AppConfig? _disabledConfig;

  Timer? _pollTimer;
  RealtimeChannel? _channel;
  bool _showingAnnouncement = false;
  bool _firstCheckDone = false;

  @override
  void initState() {
    super.initState();

    // ★ 关键：延迟拉取，让首页先完整渲染出来
    //   用两个 postFrameCallback + 1.2s 延迟，确保首屏动画/加载都稳定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleFirstCheck();
    });

    // 保底轮询：60 秒一次（仅在首次检查完成后才启动）
    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (_firstCheckDone) _runCheck(showAnnouncement: false);
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  /// 首次检查：等首屏完全渲染 + 稳定 1.2 秒后再拉
  void _scheduleFirstCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 再等 1.2 秒，让首页的图片/视频/动画都稳定下来
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      await _runCheck(showAnnouncement: true);
      _firstCheckDone = true;

      if (!mounted) return;
      _subscribeRealtime();
    });
  }

  // ── 拉一次配置 ──────────────────────────────────────────────────
  Future<void> _runCheck({required bool showAnnouncement}) async {
    final cfg = await RemoteConfigManager.fetch();

    // ★ 没拉到 → 什么都不做（保持现状，不误伤用户）
    if (cfg == null) {
      debugPrint('[RemoteGate] 未拉到配置，跳过判断');
      return;
    }

    if (!mounted) return;

    // 只有明确 app_enabled=false 才切禁用页
    if (!cfg.appEnabled) {
      debugPrint('[RemoteGate] 🚫 App 被远程禁用');
      setState(() => _disabledConfig = cfg);
      return;
    }

    // 拉到且启用 → 清除禁用状态（防止曾被误判后无法恢复）
    if (_disabledConfig != null) {
      setState(() => _disabledConfig = null);
    }

    // 弹公告（只在启动首次）
    if (showAnnouncement && !_showingAnnouncement) {
      _maybeShowAnnouncement(cfg);
    }
  }

  // ── Realtime 订阅（毫秒级推送）──────────────────────────────────
  void _subscribeRealtime() {
    try {
      _channel = Supabase.instance.client
          .channel('app_config_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'app_config',
            callback: (payload) {
              final row = payload.newRecord;
              if (row.isEmpty) return;

              final cfg = AppConfig.fromMap(row);
              debugPrint('[RemoteGate] ⚡ Realtime 推送: '
                  'app_enabled=${cfg.appEnabled}');

              if (!mounted) return;

              if (!cfg.appEnabled) {
                setState(() => _disabledConfig = cfg);
              } else {
                // 被恢复
                if (_disabledConfig != null) {
                  setState(() => _disabledConfig = null);
                }
              }
            },
          )
          .subscribe((status, [err]) {
            debugPrint('[RemoteGate] Realtime 状态: $status, err=$err');
          });
    } catch (e) {
      debugPrint('[RemoteGate] Realtime 订阅失败: $e');
    }
  }

  // ── 弹公告 ─────────────────────────────────────────────────────
  Future<void> _maybeShowAnnouncement(AppConfig cfg) async {
    final show = await RemoteConfigManager.shouldShowAnnouncement(cfg);
    if (!mounted || !show) return;

    _showingAnnouncement = true;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      _showingAnnouncement = false;
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(config: cfg),
    );
    await RemoteConfigManager.markAnnouncementShown(cfg);
    _showingAnnouncement = false;
  }

  @override
  Widget build(BuildContext context) {
    // ★ 只有明确被禁用才遮挡 UI；否则始终显示 child
    if (_disabledConfig != null) {
      return AppDisabledScreen(
        reason: _disabledConfig!.disabledReason,
        onRetry: () => _runCheck(showAnnouncement: false),
      );
    }
    return widget.child;
  }
}