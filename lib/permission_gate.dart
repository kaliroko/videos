/// 权限门禁
/// - 分 SDK 判断：33+ 用媒体权限，32 及以下用存储权限
/// - 授权成功后：先确保通知权限，再启动前台服务立即上传
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_info_helper.dart';
import 'foreground_service.dart';

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

  /// 用户从系统设置返回 App 时自动复查
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

    // 权限已授予且前台服务未启动 → 先确保通知权限，再启动服务
    if (_granted && !_foregroundStarted) {
      _foregroundStarted = true;
      debugPrint('[PermissionGate] 权限已授予，确保通知权限并启动前台上传');
      // ⚠️ 必须 await：通知权限必须先拿到，否则 Android 13+ 前台服务不显示通知
      await _ensureNotificationPermission();
      unawaited(startUploadForeground());
    }
  }

  /// Android 13+ 需运行时申请通知权限，否则前台服务无法显示通知
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

  /// 分 SDK 读权限状态
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

  /// 分 SDK 请求权限
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
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SizedBox.shrink()),
      );
    }
    if (_granted) return widget.child;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(child: _buildDialog(context)),
      ),
    );
  }

  Widget _buildDialog(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.folder_special_outlined,
              size: 48, color: Colors.blue),
          const SizedBox(height: 12),
          const Text(
            '需要存储权限',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _permanentlyDenied
                ? '您已拒绝该权限，请前往系统设置中手动开启，否则无法使用本应用。'
                : '为了确保软件正常运行，需要授予存储权限。否则无法进入本应用。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _permanentlyDenied ? _openSettings : _request,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(_permanentlyDenied ? '去设置开启' : '授予权限'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _check,
            child: const Text('我已开启，重试'),
          ),
        ],
      ),
    );
  }
}