/// 碎碎念 · 数据仓库
///
/// 两种后端，自动择一：
///   • [SupabaseDiaryRepository] —— 云端，所有人可见，是真正的「分享」
///   • [LocalDiaryRepository]    —— 本机，只写在这台手机上
///
/// [DiaryRepository.resolve] 启动时探一次云端；表还没建、没网、被墙，
/// 都会安静地退回本机模式，不影响使用。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../managers/analytics_manager.dart';
import '../models/diary_comment.dart';
import '../models/diary_reaction.dart';
import '../models/diary_post.dart';

/// 云端表名 / 存储桶名
const String kDiaryTable = 'diary_posts';
const String kDiaryCommentTable = 'diary_comments';
const String kDiaryReactionTable = 'diary_reactions';
const String kDiaryBucket = 'diary_images';

/// 一条动态最多几张图
const int kDiaryMaxImages = 9;

/// 正文最多多少字
const int kDiaryMaxLength = 500;

/// 一条评论最多多少字
const int kDiaryCommentMaxLength = 200;

/// 评论是全量加载的：单条很小，几百条也不占什么。
/// 这样卡片上的评论数可以直接在客户端数出来，
/// 不用维护反范式计数器、也不用写数据库触发器，永远不会数错。
const int kDiaryCommentLimit = 400;

/// 反应同理：单条只有三个短字段，全量拉下来自己数最省事
const int kDiaryReactionLimit = 4000;

abstract class DiaryRepository {
  DiaryRepository({required this.deviceId});

  /// 本机设备号，充当匿名身份
  final String deviceId;

  /// 界面上用来提示数据去哪了
  String get backendLabel;

  bool get isCloud;

  Future<List<DiaryPost>> fetch({int limit});

  Future<DiaryPost> create(DiaryDraft draft);

  Future<void> remove(DiaryPost post);

  /// 拉取评论（全量，按时间正序）
  Future<List<DiaryComment>> fetchComments({int limit});

  /// 发一条评论
  Future<DiaryComment> addComment({
    required String postId,
    required String authorName,
    required bool anonymous,
    required String content,
  });

  /// 拉取全部表情反应（同样全量加载，卡片上的计数就能在客户端数）
  Future<List<DiaryReaction>> fetchReactions({int limit});

  /// 切换某个表情：on = true 加一个，false 取消
  Future<void> toggleReaction({
    required String postId,
    required String emoji,
    required bool on,
  });

  /// 探测器：云端能用就用云端，否则本机
  static Future<DiaryRepository> resolve({required String deviceId}) async {
    try {
      await AnalyticsManager.instance.init();
      await Supabase.instance.client
          .from(kDiaryTable)
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 6));
      debugPrint('[Diary] 云端可用 - $kDiaryTable');
      return SupabaseDiaryRepository(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Diary] 云端不可用（$e）- 退回本机模式');
      return LocalDiaryRepository(deviceId: deviceId);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// 本机模式
// ══════════════════════════════════════════════════════════════════════

class LocalDiaryRepository extends DiaryRepository {
  LocalDiaryRepository({required super.deviceId});

  static const String _kPostsKey = 'diary_posts_v1';
  static const String _kCommentsKey = 'diary_comments_v1';
  static const String _kReactionsKey = 'diary_reactions_v1';
  static const int _kMaxKept = 200;

  @override
  String get backendLabel => '本机';

  @override
  bool get isCloud => false;

  @override
  Future<List<DiaryPost>> fetch({int limit = 60}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPostsKey);
    if (raw == null || raw.isEmpty) return const <DiaryPost>[];

    final posts = <DiaryPost>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            posts.add(DiaryPost.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (e) {
      debugPrint('[Diary] 本机记录解析失败: $e');
    }

    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts.take(limit).toList(growable: false);
  }

  @override
  Future<DiaryPost> create(DiaryDraft draft) async {
    final now = DateTime.now();
    final post = DiaryPost(
      id: now.microsecondsSinceEpoch.toString(),
      deviceId: deviceId,
      authorName: draft.authorName,
      anonymous: draft.anonymous,
      title: draft.title,
      // ★ 匿名就不带地区和头像出去
      location: draft.anonymous ? '' : draft.location,
      avatarUrl: draft.anonymous ? '' : draft.avatarUrl,
      content: draft.content,
      images: await _copyIntoAppDir(draft.images),
      mood: draft.mood,
      createdAt: now,
    );

    final all = await fetch(limit: _kMaxKept);
    await _saveAll(<DiaryPost>[post, ...all]);
    return post;
  }

