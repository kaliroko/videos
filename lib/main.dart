import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/secrets.dart';
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

  // 安全环境检测（Root/模拟器/Debuggable）
  if (!SecurityCheck.isSecure) {
    debugPrint('[Security] ⚠️ 检测到不安全环境，应用继续运行但需警惕');
    // 注：此处选择日志记录而非直接退出，避免暴露防护策略给攻击者
    // 可根据需要改为：debugPrint('[Security] 环境异常，终止启动'); exit(1);
  }

  await JwtManager.initialize();

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

  /// ★ 权限弹窗完全关闭后触发
  void _onPermissionGranted() {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;

    // 等权限弹窗的系统 UI 完全退出 + 主界面渲染完成
    // （500ms 足够，Android 权限弹窗关闭动画一般 200-300ms）
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _checkUpdate();
    });
  }

  /// 检查更新（带 Navigator 就绪重试）
  Future<void> _checkUpdate() async {
    debugPrint('[AppUpdate] 开始检查更新...');

    // ① 检查 GitHub
    final info = await AppUpdateManager.instance.checkForUpdate();
    if (info == null) {
      debugPrint('[AppUpdate] 无更新，跳过');
      return;
    }

    debugPrint('[AppUpdate] 有更新 v${info.version}，准备弹窗...');

    // ② 等 Navigator 就绪（最多 5 秒）
    for (int i = 0; i < 10; i++) {
      if (!mounted) {
        debugPrint('[AppUpdate] Widget 已销毁，放弃');
        return;
      }

      final ctx = _navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        debugPrint('[AppUpdate] Navigator 就绪，弹窗');
        await AppUpdateManager.instance.showUpdateDialog(ctx, info);
        return;
      }

      debugPrint('[AppUpdate] Navigator 未就绪，等待中 (${i + 1}/10)');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('[AppUpdate] ❌ Navigator 一直未就绪，放弃弹窗');
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