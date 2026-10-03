import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/debug_secret.dart';                    // ★
import '../managers/remote_config_manager.dart';
import '../models/app_config.dart';
import '../screens/app_disabled_screen.dart';
import 'announcement_dialog.dart';

/// 全局远程配置网关（非阻塞 + 粘性禁用 + 调试解锁 + 时限放行）
class RemoteGate extends StatefulWidget {
  final Widget child;
  const RemoteGate({super.key, required this.child});

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  AppConfig? _disabledConfig;
  Timer? _pollTimer;
  Timer? _bypassExpireTimer;
  RealtimeChannel? _channel;
  bool _showingAnnouncement = false;
  bool _firstCheckDone = false;
  bool _retrying = false;

  /// ★ 调试放行：本次会话 + 缓存期间绕过远程禁用
  bool _debugBypass = false;

  /// ★ 放行缓存是否已加载（未加载前不显示禁用页，避免闪屏）
  bool _bypassLoaded = false;

  /// 是否需要在首屏时弹公告（bypass 加载完后处理）
  bool _pendingAnnouncementCheck = false;

  @override
  void initState() {
    super.initState();

    // ★ 先加载放行缓存，再决定是否检查服务端
    _loadBypassThenStart();

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

  /// 加载放行缓存 → 决定是否 bypass
  Future<void> _loadBypassThenStart() async {
    final remaining = await getActiveBypassRemaining();
    if (!mounted) return;

    setState(() {
      _bypassLoaded = true;
      if (remaining != null) {
        _debugBypass = true;
        _scheduleBypassExpiry(remaining);
      }
    });

    debugPrint('[RemoteGate] bypass 缓存: '
        '${remaining == null ? "无" : "${remaining.inMinutes} 分钟"}');

    // 缓存加载完，再延迟 1.2 秒拉服务端
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFirstCheck());
  }

  void _scheduleFirstCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;

      if (_debugBypass) {
        // 放行中，不做服务端检查；但仍要允许公告
        _firstCheckDone = true;
        _pendingAnnouncementCheck = true;
        _subscribeRealtime();
        return;
      }

      await _runCheck(showAnnouncement: true);
      _firstCheckDone = true;

      if (!mounted) return;
      _subscribeRealtime();
    });
  }

  /// 定时清除过期放行
  void _scheduleBypassExpiry(Duration remaining) {
    _bypassExpireTimer?.cancel();
    _bypassExpireTimer = Timer(remaining, () async {
      if (!mounted) return;
      debugPrint('[RemoteGate]  放行到期，恢复服务端控制');
      await clearBypass();
      setState(() => _debugBypass = false);
      // 立即检查服务端
      await _runCheck(showAnnouncement: false);
    });
  }

  Future<void> _runCheck({required bool showAnnouncement}) async {
    final cfg = await RemoteConfigManager.fetch();
    if (cfg == null) return;
    if (!mounted) return;

    // ★ 放行中 → 忽略禁用
    if (_debugBypass) {
      debugPrint('[RemoteGate]  放行中，忽略禁用指令');
      return;
    }

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

  Future<void> _manualRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _runCheck(showAnnouncement: false);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// ★ 调试解锁（带时长）
  Future<bool> _onDebugUnlock(Duration duration) async {
    debugPrint('[RemoteGate]  调试密钥验证通过，'
        '放行 ${duration.inHours} 小时');

    // 写入缓存
    await saveBypassUntil(duration);

    // 立即生效
    setState(() {
      _debugBypass = true;
      _disabledConfig = null;
    });

    // 设置到期定时器
    final clamped = duration > kMaxBypassDuration
        ? kMaxBypassDuration
        : duration;
    _scheduleBypassExpiry(clamped);

    return true;
  }

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

              // ★ 放行中 → 忽略
              if (_debugBypass) {
                debugPrint('[RemoteGate]  放行中，忽略推送');
                return;
              }

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
    // ★ 放行缓存未加载完 → 显示 child（避免闪禁用页）
    if (!_bypassLoaded) {
      return widget.child;
    }

    if (_disabledConfig != null) {
      return AppDisabledScreen(
        reason: _disabledConfig!.disabledReason,
        onRetry: _manualRetry,
        retrying: _retrying,
        onDebugUnlock: _onDebugUnlock,
      );
    }
    return widget.child;
  }
}