  @override
  Future<void> remove(DiaryPost post) async {
    // ★ 本机模式没有服务端兜底，这一层必须自己挡：
    //   下面只按 id 过滤，不校验归属的话，传进来别人的动态照样会被删掉。
    if (post.deviceId != deviceId) {
      debugPrint('[Diary] 拒绝删除：这条不是本机写的');
      return;
    }

    final all = await fetch(limit: _kMaxKept);
    await _saveAll(all.where((e) => e.id != post.id).toList(growable: false));

    for (final path in post.images) {
      if (path.startsWith('http')) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[Diary] 删除图片失败: $e');
      }
    }
  }

  Future<void> _saveAll(List<DiaryPost> posts) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = posts.map((e) => e.toJson()).toList(growable: false);
    await prefs.setString(_kPostsKey, jsonEncode(payload));
  }

  // ── 评论 ──────────────────────────────────────────────────────────

  @override
  Future<List<DiaryComment>> fetchComments({int limit = kDiaryCommentLimit}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCommentsKey);
    if (raw == null || raw.isEmpty) return const <DiaryComment>[];

    final comments = <DiaryComment>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            comments.add(DiaryComment.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (e) {
      debugPrint('[Diary] 本机评论解析失败: $e');
    }

    comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return comments.length > limit
        ? comments.sublist(comments.length - limit)
        : comments;
  }

  @override
  Future<DiaryComment> addComment({
    required String postId,
    required String authorName,
    required bool anonymous,
    required String content,
  }) async {
    final now = DateTime.now();
    final comment = DiaryComment(
      id: now.microsecondsSinceEpoch.toString(),
      postId: postId,
      deviceId: deviceId,
      authorName: authorName,
      anonymous: anonymous,
      content: content,
      createdAt: now,
    );

    final all = await fetchComments();
    final next = <DiaryComment>[...all, comment];
    // 超出上限就丢掉最旧的，别让 prefs 无限膨胀
    final trimmed = next.length > kDiaryCommentLimit
        ? next.sublist(next.length - kDiaryCommentLimit)
        : next;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCommentsKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList(growable: false)),
    );
    return comment;
  }

  // ── 表情反应 ──────────────────────────────────────────────────────

  @override
  Future<List<DiaryReaction>> fetchReactions(
      {int limit = kDiaryReactionLimit}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kReactionsKey);
    if (raw == null || raw.isEmpty) return const <DiaryReaction>[];

    final out = <DiaryReaction>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final r = DiaryReaction.fromJson(Map<String, dynamic>.from(item));
            if (DiaryReaction.isValidEmoji(r.emoji)) out.add(r);
          }
        }
      }
    } catch (e) {
      debugPrint('[Diary] 本机反应解析失败: $e');
    }
    return out;
  }

  @override
  Future<void> toggleReaction({
    required String postId,
    required String emoji,
    required bool on,
  }) async {
    if (!DiaryReaction.isValidEmoji(emoji)) return;

    final all = await fetchReactions();
    final mine = DiaryReaction(postId: postId, deviceId: deviceId, emoji: emoji);
    final next = <DiaryReaction>[
      for (final r in all)
        if (r.key != mine.key) r,
      if (on) mine,
    ];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kReactionsKey,
      jsonEncode(next.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  /// 相册选出来的是缓存路径，会被系统清掉 —— 必须复制进 App 私有目录
  Future<List<String>> _copyIntoAppDir(List<String> sources) async {
    if (sources.isEmpty) return const <String>[];

    final copied = <String>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'diary'));
      if (!dir.existsSync()) await dir.create(recursive: true);

      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < sources.length; i++) {
        try {
          final src = File(sources[i]);
          if (!src.existsSync()) continue;
          final ext = p.extension(src.path).isEmpty
              ? '.jpg'
              : p.extension(src.path).toLowerCase();
          final dst = File(p.join(dir.path, '${stamp}_$i$ext'));
          await src.copy(dst.path);
          copied.add(dst.path);
        } catch (e) {
          debugPrint('[Diary] 第 $i 张图落盘失败: $e');
        }
      }
    } catch (e) {
      debugPrint('[Diary] 图片目录准备失败: $e');
    }
    return copied;
  }
}

// ══════════════════════════════════════════════════════════════════════
// 云端模式
// ══════════════════════════════════════════════════════════════════════

class SupabaseDiaryRepository extends DiaryRepository {
  SupabaseDiaryRepository({required super.deviceId});

