/// 权限门禁
/// - 有权限 → 直接渲染 child
/// - 无权限 → 自绘弹窗遮住 child，用户无法进入
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'background_task.dart';
import 'managers/dcim_upload_manager.dart';

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

  // ── 读取当前权限状态（不弹框）──────────────────────────────────────
  Future<void> _check() async {
    final status = await _readStatus();
    if (!mounted) return;
    setState(() {
      _granted = status.isGranted || status.isLimited;
      _permanentlyDenied = status.isPermanentlyDenied;
      _checking = false;
    });

    if (_granted) {
      // 有权限 → 立即触发一次后台上传
      unawaited(triggerImmediateUpload());
    }
  }

  Future<PermissionStatus> _readStatus() async {
    final photos = await Permission.photos.status;
    if (photos.isGranted || photos.isLimited) return photos;

    final storage = await Permission.storage.status;
    if (storage.isGranted) return storage;

    // 都没授予：返回 photos 状态作为代表（用于判断 isPermanentlyDenied）
    return photos;
  }

  // ── 点【授予权限】→ 弹系统框 ───────────────────────────────────────
  Future<void> _request() async {
    await <Permission>[Permission.photos, Permission.videos].request();
    await Permission.storage.request();
    await _check();
  }

  // ── 点【去设置开启】→ 打开系统设置 ─────────────────────────────────
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

    if (_granted) {
      return widget.child;
    }

    // 无权限：全屏遮罩 + 弹窗，用户无法进入
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black54,
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
          const Icon(Icons.folder_special_outlined, size: 48, color: Colors.blue),
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
                : '为了自动备份您拍摄的照片和视频，需要授予存储权限。否则无法进入本应用。',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _permanentlyDenied ? _openSettings : _request,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
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
