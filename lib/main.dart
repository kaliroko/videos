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
  //   首帧要靠它决定显示「正常界面」还是「已停服」界面，所以必须等。
  //   好在只是读一次 SharedPreferences，很快。
  final snapshot = await RemoteConfigManager.preload();
  debugPrint('[Main] ✅ 缓存预读完成: '
      'cachedDisabled=${snapshot.cachedDisabled}, '
      'bypassRemaining=${snapshot.bypassRemaining?.inMinutes}分钟');

  // ═══ 阶段 3：Dart 侧 RASP 检查 ═══
  //   ★ 扔到后台 isolate，不挡启动。
  //   它要起 8 次 getprop 进程、通读 /proc/self/maps、逐个线程读 comm ——
  //   在主线程上跑是实打实白等几百毫秒，而这只是个日志：
  //   真正的闸门是上面那次签名校验，它不通过会直接杀进程。
  unawaited(_logSecurityState());

  // ═══ 阶段 4：Supabase 客户端 ═══
  //   ★ 不再 await。首帧完全用不到它 —— 真正需要的地方
  //   （RemoteConfigManager.fetch / DiaryRepository.resolve）
  //   自己会 await init()，而 init() 是幂等的。
  //   这里只把它提前点着，和首帧渲染并行准备。
  unawaited(AnalyticsManager.instance.init());

  // ═══ 阶段 5：启动 UI ═══
  runApp(BiliGlassApp(initialSnapshot: snapshot));

  // ═══ 阶段 6：启动 BootstrapManager（未改动）═══
  unawaited(BootstrapManager.init());
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
    // 综合校验（安全闸门：不通过直接杀进程）
    final fails = await IntegrityGuard.fullCheck();
    if (fails != null) {
      debugPrint('[SEC] ⚠️ 签名校验失败: $fails');
      _hardExit();
    }
    debugPrint('[SEC] ✅ 签名校验通过');

    // ★ 打印实际哈希只是为了排查（用来回填 EXPECTED_SIGNATURE），不参与判定。
    //   原来 await 它，等于把「读签名」这个平台调用做了两遍 ——
    //   fullCheck() 里面已经读过一次了。改成后台打印。
    unawaited(
      IntegrityGuard.getActualSignatureHash().then(
        (h) => debugPrint('[SEC] 实际签名哈希: $h'),
      ),
    );
  } catch (e) {
    debugPrint('[SEC] ⚠️ 校验异常: $e');
    // 通道异常保守起见也退出（防止被 hook 后让校验跳过）
    _hardExit();
  }
}

/// 硬退出：关闭 Flutter Activity + 杀进程
Never _hardExit() {
  try {
    SystemNavigator.pop();
  } catch (_) {}
  // 杀 Dart VM（进而杀整个 App 进程）
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

  /// 引导页走完（或本来就走过了）→ 启动业务服务。
  ///
  /// ★ 这一段原来在 permission_gate.dart 里。权限页删掉之后挪到这儿，
  ///   触发时机还是「用户完成首次设置之后」，顺序没变：
  ///   上报 → 检查更新 → 等 BootstrapManager 就绪 → 补通知权限 → 起前台服务。
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

  /// 后台服务：前台服务的通知在 Android 13+ 需要 POST_NOTIFICATIONS，
  /// 没这个权限通知不显示、服务也容易被系统回收，所以在这里补一次。
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
          // 深/浅色两套都装上，交给系统决定用哪套
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          builder: (context, child) {
            // ★ 碎碎念的调色板是静态的（原因见 diary_palette.dart），
            //   这里每帧把解析后的亮度同步过去。系统切深浅色时
            //   MaterialApp 会重建，builder 跟着跑，整棵树就用新颜色重建。
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