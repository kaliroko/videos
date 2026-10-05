/// 碎碎念 · 状态管理
library;

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_comment.dart';
import '../models/diary_post.dart';
import '../repository/diary_cache.dart';
import '../repository/diary_repository.dart';

/// 一次拉多少条
const int kDiaryPageSize = 60;

class DiaryProvider extends ChangeNotifier {
  DiaryRepository? _repo;
  List<DiaryPost> _posts = const <DiaryPost>[];

  /// 评论全量放在内存里：卡片上的评论数直接从这儿数，永远和列表一致
  List<DiaryComment> _comments = const <DiaryComment>[];

  /// ★ 按动态分组 + 计数只算一次，别在每张卡片 build 时遍历全部评论。
  ///   60 条动态 × 400 条评论 = 每次重建 24000 次循环，会卡。
  Map<String, List<DiaryComment>> _commentsByPost =
      const <String, List<DiaryComment>>{};
  Map<String, int> _commentCounts = const <String, int>{};

  bool _sendingComment = false;

  /// 当前屏幕上这批内容是缓存铺出来的（网络还没回来）
  bool _fromCache = false;

  String _deviceId = '';
  bool _loading = true;
  bool _ready = false;
  bool _publishing = false;
  String? _error;

  /// 上次用过的昵称 / 匿名偏好
  String _nickname = '';
  bool _anonymous = false;

  bool _disposed = false;

  /// init() 只会真正跑一次
  bool _started = false;

  static const String _kNicknameKey = 'diary_nickname';
  static const String _kAnonymousKey = 'diary_anonymous';

  // ── 对外只读 ────────────────────────────────────────────────────────

  List<DiaryPost> get posts => _posts;
  bool get loading => _loading;
  bool get ready => _ready;
  bool get publishing => _publishing;
  bool get sendingComment => _sendingComment;
  bool get fromCache => _fromCache;
  String? get error => _error;
  String get deviceId => _deviceId;
  String get backendLabel => _repo?.backendLabel ?? '本机';
  bool get isCloud => _repo?.isCloud ?? false;
  bool get isEmpty => _ready && _posts.isEmpty;

  String get nickname => _nickname;
  bool get anonymous => _anonymous;

  /// 某条动态下的评论，按时间正序。O(1)
  List<DiaryComment> commentsFor(String postId) =>
      _commentsByPost[postId] ?? const <DiaryComment>[];

  /// 某条动态有几条评论。O(1)
  int commentCountFor(String postId) => _commentCounts[postId] ?? 0;

  /// 评论变了就重建一次索引（只在数据变动时调用，不在 build 里）
  void _rebuildCommentIndex() {
    if (_comments.isEmpty) {
      _commentsByPost = const <String, List<DiaryComment>>{};
      _commentCounts = const <String, int>{};
      return;
    }
    final byPost = <String, List<DiaryComment>>{};
    for (final c in _comments) {
      (byPost[c.postId] ??= <DiaryComment>[]).add(c);
    }
    _commentsByPost = byPost;
    _commentCounts = <String, int>{
      for (final entry in byPost.entries) entry.key: entry.value.length,
    };
  }

  void _setComments(List<DiaryComment> comments) {
    _comments = comments;
    _rebuildCommentIndex();
  }

