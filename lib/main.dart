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

  // ══════════════════════════════════════════════════════════
  // 阶段 1：系统级 UI 配置
  // ══════════════════════════════════════════════════════════
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // ══════════════════════════════════════════════════════════
  // 阶段 2：本地缓存预读（SharedPreferences）
  //   保证首帧就能决定"显示正常 UI"还是"显示禁用页"
  // ══════════════════════════════════════════════════════════
  final snapshot = await RemoteConfigManager.preload();
  debugPrint('[Main] ✅ 缓存预读完成: '
      'cachedDisabled=${snapshot.cachedDisabled}, '
      'bypassRemaining=${snapshot.bypassRemaining?.inMinutes}分钟');

  // ══════════════════════════════════════════════════════════
  // 阶段 3：Supabase 客户端初始化
  //   保证后续 RemoteGate 拉服务端时客户端已就绪
  //   （AnalyticsManager.init 是幂等的，多次调用只生效一次）
  // ══════════════════════════════════════════════════════════
  await AnalyticsManager.instance.init();
  debugPrint('[Main] ✅ Supabase 客户端就绪');

  // ══════════════════════════════════════════════════════════
  // 阶段 4：安全检查（非阻塞）
  // ══════════════════════════════════════════════════════════
  if (!SecurityCheck.isSecure) {
    debugPrint('[Security] ⚠️ 检测到不安全环境，应用继续运行但需警惕');
  }

  // ══════════════════════════════════════════════════════════
  // 阶段 5：启动 UI
  //   此时本地一切就绪，首帧 + 服务端请求都是最优路径
  // ══════════════════════════════════════════════════════════
  runApp(BiliGlassApp(initialSnapshot: snapshot));

  // ══════════════════════════════════════════════════════════
  // 阶段 6：其他后台初始化（不阻塞 UI）
  // ══════════════════════════════════════════════════════════
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
  bool _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportOpen();
    });
  }

  void _onPermissionGranted() {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
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