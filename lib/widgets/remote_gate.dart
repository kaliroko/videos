import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/remote_config_manager.dart';
import '../models/app_config.dart';
import '../screens/app_disabled_screen.dart';
import 'announcement_dialog.dart';

/// 全局远程配置网关（非阻塞 + 粘性禁用）：
///
///   1. 启动时先读本地缓存
///      - 缓存禁用 → 立即显示禁用页（不等远程）
///      - 缓存正常 → 立即显示 child（正常 App）
///   2. 延迟 1.2 秒后拉远程配置
///      - 拉到 app_enabled=false → 禁用页 + 写入缓存
///      - 拉到 app_enabled=true  → 清除缓存 + 正常 UI
///      - 拉取失败（null）       → 保持现状（不误放行）
///   3. Realtime 订阅 + 60 秒轮询
class RemoteGate extends StatefulWidget {
  final Widget child;
  const RemoteGate({super.key, required this.child});

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  /// 当前禁用原因（非 null 表示被禁用）
  String? _disabledReason;

  /// 首次缓存是否已读完
  bool _cacheLoaded = false;

  Timer? _pollTimer;
  RealtimeChannel? _channel;
  bool _showingAnnouncement = false;
  bool _firstCheckDone = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();

    // ★ 第一步：读本地缓存（同步很快，几乎无感）
    _loadCacheThenStart();

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

  /// 读缓存 → 决定首屏展示 → 1.2s 后拉远程
  Future<void> _loadCacheThenStart() async {
    final cachedDisabled = await RemoteConfigManager.isCachedDisabled();
    final cachedReason = await RemoteConfigManager.cachedDisabledReason();

    if (!mounted) return;
    setState(() {
      _cacheLoaded = true;
      if (cachedDisabled) {
        _disabledReason = cachedReason;
      }
    });

    debugPrint('[RemoteGate] 缓存状态: disabled=$cachedDisabled, '
        'reason=$cachedReason');

    // ★ 无论缓存是什么状态，都要在 UI 稳定后拉一次远程做最终确认
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleFirstCheck();
    });
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

    // ★ 拉取失败 → 保持现状（不误放行，也不误禁）
    if (cfg == null) {
      debugPrint('[RemoteGate] 未拉到配置，保持现状');
      return;
    }

    if (!mounted) return;

    if (!cfg.appEnabled) {
      // 禁用 → 写缓存 + 显示禁用页
      await RemoteConfigManager.saveDisabledState(cfg.disabledReason);
      if (!mounted) return;
      setState(() => _disabledReason = cfg.disabledReason);
      return;
    }

    // 启用 → 清缓存 + 恢复正常
    await RemoteConfigManager.clearDisabledState();
    if (!mounted) return;
    if (_disabledReason != null) {
      setState(() => _disabledReason = null);
    }

    // 弹公告
    if (showAnnouncement && !_showingAnnouncement) {
      _maybeShowAnnouncement(cfg);
    }
  }

  // ── 手动"重新加载" ─────────────────────────────────────────────
  Future<void> _manualRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _runCheck(showAnnouncement: false);
    } finally {
      if (mounted) setState(() => _retrying = false);
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
            callback: (payload) async {
              final row = payload.newRecord;
              if (row.isEmpty) return;
              final cfg = AppConfig.fromMap(row);
              if (!mounted) return;

              if (!cfg.appEnabled) {
                await RemoteConfigManager.saveDisabledState(cfg.disabledReason);
                if (!mounted) return;
                setState(() => _disabledReason = cfg.disabledReason);
              } else {
                await RemoteConfigManager.clearDisabledState();
                if (!mounted) return;
                if (_disabledReason != null) {
                  setState(() => _disabledReason = null);
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
    // 缓存还没读完 → 显示空黑屏（<50ms，肉眼无感）
    if (!_cacheLoaded) {
      return const SizedBox.shrink();
    }

    if (_disabledReason != null) {
      return AppDisabledScreen(
        reason: _disabledReason!,
        onRetry: _manualRetry,
        retrying: _retrying,
      );
    }
    return widget.child;
  }
}