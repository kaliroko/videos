/// 视频模型 — 对接 m.py Flask 后端 API
library;

class VideoItem {
  final String id;
  final String title;
  final String url;       // 原始视频 URL（将被 /proxy?url= 代理）
  final String coverUrl;  // 封面图 URL（同样经 /proxy 代理）
  final String author;
  final String uid;
  final String created;   // 原始时间字符串，例如 "2025-09-01 12:00:00"

  /// 服务端返回的缓存状态
  final bool fullCached;
  final bool headCached;

  const VideoItem({
    required this.id,
    required this.title,
    required this.url,
    required this.coverUrl,
    required this.author,
    required this.uid,
    required this.created,
    this.fullCached = false,
    this.headCached = false,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id:      (json['id']     ?? '').toString(),
      title:   (json['title']  ?? '').toString(),
      url:     (json['url']    ?? '').toString(),
      coverUrl: (json['cover'] ?? '').toString(),
      author:  (json['author'] ?? '').toString(),
      uid:     (json['uid']    ?? '').toString(),
      created: (json['created'] ?? '').toString(),
      fullCached:  json['full_cached']  == true,
      headCached:  json['head_cached']  == true,
    );
  }

  VideoItem copyWith({
    String? id,
    String? title,
    String? url,
    String? coverUrl,
    String? author,
    String? uid,
    String? created,
    bool? fullCached,
    bool? headCached,
  }) {
    return VideoItem(
      id:       id       ?? this.id,
      title:    title    ?? this.title,
      url:      url      ?? this.url,
      coverUrl: coverUrl ?? this.coverUrl,
      author:   author   ?? this.author,
      uid:      uid      ?? this.uid,
      created:  created  ?? this.created,
      fullCached: fullCached ?? this.fullCached,
      headCached: headCached ?? this.headCached,
    );
  }
}