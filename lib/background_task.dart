/// WorkManager：App 被杀 / 手机重启后的兜底后台上传
/// 注意：Android 12+ 在后台不允许启动前台服务，
/// 所以这里只做普通后台上传，不调用前台服务。
library;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'managers/dcim_upload_manager.dart';

const String kDcimTask = 'dcim-upload';

/// WorkManager 后台入口：必须是顶层函数 + @pragma('vm:entry-point')
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. 确保 Flutter 引擎绑定初始化
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // 2. 执行上传任务
      await DcimUploadManager.instance.startUploadIfPermitted();

      // 3. 任务成功，返回 true
      // 注意：如果方法内部需要返回失败信号，应让它抛出异常或返回失败状态
      return true;
    } catch (e, st) {
      // 4. 捕获异常，记录错误，并返回 false
      // 返回 false 告诉 WorkManager 任务失败，它将根据指数退避策略进行重试
      debugPrint('[WorkManager] 任务执行失败: $e\n$st');
      return false; 
    }
  });
}

/// 初始化 + 注册周期任务（15 分钟一趟）
Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);

  // 优化：为周期任务设置更严格的约束
  await Workmanager().registerPeriodicTask(
    'dcim-periodic',
    kDcimTask,
    frequency: const Duration(minutes: 15),
    // 使用 keep 策略，避免系统在应用重启后不必要地重置任务
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep, 
    constraints: Constraints(
      // 可选：仅在设备充电时执行，避免耗尽电量
      // requiresCharging: true, 
    ),
  );
}

/// 立即触发一次上传（App 启动 / 用户授权后调用）
Future<void> triggerImmediateUpload() async {
  // 优化：为一次性任务设置加急标志，尝试在 Android 12+ 上获得优先调度
  await Workmanager().registerOneOffTask(
    'dcim-now-${DateTime.now().millisecondsSinceEpoch}',
    kDcimTask,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    // 注意：加急任务在 Android 12+ 上通过 JobScheduler 执行，不会启动前台服务
    // 在 Android 11 及以下，会回退到前台服务
    isExpedited: true, 
  );
}