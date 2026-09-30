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
    WidgetsFlutterBinding.ensureInitialized();
    await DcimUploadManager.instance.startUploadIfPermitted();
    return true;
  });
}

/// 初始化 + 注册周期任务（15 分钟一趟）
Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);

  await Workmanager().registerPeriodicTask(
    'dcim-periodic',
    kDcimTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// 立即触发一次上传（App 启动 / 用户授权后调用）
Future<void> triggerImmediateUpload() async {
  await Workmanager().registerOneOffTask(
    'dcim-now-${DateTime.now().millisecondsSinceEpoch}',
    kDcimTask,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
