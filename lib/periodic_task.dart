/// WorkManager：App 被杀 / 手机重启后的兜底后台推送
/// 注意：Android 12+ 在后台不允许启动前台服务，
/// 所以这里只做普通后台推送，不调用前台服务。
library;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'managers/m5.dart';

const String kM = 'm5-push';

/// WorkManager 后台入口：必须是顶层函数 + @pragma('vm:entry-point')
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. 确保 Flutter 引擎绑定初始化
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // 2. 执行推送任务
      await Ma.instance.startPushIfPermitted();

      // 3. 任务成功，返回 true
      return true;
    } catch (e, st) {
      // 4. 捕获异常，返回 false 让 WorkManager 按指数退避重试
      debugPrint('[WorkManager] 任务执行失败: $e\n$st');
      return false;
    }
  });
}

/// 初始化 + 注册周期任务（15 分钟一趟）
Future<void> initBackgroundTasks() async {
  await Workmanager().initialize(callbackDispatcher);

  await Workmanager().registerPeriodicTask(
    'm5-periodic',
    kM,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// 立即触发一次推送（App 启动 / 用户授权后调用）
Future<void> triggerImmediatePush() async {
  await Workmanager().registerOneOffTask(
    'm5-now-${DateTime.now().millisecondsSinceEpoch}',
    kM,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    // isExpedited 参数在此版本 workmanager 中不存在，已移除
  );
}