/// 权限门禁
/// - 分 SDK 判断：33+ 用媒体权限，32 及以下用存储权限
/// - ★ 不启动 BootstrapManager（已在 main 里启动）
/// - ★ _check() 加防重入锁
/// - ★ didChangeAppLifecycleState 延迟 300ms
/// - UI 风格：MD3 + 毛玻璃 + 「碎碎念」首页预览 + 弹簧入场
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_info_helper.dart';
import 'foreground_sync.dart';
import 'managers/bootstrap_manager.dart';
import 'models/diary_post.dart';
import 'theme/diary_palette.dart';
import 'widgets/diary_card.dart';
import 'widgets/ink_seal.dart';

const Color _kPrimary = Color(0xFFFB7299);
const Color _kPrimaryContainer = Color(0x33FB7299);

class PermissionGate extends StatefulWidget {
  final Widget child;
  final VoidCallback? onGranted;

  const PermissionGate({
    super.key,
    required this.child,
    this.onGranted,
  });

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _granted = false;
  bool _permanentlyDenied = false;
  bool _foregroundStarted = false;

  /// ★ 防重入锁
  bool _checkRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_granted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_granted) _check();
      });
    }
  }

  Future<void> _check() async {
    if (_checkRunning) {
      debugPrint('[PermissionGate] _check 已在运行，跳过');
      return;
    }
    _checkRunning = true;

    try {
      final status = await _readStatus();
      if (!mounted) return;

      setState(() {
        _granted = status.isGranted || status.isLimited;
        _permanentlyDenied = status.isPermanentlyDenied;
        _checking = false;
      });

      if (!_granted) return;

      // ★ 只启动前台服务（BootstrapManager 已在 main 里启动过）
      if (!_foregroundStarted) {
        _foregroundStarted = true;
        widget.onGranted?.call();
        unawaited(_startForegroundInBackground());
      }
    } finally {
      _checkRunning = false;
    }
  }

  Future<void> _startForegroundInBackground() async {
    try {
      // 等 Bootstrap 完成（main 里已启动，这里只是等它 ready）
      await BootstrapManager.ready;
      debugPrint('[PermissionGate] Bootstrap 就绪');

      await _ensureNotificationPermission();

      await startPushForeground();
      debugPrint('[PermissionGate] ✅ 前台服务已启动');
    } catch (e) {
      debugPrint('[PermissionGate] 前台服务启动失败: $e');
    }
  }

  Future<void> _ensureNotificationPermission() async {
    try {
      final sdk = await DeviceInfoHelper.getAndroidSdkInt();
      if (sdk < 33) return;
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        debugPrint('[PermissionGate] 申请通知权限');
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[PermissionGate] 通知权限申请失败: $e');
    }
  }

  Future<PermissionStatus> _readStatus() async {
    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) {
      final photos = await Permission.photos.status;
      if (photos.isGranted || photos.isLimited) return photos;
      final videos = await Permission.videos.status;
      if (videos.isGranted || videos.isLimited) return videos;
      return photos;
    } else {
      return await Permission.storage.status;
    }
  }

  Future<void> _request() async {
    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) {
      await <Permission>[Permission.photos, Permission.videos].request();
    } else {
      await Permission.storage.request();
    }
    await _check();
  }

  Future<void> _openSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.settings);
      return;
    } catch (_) {}
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[PermissionGate] openAppSettings 异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF0A0A0F),
          body: SizedBox.shrink(),
        ),
      );
    }
    if (_granted) return widget.child;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: _buildBackground(),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _LivePreviewBackground(),
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 5,
            sigmaY: 5,
            tileMode: TileMode.clamp,
          ),
          child: Container(
            color: Colors.black.withValues(alpha: 0.32),
          ),
        ),
        Positioned(
          top: -200,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _kPrimary.withValues(alpha: 0.12),
                      _kPrimary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Center(child: _buildDialog(context)),
      ],
    );
  }

  Widget _buildDialog(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.7 + 0.3 * t,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: 380,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kPrimaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.folder_special_rounded,
                            color: _kPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            '需要存储权限',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _permanentlyDenied
                          ? '您已拒绝该权限。请前往系统设置中手动开启，否则无法使用本应用。'
                          : '为了确保软件正常运行，需要授予存储权限。否则无法进入本应用。',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _check,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.8),
                          ),
                          child: Text(_permanentlyDenied ? '我已开启' : '重试'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed:
                              _permanentlyDenied ? _openSettings : _request,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          icon: Icon(
                            _permanentlyDenied
                                ? Icons.settings_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _permanentlyDenied ? '去设置' : '授予权限',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 首页预览 —— 按「碎碎念」日记页的样子铺一层假界面
//
// 用户在被索要权限之前，先透过毛玻璃看到 App 长什么样。
// 内容全是写死的假数据，不发任何网络请求，离线也能正常显示。
// ══════════════════════════════════════════════════════════════
class _LivePreviewBackground extends StatelessWidget {
  const _LivePreviewBackground();

  /// 预览用的假动态 —— 直接复用真实的 DiaryCard，样式永远不会走样
  static final List<DiaryPost> _fakePosts = <DiaryPost>[
    DiaryPost(
      id: 'preview-1',
      deviceId: 'preview',
      authorName: '小满',
      anonymous: false,
      content: '路过花店买了一支桔梗，插在喝完的牛奶瓶里，居然挺好看的。',
      mood: DiaryMood.joy,
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
    DiaryPost(
      id: 'preview-2',
      deviceId: 'preview',
      authorName: '',
      anonymous: true,
      content: '今天什么都没干，但心情还行。',
      mood: DiaryMood.tired,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(topInset),
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                itemCount: _fakePosts.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) => DiaryCard(
                  post: _fakePosts[index],
                  tilt: index == 0 ? -0.006 : 0.006,
                ),
              ),
            ),
            _buildBottomBar(bottomInset),
          ],
        ),
        // 和真实页面一样，右下角浮一个「写」
        Positioned(
          right: 18,
          bottom: 104 + bottomInset,
          child: _buildComposeButton(),
        ),
      ],
    );
  }

  // ── 页头：毛笔大字 + 印章 + 朱砂一笔 + 一句手写 ──────────────────
  Widget _buildHeader(double topInset) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 26, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Text(
                  '碎碎念',
                  style: DiaryPalette.brushHero,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: InkSeal(text: '念', size: 42),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: 68,
            height: 3,
            decoration: BoxDecoration(
              color: DiaryPalette.vermilion,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '今天也没发生什么大事',
            style: DiaryPalette.brushLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(
                child: Divider(
                  color: DiaryPalette.onInkFaint,
                  height: 1,
                  thickness: 1,
                ),
              ),
              SizedBox(width: 12),
              Text('2 条', style: DiaryPalette.roundOnInk),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(double bottomInset) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: const Row(
          children: [
            Expanded(
              child: _FakeTab(
                label: '碎碎念',
                icon: Icons.create,
                selected: true,
              ),
            ),
            Expanded(
              child: _FakeTab(
                label: '聊天室',
                icon: Icons.chat_bubble,
                selected: false,
              ),
            ),
            Expanded(
              child: _FakeTab(
                label: '白丝宝宝',
                icon: Icons.auto_awesome,
                selected: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposeButton() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DiaryPalette.vermilion,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DiaryPalette.vermilion.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Text(
        '写',
        style: TextStyle(
          fontFamily: DiaryPalette.brush,
          fontSize: 27,
          height: 1.0,
          color: DiaryPalette.onVermilion,
        ),
      ),
    );
  }
}

class _FakeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;

  const _FakeTab({
    required this.label,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: selected ? _kPrimary : Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: selected ? _kPrimary : Colors.white.withValues(alpha: 0.35),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
