/// 新 API — https://api.kuleu.com/api/sjxjj
/// 简单 GET 请求，无加密，每次返回一条随机视频
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bilibili_glass/models/video_model.dart';

const _newApiUrl = 'https://api.kuleu.com/api/sjxjj';
const _pageSize  = 30;   // 同时并发请求的视频数

class SimpleApiRepository {
  /// 并发抓取指定数量的视频
  static Future<List<VideoItem>> fetchVideos() async {
    final futures = List.generate(_pageSize, (_) => _fetchOne());
    final results = await Future.wait(futures);
    return results.whereType<VideoItem>().toList();
  }

  static Future<VideoItem?> _fetchOne() async {
    try {
      final response = await http
          .get(Uri.parse(_newApiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ((body['code'] ?? -1) != 200) return null;

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final videoUrl = (data['videoUrl'] ?? '').toString();
      if (!videoUrl.contains(RegExp(r'\.(mp4|m3u8|flv|ts|mov)', caseSensitive: false))) {
        return null;
      }

      // 尝试从 URL 提取文件名作为标题
      final rawName = videoUrl.split('/').last.split('?').first;
      final title = _decodeFileName(rawName);

      return VideoItem(
        id:         (data['index'] ?? '').toString(),
        title:      title,
        url:        videoUrl,
        coverUrl:   '',  // 新 API 无封面字段
        author:     '',
        uid:        '',
        created:    '',
        fullCached: false,
        headCached: false,
      );
    } catch (_) {
      return null;
    }
  }

  /// 尝试把 URL 文件名解码成可读标题（处理 %E4%B8%AD 等 URL 编码）
  static String _decodeFileName(String raw) {
    try {
      // 去掉扩展名
      final withoutExt = raw.split('.').isEmpty ? raw : raw.substring(0, raw.lastIndexOf('.'));
      return Uri.decodeComponent(withoutExt);
    } catch (_) {
      return '视频';
    }
  }
}
