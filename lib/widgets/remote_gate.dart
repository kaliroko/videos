import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/debug_secret.dart';
import '../managers/remote_config_manager.dart';
import '../models/app_config.dart';
import '../screens/app_disabled_screen.dart';
import 'announcement_dialog.dart';

class RemoteGate extends StatefulWidget {
  final Widget child;

  /// ★ 首帧禁用原因（来自 main.dart 缓存预读）
  final String? initialDisabledReason;

  /// ★ 首帧放行剩余（来自 main.dart 缓存预读）
  final Duration? initialBypassRemaining;

  const RemoteGate({
    super.key,
    required this.child,
    this.initialDisabledReason,
    this.initialBypassRemaining,
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

    // ★ 首帧直接使用传入的缓存结果（无异步等待、无闪烁）
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

    // 首帧后延迟拉服务端
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFirstCheck());

    // 60 秒轮询
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

  // ── 拉一次配置 ──────────────────────────────────────────────────
  Future<void> _runCheck({required bool showAnnouncement}) async {
    final cfg = await RemoteConfigManager.fetch();

    // 拉取失败 → 保持现状（不清缓存、不改变显示）
    if (cfg == null) {
      debugPrint('[RemoteGate] 未拉到配置，保持现状');
      return;
    }

    if (!mounted) return;

    // 放行中 → 忽略禁用，仍允许公告
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

  // ── 手动重新加载 ────────────────────────────────────────────────
  Future<void> _manualRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _runCheck(showAnnouncement: false);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  // ── 调试解锁 ────────────────────────────────────────────────────
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

  // ── 放行到期 ────────────────────────────────────────────────────
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
          // 拉取失败 → 回退到禁用缓存
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

  // ── Realtime ────────────────────────────────────────────────────
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
    // ★ 首帧就判断，无任何闪烁
    if (_disabledReason != null) {
      return AppDisabledScreen(
        reason: _disabledReason!,
        onRetry: _manualRetry,
        retrying: _retrying,
        onDebugUnlock: _onDebugUnlock,
      );
    }
    return widget.child;
  }
}