import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
    await DcimUploadManager.instance.initialize();
    await DcimUploadManager.instance.startUploadIfPermitted();
    // 上传完成后停止前台服务
    await FlutterForegroundTask.stopService();
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
      // HIGHEST 优先级确保通知可见，LOW 会被折叠
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      // 不清除通知，上传结束后保留历史痕迹
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
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      debugPrint('[ForegroundService] 已在运行，跳过');
      return;
    }
    debugPrint('[ForegroundService] 开始启动服务...');
    await FlutterForegroundTask.startService(
      notificationTitle: '正在上传文件',
      notificationText: 'DCIM 照片和视频上传中，请稍候...',
      callback: startCallback,
    );
    debugPrint('[ForegroundService] startService 调用成功');
  } catch (e, st) {
    debugPrint('[ForegroundService] ❌ 启动失败: $e\n$st');
  }
}
