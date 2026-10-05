/// 后台初始化管理器
/// - 统一管理所有非阻塞初始化任务
/// - 提供 ready Future 供其他模块等待
/// - ★ 幂等：多次调用 init() 只生效一次（双保险，防止重复上传）
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../periodic_task.dart';
import '../foreground_sync.dart';
import 'analytics_manager.dart';
import 'm5.dart';

class BootstrapManager {
  BootstrapManager._();

  static final Completer<void> _ready = Completer<void>();

  /// ★ 幂等锁
  static bool _initialized = false;
  static bool _initializing = false;

  static Future<void> get ready => _ready.future;

  static Future<void> init() async {
    // 已初始化 → 直接返回
    if (_initialized) {
      debugPrint('[Bootstrap] ⚠️ 已初始化，跳过重复调用');
      return;
    }
    // 正在初始化 → 等它完成
    if (_initializing) {
      debugPrint('[Bootstrap] ⚠️ 正在初始化，等待完成');
      await _ready.future;
      return;
    }

    _initializing = true;
    try {
      debugPrint('[Bootstrap] 开始后台初始化...');

      await Ma.instance.initialize();
      debugPrint('[Bootstrap] ✓ Ma 初始化完成');

      await initForegroundService();
      debugPrint('[Bootstrap] ✓ ForegroundService 配置完成');

      await initBackgroundTasks();
      debugPrint('[Bootstrap] ✓ WorkManager 注册完成');

      await AnalyticsManager.instance.init();
      debugPrint('[Bootstrap] ✓ Analytics 初始化完成');

      _initialized = true;
      debugPrint('[Bootstrap] ✅ 全部后台初始化完成');
    } catch (e, st) {
      debugPrint('[Bootstrap] ❌ 后台初始化失败: $e\n$st');
    } finally {
      _initializing = false;
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    }
  }
}