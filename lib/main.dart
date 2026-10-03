import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/secrets.dart';
import 'managers/bootstrap_manager.dart';
import 'managers/app_update_manager.dart';
import 'managers/analytics_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'providers/nav_bar_visibility.dart';
import 'widgets/remote_gate.dart';                 // ★ 新增这一行
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 让内容延伸到系统栏后面（沉浸式 / Edge-to-Edge）
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  if (!SecurityCheck.isSecure) {
    debugPrint('[Security] ⚠️ 检测到不安全环境，应用继续运行但需警惕');
  }

  runApp(const BiliGlassApp());

  unawaited(BootstrapManager.init());
}

class BiliGlassApp extends StatefulWidget {
  const BiliGlassApp({super.key});

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
          // ★ 唯一的功能改动：用 RemoteGate 包住 HomeScreen
          home: const RemoteGate(child: HomeScreen()),
        ),
      ),
    );
  }
}