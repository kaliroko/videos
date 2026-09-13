/// 视频模型 — 兼容两套 API：
///   • 旧 listHot（AES-CBC，mv_* 字段）
///   • 新 JWT API（AES-ECB，vod_* 字段）
library;

import 'dart:convert';

// ─── 旧 API（listHot）数据模型 ──────────────────────────────────────

class VideoItem {
  final String id;
  final String title;
  final String url;           // 原始视频 URL（将被 /proxy?url= 代理）
  final String coverUrl;      // 封面图 URL
  final String author;
  final String uid;
  final String created;       // "2025-09-01 12:00:00"
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
      id:       (json['id']       ?? '').toString(),
      title:    (json['title']    ?? '').toString(),
      url:      (json['url']      ?? '').toString(),
      coverUrl: (json['cover']    ?? '').toString(),
      author:   (json['author']   ?? '').toString(),
      uid:      (json['uid']      ?? '').toString(),
      created:  (json['created']  ?? '').toString(),
      fullCached:  json['full_cached']  == true,
      headCached:  json['head_cached']  == true,
    );
  }
}

// ─── 新 API（JWT CMS）数据模型 — MovieBean ──────────────────────────

/// vodPicInfo JSON 子对象
class VodPicInfo {
  final String? horizontalSmall;
  final String? horizontalLarge;
  final String? verticalSmall;
  final String? verticalLarge;

  VodPicInfo({this.horizontalSmall, this.horizontalLarge,
              this.verticalSmall, this.verticalLarge});

  factory VodPicInfo.fromJson(dynamic v) {
    if (v is String) {
      try {
        final parsed = jsonDecode(v) as Map<String, dynamic>;
        return VodPicInfo.fromJson(parsed);
      } catch (_) {
        return VodPicInfo();
      }
    }
    if (v is! Map<String, dynamic>) return VodPicInfo();
    return VodPicInfo(
      horizontalSmall: v['horizontal_small'] as String?,
      horizontalLarge: v['horizontal_large'] as String?,
      verticalSmall:   v['vertical_small']   as String?,
      verticalLarge:   v['vertical_large']   as String?,
    );
  }
}

/// 多分辨率播放项
class VideoQuality {
  final String url;
  final String type;  // "720p", "1080p" …
  final int duration; // ms
  final int size;    // KB

  VideoQuality({required this.url, required this.type,
                required this.duration, required this.size});

  factory VideoQuality.fromJson(Map<String, dynamic> json) {
    return VideoQuality(
      url:      (json['addr']      ?? '').toString(),
      type:     (json['type']      ?? '').toString(),
      duration: json['duration']    ?? 0,
      size:     json['size']        ?? 0,
    );
  }
}

/// 作者信息
class AuthorInfo {
  final String nickName;
  final String avatar;
  final int id;

  AuthorInfo({required this.nickName, required this.avatar, required this.id});

  factory AuthorInfo.fromJson(Map<String, dynamic> json) {
    return AuthorInfo(
      nickName: (json['nickName'] ?? '').toString(),
      avatar:   (json['avatar']   ?? '').toString(),
      id:       json['id'] ?? 0,
    );
  }
}

/// 视频统计
class VideoStats {
  final int likeNumber;
  final int readNumber;
  final double starAvg;

  VideoStats({this.likeNumber = 0, this.readNumber = 0, this.starAvg = 0.0});

  factory VideoStats.fromJson(Map<String, dynamic> json) {
    return VideoStats(
      likeNumber:  json['likeNumber']  ?? 0,
      readNumber:  json['readNumber']  ?? 0,
      starAvg:     (json['starAvg']   ?? 0).toDouble(),
    );
  }
}

/// 新 API 单个视频条目（MovieBean 映射）
class MovieBean {
  final String id;            // vodId
  final String title;         // vodName
  final String coverUrl;      // 已拼接 picBaseUrl 的封面
  final String vodPic;        // 原始 vodPic（可能为相对路径）
  final VodPicInfo? picInfo;  // vodPicInfo JSON
  final String playUrl;       // vodPlayUrl（多集用 # 分隔，或 m3u8 相对路径）
  final List<VideoQuality>? qualities; // vodFullPlayUrl
  final String mp4Url;        // mp4 字段（MP4直链）
  final int duration;         // vodDuration（毫秒）
  final AuthorInfo author;
  final String description;   // vodIntro
  final String category;      // vodClass
  final String area;          // vodArea
  final String year;          // vodYear
  final bool isVip;           // isVip
  final int gold;             // 所需金币
  final VideoStats stats;
  final int createTime;       // 时间戳

