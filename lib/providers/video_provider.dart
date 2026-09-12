/// 视频数据 Provider — 连接 m.py Flask 后端 API
///
/// 后端地址可通过 [serverUrl] 设置，默认使用本机地址。
/// 运行 m.py 后，在首页点击右下角「⚙ 设置」可修改地址。
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:bilibili_glass/models/video_model.dart';

class VideoProvider extends ChangeNotifier {
  static const String _defaultServerUrl = 'http://192.168.1.100:5000';

  String _serverUrl = _defaultServerUrl;
  List<VideoItem> _videos = [];
  bool _loading = false;
  String? _error;

  String get serverUrl => _serverUrl;
  List<VideoItem> get videos => _videos;
  bool get loading => _loading;
  String? get error => _error;

  void setServerUrl(String url) {
    _serverUrl = url.trim();
    notifyListeners();
  }

  String _proxyUrl(String rawUrl) => '$_serverUrl/proxy?url=${Uri.encodeComponent(rawUrl)}';

  /// 从后端获取视频列表
  Future<void> fetchVideos() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$_serverUrl/api/videos');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _error = 'HTTP ${response.statusCode}';
        return;
      }

      final List<dynamic> list = jsonDecode(response.body);
      _videos = list.map((e) => VideoItem.fromJson(e as Map<String, dynamic>)).toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 获取代理后的视频播放 URL（完整或头部缓存）
  String getPlayUrl(String rawUrl) => _proxyUrl(rawUrl);

  /// 获取代理后的封面 URL
  String getCoverUrl(String rawCoverUrl) {
    if (rawCoverUrl.isEmpty) return '';
    return _proxyUrl(rawCoverUrl);
  }
}