/// 新 API — https://api.kuleu.com/api/sjxjj
/// 简单 GET 请求，无加密，每次返回一条随机视频
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bilibili_glass/models/video_model.dart';

const _newApiUrl = 'https://api.kuleu.com/api/sjxjj';

class SimpleApiRepository {
  /// 单次请求一条视频
  static Future<VideoItem?> fetchOne() async {
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
      if (!videoUrl.contains(RegExp(
          r'\.(mp4|m3u8|flv|ts|mov)', caseSensitive: false))) {
        return null;
      }

      final rawName = videoUrl.split('/').last.split('?').first;
      final title = _decodeFileName(rawName);

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
    } catch (_) {
      return null;
    }
  }

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