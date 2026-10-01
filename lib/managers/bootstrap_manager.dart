/// 后台初始化管理器
/// - 统一管理所有非阻塞初始化任务
/// - 提供 ready Future 供其他模块等待
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../background_task.dart';
import '../foreground_service.dart';
import 'analytics_manager.dart';
import 'dcim_upload_manager.dart';

class BootstrapManager {
  BootstrapManager._();

  static final Completer<void> _ready = Completer<void>();

  /// 所有后台初始化完成的 Future
  /// 任何模块都可以 await 它，确保依赖的服务已就绪
  static Future<void> get ready => _ready.future;

  /// 启动后台初始化（在 main 里 unawaited 调用）
  static Future<void> init() async {
    try {
      debugPrint('[Bootstrap] 开始后台初始化...');

      // 1. DCIM 上传管理器（加载已上传记录）
      await DcimUploadManager.instance.initialize();
      debugPrint('[Bootstrap] ✓ DcimUploadManager 初始化完成');

      // 2. 前台服务配置
      await initForegroundService();
      debugPrint('[Bootstrap] ✓ ForegroundService 配置完成');

      // 3. WorkManager 周期任务注册
      await initBackgroundTasks();
      debugPrint('[Bootstrap] ✓ WorkManager 注册完成');

      // 4. 统计模块
      await AnalyticsManager.instance.init();
      debugPrint('[Bootstrap] ✓ Analytics 初始化完成');

      debugPrint('[Bootstrap] ✅ 全部后台初始化完成');
    } catch (e, st) {
      debugPrint('[Bootstrap] ❌ 后台初始化失败: $e\n$st');
    } finally {
      // 无论成功失败，都打开门闩（避免 PermissionGate 永久等待）
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    }
  }
}