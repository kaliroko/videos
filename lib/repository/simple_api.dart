/// 新 API — https://api.kuleu.com/api/sjxjj
/// - GET 请求，每次返回一条随机视频
/// - ★ URL 用 HardwareKey 派生密钥 XOR 解密（每台设备不同）
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:bilibili_glass/config/hardware_key.dart';
import 'package:bilibili_glass/models/video_model.dart';

// ══════════════════════════════════════════════════════════════════
// ★ API URL 密文（明文: https://api.kuleu.com/api/sjxjj）
//   使用 HardwareKey.deriveApiKey() 派生密钥 XOR 解密
// ══════════════════════════════════════════════════════════════════
const List<int> _kApiUrlEnc = <int>[
  // "https://"
  0xCF, 0xD3, 0xD3, 0xD7, 0xD4, 0x9D, 0x88, 0x88,
  // "api.kule"
  0xC6, 0xD7, 0xCE, 0x89, 0xCC, 0xD2, 0xCB, 0xC2,
  // "u.com/ap"
  0xD2, 0x89, 0xC4, 0xC8, 0xCA, 0x88, 0xC6, 0xD7,
  // "i/sjxjj"
  0xCE, 0x88, 0xD4, 0xCD, 0xDF, 0xCD, 0xCD,
];

String? _apiUrlCache;
Future<String> get _apiUrl async {
  if (_apiUrlCache == null) {
    final key = await HardwareKey.deriveApiKey();
    _apiUrlCache = String.fromCharCodes(
      _kApiUrlEnc.map((b) => b ^ key[b % key.length]),
    );
  }
  return _apiUrlCache!;
}

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
      final apiUrl = await _apiUrl;
      final response = await http
          .get(
            Uri.parse(apiUrl),
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
        id: (data['index'] ?? '').toString(),
        title: title,
        url: videoUrl,
        coverUrl: '',
        author: '',
        uid: '',
        created: '',
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
