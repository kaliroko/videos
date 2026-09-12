/// 视频数据 Provider — 直接调用上游 API（无需 m.py）
library;

import 'package:flutter/foundation.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/repository/api_repository.dart';

class VideoProvider extends ChangeNotifier {
  List<VideoItem> _videos = [];
  bool _loading = false;
  String? _error;

  List<VideoItem> get videos => _videos;
  bool get loading => _loading;
  String? get error => _error;

  /// 从上游 API 直接抓取视频列表
  Future<void> fetchVideos() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _videos = await ApiRepository.fetchAll();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 刷新（重新抓取）
  Future<void> refresh() async {
    await fetchVideos();
  }
}
