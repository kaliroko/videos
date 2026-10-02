/// 视频数据提供者 — 支持两个 API 源
///   • 旧API (VideoSource.old) → api_repository.dart（AES-CBC，m.py 原逻辑）
///   • 新API (VideoSource.new) → simple_api.dart（GET https://api.kuleu.com/api/sjxjj）
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
  VideoSource _source = VideoSource.oldApi;

  List<VideoItem> get videos        => _videos;
  bool        get loading           => _loading;
  String?     get error             => _error;
  VideoSource get source            => _source;

  void setSource(VideoSource source) {
    if (_source == source) return;
    _source = source;
    _videos.clear();
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
      _videos = _source == VideoSource.oldApi
          ? await ApiRepository.fetchVideos()
          : await SimpleApiRepository.fetchVideos();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}