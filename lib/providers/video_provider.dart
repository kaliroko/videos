/// 视频数据提供者 — 支持两套API源
///   • source == old → 旧 listHot（AES-CBC，m.py Flask后端）
///   • source == new → 新 JWT CMS API（AES-ECB，移植文档）
library;

import 'package:flutter/foundation.dart' hide Category;
import 'package:bilibili_glass/repository/api_repository.dart';
import 'package:bilibili_glass/repository/api_gateway.dart';
import 'package:bilibili_glass/models/video_model.dart';

enum VideoSource { oldApi, newApi }

class VideoProvider extends ChangeNotifier {
  // ── 状态 ───────────────────────────────────────────────────────────────
  List<MovieBean> _videos = [];
  String? _error;
  bool _loading = false;
  VideoSource _source = VideoSource.newApi;
  Category _activeCategory = ApiService.catRecommend;
  int _currentPage = 1;
  bool _hasMore = true;

  List<MovieBean> get videos => _videos;
  String? get error => _error;
  bool get loading => _loading;
  VideoSource get source => _source;
  Category get activeCategory => _activeCategory;
  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;

  // ── 切换API源 ──────────────────────────────────────────────────────────
  void setSource(VideoSource source) {
    if (_source == source) return;
    _source = source;
    _videos.clear();
    _currentPage = 1;
    _hasMore = true;
    _error = null;
    notifyListeners();
    fetchVideos(refresh: true);
  }

  // ── 切换分类 ──────────────────────────────────────────────────────────
  void selectCategory(Category cat) {
    if (_activeCategory == cat) return;
    _activeCategory = cat;
    _videos.clear();
    _currentPage = 1;
    _hasMore = true;
    _error = null;
    notifyListeners();
    fetchVideos(refresh: true);
  }

  // ── 加载更多 ──────────────────────────────────────────────────────────
  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _currentPage++;
    await fetchVideos(refresh: false);
  }

  // ── 刷新 ──────────────────────────────────────────────────────────────
  Future<void> fetchVideos({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _videos.clear();
      _hasMore = true;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      List<MovieBean> list;
      if (_source == VideoSource.oldApi) {
        // 旧API（m.py Flask）— 返回旧VideoItem，需转换
        final oldList = await ApiRepository.fetchVideos();
        list = oldList.map(_convertOldToMovie).toList();
      } else {
        // 新JWT API
        list = await ApiService.fetchList(
          groupId: _activeCategory.id,
          page: _currentPage,
        );
        // 检查是否还有更多（列表长度 < pageSize 表示最后一页）
        _hasMore = list.length >= 20;
      }

      if (refresh) {
        _videos = list;
      } else {
        _videos.addAll(list);
      }

      if (list.isEmpty && refresh) {
        _error = list.isEmpty ? '暂无数据' : null;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 将旧 VideoItem 转换为 MovieBean（兼容展示）
  static MovieBean _convertOldToMovie(VideoItem item) {
    return MovieBean(
      id:         item.id,
      title:      item.title,
      coverUrl:   item.coverUrl,
      vodPic:     item.coverUrl,
      playUrl:    item.url,
      author:     AuthorInfo(nickName: item.author, avatar: '', id: 0),
      description: '',
      duration:   0,
    );
  }
}