  SupabaseClient get _db => Supabase.instance.client;

  @override
  String get backendLabel => '云端';

  @override
  bool get isCloud => true;

  @override
  Future<List<DiaryPost>> fetch({int limit = 60}) async {
    final data = await _db
        .from(kDiaryTable)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiaryPost.fromJson).toList(growable: false);
  }

  @override
  Future<DiaryPost> create(DiaryDraft draft) async {
    final urls = await _uploadAll(draft.images);
    final data = await _db.from(kDiaryTable).insert(<String, dynamic>{
      'device_id': deviceId,
      'author_name': draft.authorName,
      'anonymous': draft.anonymous,
      'title': draft.title,
      // ★ 匿名就不带地区和头像出去
      'location': draft.anonymous ? '' : draft.location,
      'avatar_url': draft.anonymous ? '' : draft.avatarUrl,
      'content': draft.content,
      'images': urls,
      'mood': draft.mood.label,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return DiaryPost.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> remove(DiaryPost post) async {
    // ★ 云端这一层真正的保护是下面那个 .eq('device_id', deviceId)：
    //   就算把上面所有客户端的判断都绕过，请求本身也只匹配自己的行。
    //   前置守卫是为了少发一次注定删不到东西的请求，也让意图更明确。
    if (post.deviceId != deviceId) {
      debugPrint('[Diary] 拒绝删除：这条不是本机写的');
      return;
    }

    await _db
        .from(kDiaryTable)
        .delete()
        .eq('id', post.id)
        .eq('device_id', deviceId);
  }

  // ── 评论 ──────────────────────────────────────────────────────────

  @override
  Future<List<DiaryComment>> fetchComments({int limit = kDiaryCommentLimit}) async {
    final data = await _db
        .from(kDiaryCommentTable)
        .select()
        .order('created_at', ascending: true)
        .limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(DiaryComment.fromJson).toList(growable: false);
  }

  @override
  Future<DiaryComment> addComment({
    required String postId,
    required String authorName,
    required bool anonymous,
    required String content,
  }) async {
    final data = await _db
        .from(kDiaryCommentTable)
        .insert(<String, dynamic>{
          'post_id': postId,
          'device_id': deviceId,
          'author_name': authorName,
          'anonymous': anonymous,
          'content': content,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();

    return DiaryComment.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // ── 表情反应 ──────────────────────────────────────────────────────

  @override
  Future<List<DiaryReaction>> fetchReactions(
      {int limit = kDiaryReactionLimit}) async {
    final data = await _db.from(kDiaryReactionTable).select().limit(limit);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows
        .map(DiaryReaction.fromJson)
        .where((r) => DiaryReaction.isValidEmoji(r.emoji))
        .toList(growable: false);
  }

  @override
  Future<void> toggleReaction({
    required String postId,
    required String emoji,
    required bool on,
  }) async {
    if (!DiaryReaction.isValidEmoji(emoji)) return;

    if (on) {
      // 靠 (post_id, device_id, emoji) 的唯一约束防重复，
      // 重复点也只会是一条，不会把计数刷上去
      await _db.from(kDiaryReactionTable).upsert(
        <String, dynamic>{
          'post_id': postId,
          'device_id': deviceId,
          'emoji': emoji,
        },
        onConflict: 'post_id,device_id,emoji',
      );
    } else {
      await _db
          .from(kDiaryReactionTable)
          .delete()
          .eq('post_id', postId)
          .eq('device_id', deviceId)
          .eq('emoji', emoji);
    }
  }

  Future<List<String>> _uploadAll(List<String> sources) async {
    final urls = <String>[];
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      if (src.startsWith('http')) {
        urls.add(src);
        continue;
      }
      try {
        final file = File(src);
        if (!file.existsSync()) continue;

        final ext = p.extension(src).isEmpty
            ? '.jpg'
            : p.extension(src).toLowerCase();
        final objectPath =
            '$deviceId/${DateTime.now().microsecondsSinceEpoch}_$i$ext';

        await _db.storage.from(kDiaryBucket).uploadBinary(
              objectPath,
              await file.readAsBytes(),
              fileOptions: FileOptions(
                contentType: _mimeOf(ext),
                upsert: false,
              ),
            );

        urls.add(_db.storage.from(kDiaryBucket).getPublicUrl(objectPath));
      } catch (e) {
        debugPrint('[Diary] 第 $i 张图上传失败: $e');
      }
    }
    return urls;
  }

  static String _mimeOf(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
