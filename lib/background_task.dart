/// WorkManager 后台任务
/// - 注册周期任务（15 分钟一趟）
/// - App 关闭后仍能继续静默上传
library;

import 'package:flutter/foundation.dart' show DartPluginRegistrant;
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'managers/dcim_upload_manager.dart';

const String kDcimTask = 'dcim-upload';

/// WorkManager 后台入口：必须是顶层函数 + @pragma('vm:entry-point')
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    // 后台不能弹权限框；只查现状，有权限就传
    await DcimUploadManager.instance.startUploadIfPermitted();
    return true;
  });
}

/// 初始化 + 注册周期任务
Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);

  await Workmanager().registerPeriodicTask(
    'dcim-periodic',
    kDcimTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingWorkPolicy.keep,
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
