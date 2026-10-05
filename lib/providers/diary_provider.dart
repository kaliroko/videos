/// 碎碎念 · 状态管理
library;

import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_post.dart';
import '../repository/diary_repository.dart';

/// 一次拉多少条
const int kDiaryPageSize = 60;

class DiaryProvider extends ChangeNotifier {
  DiaryRepository? _repo;
  List<DiaryPost> _posts = const <DiaryPost>[];

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
  String? get error => _error;
  String get deviceId => _deviceId;
  String get backendLabel => _repo?.backendLabel ?? '本机';
  bool get isCloud => _repo?.isCloud ?? false;
  bool get isEmpty => _ready && _posts.isEmpty;

  String get nickname => _nickname;
  bool get anonymous => _anonymous;

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

    _loading = true;
    _safeNotify();

    try {
      await _loadIdentity();
      _deviceId = await _readDeviceId();
      _repo = await DiaryRepository.resolve(deviceId: _deviceId);
      _posts = await _repo!.fetch(limit: kDiaryPageSize);
      _error = null;
      debugPrint('[Diary] 就绪 - $backendLabel - ${_posts.length} 条');
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 初始化失败: $e');
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
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('[Diary] 刷新失败: $e');
    }
    _safeNotify();
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