  // ── 生命周期 ────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// 只跑一次
  Future<void> init() async {
    if (_started) return;
    _started = true;

    await _loadIdentity();

    // ── ① 先把上次的缓存铺出来 ──────────────────────────────────────
    // 云端模式要先探测 Supabase（最长 6 秒）才能拿数据，这段时间屏幕空着很难看。
    // 有缓存就先渲染卡片，网络回来再无声替换。
    _loading = true;
    _safeNotify();
    try {
      final cachedPosts = await DiaryCache.readPosts();
      if (cachedPosts.isNotEmpty) {
        _posts = cachedPosts;
        _setComments(await DiaryCache.readComments());
        _fromCache = true;
        _ready = true;
        _loading = false;
        _safeNotify();
        debugPrint('[Diary] 📦 缓存先顶上 - ${cachedPosts.length} 条');
      }
    } catch (e) {
      debugPrint('[Diary] 读缓存失败（忽略）: $e');
    }

    // ── ② 再联网刷新 ────────────────────────────────────────────────
    try {
      _deviceId = await _readDeviceId();
      _repo = await DiaryRepository.resolve(deviceId: _deviceId);
      _posts = await _repo!.fetch(limit: kDiaryPageSize);
      _setComments(await _loadCommentsSafe(_repo!));
      _error = null;
      _fromCache = false;
      await _saveCache();
      debugPrint(
          '[Diary] 就绪 - $backendLabel - ${_posts.length} 条动态 / ${_comments.length} 条评论');
    } catch (e) {
      _error = e.toString();
      // ★ 刷新失败就保留缓存，别把用户已经看到的卡片清掉
      debugPrint('[Diary] 初始化失败（保留缓存）: $e');
    } finally {
      _loading = false;
      _ready = true;
      _safeNotify();
    }
  }

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      _posts = await repo.fetch(limit: kDiaryPageSize);
      _setComments(await _loadCommentsSafe(repo));
      _error = null;
      _fromCache = false;
      await _saveCache();
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 刷新失败: $e');
    }
    _safeNotify();
  }

  /// 缓存写盘失败无所谓，不该影响主流程
  Future<void> _saveCache() async {
    try {
      await DiaryCache.writePosts(_posts);
      await DiaryCache.writeComments(_comments);
    } catch (e) {
      debugPrint('[Diary] 写缓存失败（忽略）: $e');
    }
  }

  /// 评论拉不到不该把整页拖垮：动态照常显示，只是评论数先当 0
  Future<List<DiaryComment>> _loadCommentsSafe(DiaryRepository repo) async {
    try {
      return await repo.fetchComments(limit: kDiaryCommentLimit);
    } catch (e) {
      debugPrint('[Diary] 评论加载失败（忽略）: $e');
      return _comments;
    }
  }

  /// 在某条动态下发一条评论，成功返回 true
  Future<bool> addComment({
    required String postId,
    required String authorName,
    required bool anonymous,
    required String content,
  }) async {
    final repo = _repo;
    final text = content.trim();
    if (repo == null || _sendingComment || text.isEmpty) return false;

    _sendingComment = true;
    _safeNotify();

    try {
      final comment = await repo.addComment(
        postId: postId,
        authorName: authorName.trim(),
        anonymous: anonymous,
        content: text,
      );
      _setComments(<DiaryComment>[..._comments, comment]);
      _error = null;
      _fromCache = false;
      await _saveCache();
      await saveIdentity(
        nickname: anonymous ? _nickname : authorName,
        anonymous: anonymous,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 评论失败: $e');
      return false;
    } finally {
      _sendingComment = false;
      _safeNotify();
    }
  }

  /// 发布一条，成功返回 true
  Future<bool> publish(DiaryDraft draft) async {
    final repo = _repo;
    if (repo == null || _publishing) return false;

    _publishing = true;
    _safeNotify();

    try {
      final post = await repo.create(draft);
      _posts = <DiaryPost>[post, ..._posts];
      _error = null;
      _fromCache = false;
      await _saveCache();
      await saveIdentity(
        nickname: draft.anonymous ? _nickname : draft.authorName,
        anonymous: draft.anonymous,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 发布失败: $e');
      return false;
    } finally {
      _publishing = false;
      _safeNotify();
    }
  }

  /// 删掉自己写的一条
  Future<bool> remove(DiaryPost post) async {
    final repo = _repo;
    if (repo == null) return false;

    try {
      await repo.remove(post);
      _posts = _posts.where((e) => e.id != post.id).toList(growable: false);
      // 动态没了，它下面的评论也别留在内存里
      _setComments(
        _comments.where((c) => c.postId != post.id).toList(growable: false),
      );
      await _saveCache();
      _safeNotify();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 删除失败: $e');
      _safeNotify();
      return false;
    }
  }

  // ── 昵称 / 匿名偏好 ─────────────────────────────────────────────────

  Future<void> saveIdentity({
    required String nickname,
    required bool anonymous,
  }) async {
    _nickname = nickname.trim();
    _anonymous = anonymous;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kNicknameKey, _nickname);
      await prefs.setBool(_kAnonymousKey, anonymous);
    } catch (e) {
      debugPrint('[Diary] 昵称保存失败: $e');
    }
  }

  Future<void> _loadIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _nickname = prefs.getString(_kNicknameKey) ?? '';
      _anonymous = prefs.getBool(_kAnonymousKey) ?? false;
    } catch (e) {
      debugPrint('[Diary] 昵称读取失败: $e');
    }
  }

  /// 设备号充当匿名身份 —— 和聊天室保持一致
  Future<String> _readDeviceId() async {
    try {
      if (!Platform.isAndroid) return 'unknown-device';
      final info = await DeviceInfoPlugin().androidInfo;
      return info.id.isEmpty ? 'unknown-device' : info.id;
    } catch (e) {
      debugPrint('[Diary] 读取设备号失败: $e');
      return 'unknown-device';
    }
  }
}