  MovieBean({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.vodPic,
    this.picInfo,
    required this.playUrl,
    this.qualities,
    this.mp4Url = '',
    this.duration = 0,
    required this.author,
    this.description = '',
    this.category = '',
    this.area = '',
    this.year = '',
    this.isVip = false,
    this.gold = 0,
    this.stats = const VideoStats(),
    this.createTime = 0,
  });

  factory MovieBean.fromJson(Map<String, dynamic> json) {
    final vod   = json['vod']       as Map<String, dynamic>? ?? {};
    final auth  = json['author']    as Map<String, dynamic>? ?? {};
    final stats = json['statistics']as Map<String, dynamic>? ?? {};
    final rawPicInfo = vod['vodPicInfo'] as dynamic;

    // 解析 vodPicInfo
    VodPicInfo? picInfo;
    try {
      if (rawPicInfo is String && rawPicInfo.isNotEmpty) {
        picInfo = VodPicInfo.fromJson(jsonDecode(rawPicInfo));
      } else if (rawPicInfo is Map) {
        picInfo = VodPicInfo.fromJson(rawPicInfo);
      }
    } catch (_) {}

    // 多分辨率列表
    List<VideoQuality>? qualities;
    try {
      final raw = vod['vodFullPlayUrl'] as List<dynamic>?;
      if (raw != null) {
        qualities = raw
            .map((e) => VideoQuality.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return MovieBean(
      id:         (vod['vodId']     ?? json['id']      ?? 0).toString(),
      title:      (vod['vodName']   ?? '').toString(),
      coverUrl:   (vod['vodPic']    ?? '').toString(),
      vodPic:     (vod['vodPic']    ?? '').toString(),
      picInfo:    picInfo,
      playUrl:    (vod['vodPlayUrl'] ?? '').toString(),
      qualities:  qualities,
      mp4Url:     (vod['mp4']       ?? '').toString(),
      duration:   (vod['vodDuration'] ?? 0),
      author:     AuthorInfo.fromJson(auth),
      description:(vod['vodIntro']  ?? '').toString(),
      category:   (vod['vodClass']  ?? '').toString(),
      area:       (vod['vodArea']   ?? '').toString(),
      year:       (vod['vodYear']   ?? '').toString(),
      isVip:      (vod['isVip']     ?? false) == 1,
      gold:       (vod['gold']      ?? 0),
      stats:      VideoStats.fromJson(stats),
      createTime: (vod['createTime'] ?? 0),
    );
  }

  MovieBean copyWith({
    String? id,
    String? title,
    String? coverUrl,
    String? vodPic,
    VodPicInfo? picInfo,
    String? playUrl,
    List<VideoQuality>? qualities,
    String? mp4Url,
    int? duration,
    AuthorInfo? author,
    String? description,
    String? category,
    String? area,
    String? year,
    bool? isVip,
    int? gold,
    VideoStats? stats,
    int? createTime,
  }) =>
      MovieBean(
        id:       id       ?? this.id,
        title:    title    ?? this.title,
        coverUrl: coverUrl ?? this.coverUrl,
        vodPic:   vodPic   ?? this.vodPic,
        picInfo:  picInfo  ?? this.picInfo,
        playUrl:  playUrl  ?? this.playUrl,
        qualities: qualities ?? this.qualities,
        mp4Url:   mp4Url   ?? this.mp4Url,
        duration: duration ?? this.duration,
        author:   author   ?? this.author,
        description: description ?? this.description,
        category: category ?? this.category,
        area:     area     ?? this.area,
        year:     year     ?? this.year,
        isVip:    isVip    ?? this.isVip,
        gold:     gold     ?? this.gold,
        stats:    stats    ?? this.stats,
        createTime: createTime ?? this.createTime,
      );
}