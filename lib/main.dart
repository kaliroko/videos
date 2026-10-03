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

  // ═══ 阶段 5：启动 UI（权限页立刻显示）═══
  runApp(BiliGlassApp(initialSnapshot: snapshot));

  // ★ BootstrapManager 已挪到授权后（PermissionGate._check）
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

  /// ★ 授权后启动业务服务（BootstrapManager 已由 PermissionGate 启动）
  Future<void> _onPermissionGranted() async {
    if (_onGrantedStarted) return;
    _onGrantedStarted = true;

    debugPrint('[Main] 权限已授予 → 启动业务服务');

    // ① 上报打开记录
    unawaited(_reportOpen());

    // ② 延迟 500ms 后检查更新
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _checkUpdate();
    });
  }

  Future<void> _checkUpdate() async {
    debugPrint('[AppUpdate] 开始检查更新...');
    final info = await AppUpdateManager.instance.checkForUpdate();
    if (info == null) {
      debugPrint('[AppUpdate] 无更新，跳过');
      return;
    }
    debugPrint('[AppUpdate] 有更新 v${info.version}，准备弹窗...');
    for (int i = 0; i < 10; i++) {
      if (!mounted) return;
      final ctx = _navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        debugPrint('[AppUpdate] Navigator 就绪，弹窗');
        await AppUpdateManager.instance.showUpdateDialog(ctx, info);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[AppUpdate] Navigator 一直未就绪，放弃弹窗');
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