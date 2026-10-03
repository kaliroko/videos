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
///   1. 首帧立刻显示 child（完整正常 App UI），用户无感
///   2. 延迟 1.2 秒后，才拉远程配置
///   3. 只有明确拉到 app_enabled=false 才切禁用页
///   4. 网络失败/超时/表空 → 什么都不做
///   5. Realtime 订阅：运行期间配置变更 → 毫秒级响应
///   6. 60 秒轮询保底
///   7. ★ 手动"重新加载"按钮：立即拉取，且防狂点
class RemoteGate extends StatefulWidget {
  final Widget child;
  const RemoteGate({super.key, required this.child});

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  AppConfig? _disabledConfig;
  Timer? _pollTimer;
  RealtimeChannel? _channel;
  bool _showingAnnouncement = false;
  bool _firstCheckDone = false;

  /// ★ 是否正在手动"重新加载"检查中（防狂点）
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFirstCheck());

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

  void _scheduleFirstCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
    if (cfg == null) return;
    if (!mounted) return;

    if (!cfg.appEnabled) {
      setState(() => _disabledConfig = cfg);
      return;
    }

    if (_disabledConfig != null) {
      setState(() => _disabledConfig = null);
    }

    if (showAnnouncement && !_showingAnnouncement) {
      _maybeShowAnnouncement(cfg);
    }
  }

  // ── ★ 手动"重新加载"（防狂点）───────────────────────────────────
  Future<void> _manualRetry() async {
    if (_retrying) return;              // 已经在检查中，忽略
    setState(() => _retrying = true);
    try {
      await _runCheck(showAnnouncement: false);
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  // ── Realtime 订阅 ───────────────────────────────────────────────
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
              if (!mounted) return;

              if (!cfg.appEnabled) {
                setState(() => _disabledConfig = cfg);
              } else {
                if (_disabledConfig != null) {
                  setState(() => _disabledConfig = null);
                }
              }
            },
          )
          .subscribe((status, [err]) {
            debugPrint('[RemoteGate] Realtime: $status, err=$err');
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
    if (_disabledConfig != null) {
      return AppDisabledScreen(
        reason: _disabledConfig!.disabledReason,
        onRetry: _manualRetry,
        retrying: _retrying,          // ★ 传给按钮
      );
    }
    return widget.child;
  }
}