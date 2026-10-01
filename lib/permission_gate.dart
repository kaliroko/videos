/// 权限门禁
/// - 分 SDK 判断：33+ 用媒体权限，32 及以下用存储权限
/// - 授权成功后：先确保通知权限，再启动前台服务立即上传
/// - UI 风格：MD3 + 毛玻璃 + 单色淡光晕背景 + 弹簧入场
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_info_helper.dart';
import 'foreground_service.dart';

// ══════════════════════════════════════════════════════════════
// 主题色
// ══════════════════════════════════════════════════════════════
const Color _kPrimary = Color(0xFFFB7299);           // B站粉
const Color _kPrimaryContainer = Color(0x33FB7299);  // 粉 20% 透明度

class PermissionGate extends StatefulWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _granted = false;
  bool _permanentlyDenied = false;
  bool _foregroundStarted = false;

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
      _check();
    }
  }

  Future<void> _check() async {
    final status = await _readStatus();
    if (!mounted) return;
    setState(() {
      _granted = status.isGranted || status.isLimited;
      _permanentlyDenied = status.isPermanentlyDenied;
      _checking = false;
    });

    if (_granted && !_foregroundStarted) {
      _foregroundStarted = true;
      debugPrint('[PermissionGate] 权限已授予，确保通知权限并启动前台上传');
      await _ensureNotificationPermission();
      unawaited(startUploadForeground());
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

  /// 打开应用详情设置页
  /// - 优先用 app_settings（直接跳应用详情）
  /// - 失败时回退到 permission_handler
  Future<void> _openSettings() async {
    debugPrint('[PermissionGate] 跳转到应用详情设置...');

    // 方案 1：app_settings（明确跳转到 App Info 页面）
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.settings);
      debugPrint('[PermissionGate] ✅ AppSettings 成功');
      return;
    } catch (e) {
      debugPrint('[PermissionGate] AppSettings 失败: $e，尝试 fallback');
    }

    // 方案 2：permission_handler
    try {
      final ok = await openAppSettings();
      debugPrint('[PermissionGate] openAppSettings 返回 $ok');
    } catch (e) {
      debugPrint('[PermissionGate] openAppSettings 异常: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // build
  // ══════════════════════════════════════════════════════════
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

  // ══════════════════════════════════════════════════════════
  // 简约背景：深色渐变 + 单一柔和淡光晕
  // ══════════════════════════════════════════════════════════
  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0E0E14),
            Color(0xFF08080C),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 单一光晕：顶部中央，极低透明度
          Positioned(
            top: -200,
            left: 0,
            right: 0,
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

          // 弹窗
          Center(child: _buildDialog(context)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 弹窗本体：MD3 + 毛玻璃 + 弹簧入场
  // ══════════════════════════════════════════════════════════
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
                    // ── 图标 + 标题 ────────────────────
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

                    // ── 说明文字 ───────────────────────
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

                    // ── 按钮 ───────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 次按钮
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

                        // 主按钮
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