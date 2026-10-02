/// 视频数据提供者 — 支持两个 API 源
///   • 旧API (VideoSource.oldApi) → api_repository.dart（AES-CBC，m.py 原逻辑）
///   • 新API (VideoSource.newApi) → simple_api.dart（GET https://api.kuleu.com/api/sjxjj）
library;

import 'package:flutter/foundation.dart';
import 'package:bilibili_glass/repository/api_repository.dart';
import 'package:bilibili_glass/repository/simple_api.dart';
import 'package:bilibili_glass/models/video_model.dart';

enum VideoSource { oldApi, newApi }

class VideoProvider extends ChangeNotifier {
  List<VideoItem> _videos = [];
  bool _loading = false;
  String? _error;
  bool _hasMore = false;
  VideoSource _source = VideoSource.oldApi;

  List<VideoItem> get videos     => _videos;
  bool            get loading    => _loading;
  String?         get error      => _error;
  bool            get hasMore    => _hasMore;
  VideoSource     get source     => _source;

  void setSource(VideoSource source) {
    if (_source == source) return;
    _source = source;
    _videos.clear();
    _hasMore = false;
    _error = null;
    notifyListeners();
    fetchVideos();
  }

  Future<void> fetchVideos() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (_source == VideoSource.oldApi) {
        _videos = await ApiRepository.fetchVideos();
      } else {
        // 新API：一次拉 1 条，由 TiktokFeedScreen 自己管理加载
        _videos = await SimpleApiRepository.fetchVideos(count: 1);
      }
      _hasMore = false;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}