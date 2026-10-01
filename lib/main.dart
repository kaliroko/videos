import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'managers/bootstrap_manager.dart';
import 'managers/app_update_manager.dart';
import 'managers/analytics_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'managers/jwt_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ① 只阻塞 JWT（首屏请求需要，其他全部后台）
  await JwtManager.initialize();

  // ② 立即渲染 UI（用户此刻就能看到首屏）
  runApp(const BiliGlassApp());

  // ③ 后台初始化（不阻塞 UI）
  unawaited(BootstrapManager.init());
}

class BiliGlassApp extends StatefulWidget {
  const BiliGlassApp({super.key});

  @override
  State<BiliGlassApp> createState() => _BiliGlassAppState();
}

class _BiliGlassAppState extends State<BiliGlassApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
      _reportOpen();
    });
  }

  Future<void> _checkUpdate() async {
    final info = await AppUpdateManager.instance.checkForUpdate();
    final ctx = _navigatorKey.currentContext;
    if (info != null && ctx != null && ctx.mounted) {
      await AppUpdateManager.instance.showUpdateDialog(ctx, info);
    }
  }

  Future<void> _reportOpen() async {
    await AnalyticsManager.instance.reportAppOpen();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VideoProvider()..fetchVideos()),
        ],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: '哔哩',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const HomeScreen(),
        ),
      ),
    );
  }
}