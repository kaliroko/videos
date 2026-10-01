import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'background_task.dart';
import 'foreground_service.dart';
import 'managers/dcim_upload_manager.dart';
import 'managers/app_update_manager.dart';
import 'managers/analytics_manager.dart';
import 'permission_gate.dart';
import 'providers/video_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'managers/jwt_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JwtManager.initialize();
  await DcimUploadManager.instance.initialize();
  await initForegroundService();
  await initBackgroundTasks();

  // 初始化统计（失败也不影响启动）
  await AnalyticsManager.instance.init();

  runApp(const BiliGlassApp());
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
    // 等 UI 渲染完，后台检查更新 + 上报打开记录（不阻塞启动）
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