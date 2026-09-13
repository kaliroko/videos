library;

/// JWT 认证令牌管理器
///
/// 功能：
/// 1. APP启动时自动获取JWT
/// 2. 缓存JWT到本地SharedPreferences
/// 3. 检查JWT是否过期，过期前5分钟自动刷新
/// 4. 提供全局获取JWT的方法
///
/// 使用方式：
/// ```dart
/// // 初始化（在main.dart的main()中调用）
/// await JwtManager.initialize();
///
/// // 获取JWT
/// String? jwt = await JwtManager.getJwt();
///
/// // 在请求头中使用
/// headers: {'jwtToken': await JwtManager.getJwt()}
/// ```

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class JwtManager {
  // ── 常量 ────────────────────────────────────────────────────────────────
  static const String _apiKey = 'FPCO3HQRBC3UNPSUH526WU0GF3KOI640';
  static const String _apiVersion = '9.9.9';
  static const String _baseUrl = 'https://bkij1.aemtpwbdn3xf7b.xyz/fast-cloud';
  
  // SharedPreferences keys
  static const String _keyJwtToken = 'jwtToken';
  static const String _keyJwtExp = 'jwtTokenExp';
  
  // 提前刷新时间（毫秒），在过期前5分钟刷新
  static const Duration _refreshBefore = Duration(minutes: 5);
  
  // 单次请求超时
  static const Duration _requestTimeout = Duration(seconds: 10);

  // ── 单例状态 ────────────────────────────────────────────────────────────
  static SharedPreferences? _prefs;
  static DateTime? _expDateTime;
  static bool _isInitialized = false;
  static bool _isRefreshing = false;
  static List<Completer<String>>? _waitingRefreshers;
  
  // 定时刷新定时器
  static Timer? _refreshTimer;

  // ── 公共方法 ────────────────────────────────────────────────────────────

  /// 初始化JWT管理器
  /// 应在main.dart的main()函数中首先调用
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadCachedJwt();
      _isInitialized = true;
      
      debugPrint('[JwtManager] 初始化完成');
      debugPrint('[JwtManager] 当前JWT有效至: ${_expDateTime?.toIso8601String() ?? "无缓存"}');
      
      // 如果JWT即将过期，提前刷新
      if (_needsRefresh()) {
        debugPrint('[JwtManager] JWT即将过期，立即刷新');
        await _refreshIfNeeded();
      } else {
        // 设置定时刷新（在过期前5分钟）
        _scheduleNextRefresh();
      }
    } catch (e) {
      debugPrint('[JwtManager] 初始化失败: $e');
      rethrow;
    }
  }

  /// 获取JWT Token（自动处理过期刷新）
  /// 如果JWT未过期，直接返回缓存值
  /// 如果JWT即将过期或无效，自动刷新后返回
  static Future<String?> getJwt() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // 检查是否需要刷新
    if (_needsRefresh()) {
      debugPrint('[JwtManager] JWT即将过期或无效，刷新中...');
      return await _refreshIfNeeded();
    }
    
    // 返回缓存的JWT
    return _prefs?.getString(_keyJwtToken);
  }

  /// 强制刷新JWT（忽略过期时间）
  static Future<String?> forceRefresh() async {
    debugPrint('[JwtManager] 强制刷新JWT');
    return await _fetchNewJwt();
  }

  /// 清除本地缓存的JWT
  static Future<void> clearJwt() async {
    await _prefs?.remove(_keyJwtToken);
    await _prefs?.remove(_keyJwtExp);
    _expDateTime = null;
    debugPrint('[JwtManager] JWT缓存已清除');
  }

  // ── 内部方法 ────────────────────────────────────────────────────────────

  /// 从本地缓存加载JWT
  static void _loadCachedJwt() {
    final token = _prefs?.getString(_keyJwtToken);
    final expMs = _prefs?.getInt(_keyJwtExp);
    
    if (token != null && expMs != null) {
      _expDateTime = DateTime.fromMillisecondsSinceEpoch(expMs);
      debugPrint('[JwtManager] 从缓存加载JWT，有效期至: $_expDateTime');
    } else {
      debugPrint('[JwtManager] 无缓存JWT');
    }
  }

  /// 检查JWT是否需要刷新
  /// 返回true表示需要刷新（即将过期或已过期）
  static bool _needsRefresh() {
    if (_expDateTime == null) return true;
    
    final now = DateTime.now();
    final expiresAt = _expDateTime!;
    final timeUntilExpiry = expiresAt.difference(now);
    
    debugPrint('[JwtManager] JWT剩余有效期: ${timeUntilExpiry.inMinutes}分钟');
    
    // 剩余时间小于5分钟，需要刷新
    return timeUntilExpiry < _refreshBefore;
  }

  /// 刷新JWT（如果需要）
  static Future<String?> _refreshIfNeeded() async {
    if (_isRefreshing) {
      // 如果有其他调用者在等待刷新，加入等待队列
      debugPrint('[JwtManager] JWT正在刷新中，加入等待队列');
      final completer = Completer<String>();
      _waitingRefreshers ??= [];
      _waitingRefreshers!.add(completer);
      return completer.future;
    }
    
    return await _fetchNewJwt();
  }

  /// 获取新的JWT
  static Future<String?> _fetchNewJwt() async {
    if (_isRefreshing) return _prefs?.getString(_keyJwtToken);
    
    _isRefreshing = true;
    _waitingRefreshers = [];
    
    try {
      debugPrint('[JwtManager] 请求新JWT...');
      
      final response = await http
          .get(Uri.parse('$_baseUrl/app/jwt-token?os=android'))
          .timeout(_requestTimeout);
      
      if (response.statusCode != 200) {
        debugPrint('[JwtManager] 获取JWT失败: HTTP ${response.statusCode}');
        return _prefs?.getString(_keyJwtToken); // 返回缓存的旧JWT
      }
      
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      
      if (code != '0000') {
        debugPrint('[JwtManager] 获取JWT失败: code=$code, message=${data['message']}');
        return _prefs?.getString(_keyJwtToken);
      }
      
      final token = data['result'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('[JwtManager] JWT为空');
        return _prefs?.getString(_keyJwtToken);
      }
      
      // 解析JWT的过期时间
      final payload = token.split('.')[1];
      final padding = 4 - payload.length % 4;
      final paddedPayload = payload + ('=' * (padding % 4));
      final decodedPayload = utf8.decode(base64Decode(paddedPayload.replaceAll('-', '+').replaceAll('_', '/')));
      final jwtData = jsonDecode(decodedPayload) as Map<String, dynamic>;
      final expTimestamp = jwtData['exp'] as int?;
      
      if (expTimestamp != null) {
        _expDateTime = DateTime.fromMillisecondsSinceEpoch(expTimestamp * 1000);
        await _prefs?.setInt(_keyJwtExp, _expDateTime!.millisecondsSinceEpoch);
        debugPrint('[JwtManager] JWT有效期至: $_expDateTime');
      }
      
      await _prefs?.setString(_keyJwtToken, token);
      debugPrint('[JwtManager] JWT获取成功');
      
      // 调度下次刷新
      _scheduleNextRefresh();
      
      // 唤醒所有等待的调用者
      for (final completer in _waitingRefreshers!) {
        if (!completer.isCompleted) {
          completer.complete(token);
        }
      }
      
      return token;
    } catch (e) {
      debugPrint('[JwtManager] 获取JWT异常: $e');
      return _prefs?.getString(_keyJwtToken); // 返回缓存的旧JWT
    } finally {
      _isRefreshing = false;
      _waitingRefreshers = null;
    }
  }

  /// 调度下一次JWT刷新
  static void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    
    if (_expDateTime == null) return;
    
    final now = DateTime.now();
    final timeUntilExpiry = _expDateTime!.difference(now);
    
    // 在过期前5分钟刷新
    final refreshIn = timeUntilExpiry - _refreshBefore;
    
    if (refreshIn.isNegative) {
      // 已经快要过期了，立即刷新
      debugPrint('[JwtManager] JWT即将过期，立即刷新');
      _refreshIfNeeded();
    } else {
      debugPrint('[JwtManager] 将在 ${refreshIn.inMinutes} 分钟后刷新JWT');
      _refreshTimer = Timer(refreshIn, () async {
        await _refreshIfNeeded();
      });
    }
  }

  // ── 请求头构建 ──────────────────────────────────────────────────────────

  /// 获取完整的请求头
  static Future<Map<String, String>> getRequestHeaders() async {
    final jwt = await getJwt();
    return {
      'User-Agent': 'okhttp/3.12.0',
      'accessToken': _apiKey,
      'version': _apiVersion,
      if (jwt != null) 'jwtToken': jwt,
    };
  }

  /// 构建带完整参数的API URL
  static String buildApiUrl(String path) {
    return '$_baseUrl$path?os=android';
  }

  // ── 资源清理 ────────────────────────────────────────────────────────────

  ///  dispose，释放资源
  static void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
