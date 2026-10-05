/// 新 API — https://api.kuleu.com/api/sjxjj
/// - GET 请求，每次返回一条随机视频
/// - ★ URL 用 XOR 0x3C 加密（与 analytics_manager / app_update_manager 一致）
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:suisuinian/models/video_model.dart';

// ══════════════════════════════════════════════════════════════════
// ★ XOR 0x3C 加密的 API URL
//   明文: https://api.kuleu.com/api/sjxjj
//   密钥: 0x3C（与 analytics_manager / app_update_manager 一致）
// ══════════════════════════════════════════════════════════════════
const int _kXorKey = 0x3C;

const List<int> _kApiUrlEnc = [
  // "https://"
  0x54, 0x48, 0x48, 0x4C, 0x4F, 0x06, 0x13, 0x13,
  // "api.kule"
  0x5D, 0x4C, 0x55, 0x12, 0x57, 0x49, 0x50, 0x59,
  // "u.com/ap"
  0x49, 0x12, 0x5F, 0x53, 0x51, 0x13, 0x5D, 0x4C,
  // "i/sjxjj"
  0x55, 0x13, 0x4F, 0x56, 0x44, 0x56, 0x56,
];

String _xorDecode(List<int> bytes) =>
    String.fromCharCodes(bytes.map((b) => b ^ _kXorKey));

String? _apiUrlCache;
String get _apiUrl => _apiUrlCache ??= _xorDecode(_kApiUrlEnc);

// ══════════════════════════════════════════════════════════════════

class SimpleApiRepository {
  SimpleApiRepository._();

  /// 请求冷却：防止接口限流（200 次/分钟）
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 400);

  // ── 单次请求一条视频 ──────────────────────────────────────────────
  static Future<VideoItem?> fetchOne() async {
    // 冷却控制
    final elapsed = DateTime.now().difference(_lastRequest);
    if (elapsed < _minInterval) {
      await Future.delayed(_minInterval - elapsed);
    }
    _lastRequest = DateTime.now();

    try {
      final response = await http
          .get(
            Uri.parse(_apiUrl),   // ★ 解密后的 URL
            headers: {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[SimpleApi] HTTP ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ((body['code'] ?? -1) != 200) {
        debugPrint('[SimpleApi] 业务错误: ${body['msg']}');
        return null;
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final videoUrl = (data['videoUrl'] ?? '').toString();
      if (!videoUrl.contains(RegExp(
          r'\.(mp4|m3u8|flv|ts|mov)', caseSensitive: false))) {
        debugPrint('[SimpleApi] URL 非视频格式: $videoUrl');
        return null;
      }

      final rawName = videoUrl.split('/').last.split('?').first;
      final title = _decodeFileName(rawName);

      debugPrint('[SimpleApi] ✅ $title');

      return VideoItem(
        id:         (data['index'] ?? '').toString(),
        title:      title,
        url:        videoUrl,
        coverUrl:   '',
        author:     '',
        uid:        '',
        created:    '',
        fullCached: false,
        headCached: false,
      );
    } catch (e) {
      debugPrint('[SimpleApi] 异常: $e');
      return null;
    }
  }

  // ── 批量拉取（给 video_provider 用）──────────────────────────────
  /// 串行拉取 count 条视频，每条间隔 400ms 避免限流
  static Future<List<VideoItem>> fetchVideos({int count = 1}) async {
    final list = <VideoItem>[];
    for (int i = 0; i < count; i++) {
      final v = await fetchOne();
      if (v != null) list.add(v);
    }
    return list;
  }

  // ── 解码文件名 ────────────────────────────────────────────────────
  static String _decodeFileName(String raw) {
    try {
      final withoutExt =
          raw.split('.').isEmpty ? raw : raw.substring(0, raw.lastIndexOf('.'));
      return Uri.decodeComponent(withoutExt);
    } catch (_) {
      return '视频';
    }
  }
}