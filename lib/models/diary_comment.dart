/// 碎碎念 · 动态评论
///
/// 和动态一样走匿名身份（设备号），昵称可自定义也可匿名。
library;

import 'diary_post.dart';

/// 一条评论
class DiaryComment {
  const DiaryComment({
    required this.id,
    required this.postId,
    required this.deviceId,
    required this.authorName,
    required this.anonymous,
    required this.content,
    required this.createdAt,
  });

  /// 本机模式下是时间戳字符串，云端模式是数据库主键
  final String id;

  /// 挂在哪条动态下
  final String postId;

  final String deviceId;
  final String authorName;
  final bool anonymous;
  final String content;
  final DateTime createdAt;

  // ── 展示辅助 ────────────────────────────────────────────────────────

  String get displayName {
    if (anonymous) return kAnonymousName;
    final n = authorName.trim();
    return n.isEmpty ? kAnonymousName : n;
  }

  String get initial {
    final n = displayName;
    if (n.isEmpty) return '念';
    return String.fromCharCode(n.runes.first);
  }

  bool isMine(String? myDeviceId) =>
      myDeviceId != null && myDeviceId.isNotEmpty && deviceId == myDeviceId;

  // ── 序列化 ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'post_id': postId,
        'device_id': deviceId,
        'author_name': authorName,
        'anonymous': anonymous,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  factory DiaryComment.fromJson(Map<String, dynamic> m) => DiaryComment(
        id: (m['id'] ?? '').toString(),
        postId: (m['post_id'] ?? '').toString(),
        deviceId: (m['device_id'] ?? '').toString(),
        authorName: (m['author_name'] ?? '').toString(),
        anonymous: m['anonymous'] == true,
        content: (m['content'] ?? '').toString(),
        createdAt: _parseTime(m['created_at']),
      );

  Map<String, dynamic> toInsertMap() => <String, dynamic>{
        'post_id': postId,
        'device_id': deviceId,
        'author_name': authorName,
        'anonymous': anonymous,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static DateTime _parseTime(Object? raw) {
    if (raw == null) return DateTime.now();
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }
}
