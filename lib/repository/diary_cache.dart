/// 碎碎念 · 本地缓存
///
/// 目的：冷启动时**立刻**有内容可看。
///
/// 云端模式下，`init()` 要先探测 Supabase（最长 6 秒）再拉列表，
/// 这段时间里屏幕上是空的，很难看。所以每次拿到数据后都往本地存一份，
/// 下次启动先把这份缓存铺出来，网络回来再无声替换。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_comment.dart';
import '../models/diary_post.dart';
import '../models/diary_reaction.dart';

class DiaryCache {
  DiaryCache._();

  static const String _kPostsKey = 'diary_cache_posts_v1';
  static const String _kCommentsKey = 'diary_cache_comments_v1';
  static const String _kReactionsKey = 'diary_cache_reactions_v1';

  /// 缓存上限：够铺满首屏就行，别让 prefs 无限膨胀
  static const int _kMaxPosts = 120;
  static const int _kMaxComments = 400;
  static const int _kMaxReactions = 4000;

  // ── 动态 ──────────────────────────────────────────────────────────

  static Future<List<DiaryPost>> readPosts() async {
    return _read(
      _kPostsKey,
      (m) => DiaryPost.fromJson(m),
      _kMaxPosts,
    );
  }

  static Future<void> writePosts(List<DiaryPost> posts) async {
    await _write(
      _kPostsKey,
      posts.take(_kMaxPosts).map((e) => e.toJson()).toList(growable: false),
    );
  }

  // ── 评论 ──────────────────────────────────────────────────────────

  static Future<List<DiaryComment>> readComments() async {
    return _read(
      _kCommentsKey,
      (m) => DiaryComment.fromJson(m),
      _kMaxComments,
    );
  }

  static Future<void> writeComments(List<DiaryComment> comments) async {
    final tail = comments.length > _kMaxComments
        ? comments.sublist(comments.length - _kMaxComments)
        : comments;
    await _write(
      _kCommentsKey,
      tail.map((e) => e.toJson()).toList(growable: false),
    );
  }

  // ── 表情反应 ──────────────────────────────────────────────────────

  static Future<List<DiaryReaction>> readReactions() async {
    final all = await _read(
      _kReactionsKey,
      (m) => DiaryReaction.fromJson(m),
      _kMaxReactions,
    );
    return all.where((r) => DiaryReaction.isValidEmoji(r.emoji)).toList(growable: false);
  }

  static Future<void> writeReactions(List<DiaryReaction> reactions) async {
    final tail = reactions.length > _kMaxReactions
        ? reactions.sublist(reactions.length - _kMaxReactions)
        : reactions;
    await _write(
      _kReactionsKey,
      tail.map((e) => e.toJson()).toList(growable: false),
    );
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPostsKey);
      await prefs.remove(_kCommentsKey);
      await prefs.remove(_kReactionsKey);
      debugPrint('[Diary] 缓存已清空');
    } catch (e) {
      debugPrint('[Diary] 清缓存失败: $e');
    }
  }

  // ── 内部 ──────────────────────────────────────────────────────────

  static Future<List<T>> _read<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
    int limit,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return <T>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];

      final out = <T>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            out.add(parse(Map<String, dynamic>.from(item)));
          } catch (_) {
            // 单条脏数据不该毁掉整个缓存
          }
        }
      }
      return out.length > limit ? out.sublist(0, limit) : out;
    } catch (e) {
      debugPrint('[Diary] 读缓存失败($key): $e');
      return <T>[];
    }
  }

  static Future<void> _write(String key, List<Map<String, dynamic>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(rows));
    } catch (e) {
      debugPrint('[Diary] 写缓存失败($key): $e');
    }
  }
}
