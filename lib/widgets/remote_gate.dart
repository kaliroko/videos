import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/debug_secret.dart';
import '../managers/remote_config_manager.dart';
import '../models/app_config.dart';
import '../screens/app_disabled_screen.dart';
import 'announcement_dialog.dart';

class RemoteGate extends StatefulWidget {
  final Widget child;
  final String? initialDisabledReason;
  final Duration? initialBypassRemaining;

  /// ★ 只用于公告弹窗（AppDisabledScreen 用 Stack 版，不需要）
  final GlobalKey<NavigatorState>? navigatorKey;

  const RemoteGate({
    super.key,
    required this.child,
    this.initialDisabledReason,
    this.initialBypassRemaining,
    this.navigatorKey,
  });

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  late String? _disabledReason;
  late bool _debugBypass;
  String? _bypassDisabledFallback;

  Timer? _pollTimer;
  Timer? _bypassExpireTimer;
  RealtimeChannel? _channel;
  bool _showingAnnouncement = false;
  bool _firstCheckDone = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();

    _debugBypass = widget.initialBypassRemaining != null;
    _disabledReason =
        _debugBypass ? null : widget.initialDisabledReason;

    if (_debugBypass) {
      _bypassDisabledFallback = widget.initialDisabledReason;
      _scheduleBypassExpiry(widget.initialBypassRemaining!);
      debugPrint('[RemoteGate] 🔓 首帧：放行中，'
          '剩余 ${widget.initialBypassRemaining!.inMinutes} 分钟');
    } else if (_disabledReason != null) {
      debugPrint('[RemoteGate] 🚫 首帧：禁用页 ($_disabledReason)');
    } else {
      debugPrint('[RemoteGate] ✅ 首帧：正常 UI');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFirstCheck());

    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (_firstCheckDone && !_debugBypass) {
          _runCheck(showAnnouncement: false);
        }
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bypassExpireTimer?.cancel();
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

  Future<void> _runCheck({required bool showAnnouncement}) async {
    final cfg = await RemoteConfigManager.fetch();

    if (cfg == null) {
      debugPrint('[RemoteGate] 未拉到配置，保持现状');
      return;
    }

    if (!mounted) return;

    if (_debugBypass) {
      debugPrint('[RemoteGate] 🔓 放行中，忽略禁用指令');
      if (cfg.appEnabled && showAnnouncement && !_showingAnnouncement) {
        _maybeShowAnnouncement(cfg);
      }
      return;
    }

    if (!cfg.appEnabled) {
      await RemoteConfigManager.saveDisabledState(cfg.disabledReason);
      if (!mounted) return;
      setState(() => _disabledReason = cfg.disabledReason);
      return;
    }

    await RemoteConfigManager.clearDisabledState();
    if (!mounted) return;
    if (_disabledReason != null) {
      setState(() => _disabledReason = null);
    }

    if (showAnnouncement && !_showingAnnouncement) {
      _maybeShowAnnouncement(cfg);
    }
  }

  Future<void> _manualRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _runCheck(showAnnouncement: false);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<bool> _onDebugUnlock(Duration duration) async {
    debugPrint('[RemoteGate] 🔓 调试解锁 ${duration.inHours} 小时');

    await saveBypassUntil(duration);

    final clamped = duration > kMaxBypassDuration
        ? kMaxBypassDuration
        : duration;

    if (!mounted) return true;

    setState(() {
      _debugBypass = true;
      _bypassDisabledFallback = _disabledReason;
      _disabledReason = null;
    });

    _scheduleBypassExpiry(clamped);
    return true;
  }

  void _scheduleBypassExpiry(Duration remaining) {
    _bypassExpireTimer?.cancel();
    _bypassExpireTimer = Timer(remaining, () async {
      if (!mounted) return;
      debugPrint('[RemoteGate] ⏰ 放行到期，恢复服务端控制');

      await clearBypass();
      if (!mounted) return;

      final cfg = await RemoteConfigManager.fetch();
      if (!mounted) return;

      setState(() {
        _debugBypass = false;

        if (cfg != null && !cfg.appEnabled) {
          _disabledReason = cfg.disabledReason;
        } else if (cfg != null && cfg.appEnabled) {
          _disabledReason = null;
        } else {
          _disabledReason = _bypassDisabledFallback;
        }
        _bypassDisabledFallback = null;
      });

      if (cfg != null && !cfg.appEnabled) {
        await RemoteConfigManager.saveDisabledState(cfg.disabledReason);
      } else if (cfg != null && cfg.appEnabled) {
        await RemoteConfigManager.clearDisabledState();
      }
    });
  }

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

              if (_debugBypass) {
                debugPrint('[RemoteGate] 🔓 放行中，忽略推送');
                return;
              }

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

  Future<void> _maybeShowAnnouncement(AppConfig cfg) async {
    final show = await RemoteConfigManager.shouldShowAnnouncement(cfg);
    if (!mounted || !show) return;

    _showingAnnouncement = true;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      _showingAnnouncement = false;
      return;
    }

    // ★ 用 navigatorKey 的 context（本 widget 位于 builder 层，自身 context 拿不到 Navigator）
    final navCtx = widget.navigatorKey?.currentContext;
    if (navCtx == null || !navCtx.mounted) {
      debugPrint('[RemoteGate] navigatorKey 未就绪，跳过公告');
      _showingAnnouncement = false;
      return;
    }

    await showDialog(
      context: navCtx,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(config: cfg),
    );
    await RemoteConfigManager.markAnnouncementShown(cfg);
    _showingAnnouncement = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_disabledReason != null) {
      return AppDisabledScreen(
        reason: _disabledReason!,
        onRetry: _manualRetry,
        retrying: _retrying,
        onDebugUnlock: _onDebugUnlock,
        // ★ 不传 navigatorKey（Stack 版 AppDisabledScreen 不需要）
      );
    }
    return widget.child;
  }
}