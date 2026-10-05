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
import '../models/diary_post.dart';

/// 云端表名 / 存储桶名
const String kDiaryTable = 'diary_posts';
const String kDiaryBucket = 'diary_images';

/// 一条动态最多几张图
const int kDiaryMaxImages = 9;

/// 正文最多多少字
const int kDiaryMaxLength = 500;

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
      'content': draft.content,
      'images': urls,
      'mood': draft.mood.label,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return DiaryPost.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> remove(DiaryPost post) async {
    await _db
        .from(kDiaryTable)
        .delete()
        .eq('id', post.id)
        .eq('device_id', deviceId);
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
