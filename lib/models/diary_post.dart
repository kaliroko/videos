/// 碎碎念 · 日记动态模型
///
/// 设计要点：
///   • 无需注册 —— 身份就是设备号，昵称只存在本机 / 云端一行文本里
///   • 昵称可自定义，也可以勾选匿名；匿名时对外一律显示「匿名」
///   • 图片既可能是本机绝对路径（本机模式），也可能是云端 URL
library;

/// 匿名时对外显示的名字
const String kAnonymousName = '匿名';

/// 心情标签 —— 固定几款，避免自由输入带来的脏数据
///
/// 存库时直接存 [label] 文本，可读性好、跨端也不用维护枚举映射。
enum DiaryMood {
  none(''),
  joy('小确幸'),
  emo('有点emo'),
  miss('想你了'),
  tired('累累的'),
  silly('犯傻中'),
  hungry('忽然想吃');

  const DiaryMood(this.label);

  /// 展示文案，[none] 为空串代表没选
  final String label;

  bool get isEmpty => this == DiaryMood.none;

  /// 反查：认不出来的一律当作没选
  static DiaryMood fromLabel(String? value) {
    if (value == null || value.isEmpty) return DiaryMood.none;
    for (final m in DiaryMood.values) {
      if (m.label == value) return m;
    }
    return DiaryMood.none;
  }
}

/// 一条动态
class DiaryPost {
  const DiaryPost({
    required this.id,
    required this.deviceId,
    required this.authorName,
    required this.anonymous,
    required this.content,
    required this.createdAt,
    this.images = const <String>[],
    this.mood = DiaryMood.none,
  });

  /// 本机模式下是时间戳字符串，云端模式是数据库主键
  final String id;

  /// 作者设备号 —— 判断「这条是不是我写的」
  final String deviceId;

  /// 用户自定义昵称，可为空
  final String authorName;

  final bool anonymous;

  final String content;

  /// 本机绝对路径 或 云端 URL，混存
  final List<String> images;

  final DiaryMood mood;

  /// 统一用本地时间展示
  final DateTime createdAt;

  // ── 展示辅助 ────────────────────────────────────────────────────────

  /// 对外展示的名字
  String get displayName {
    if (anonymous) return kAnonymousName;
    final n = authorName.trim();
    return n.isEmpty ? kAnonymousName : n;
  }

  /// 名字首字 —— 用来画印章头像
  String get initial {
    final n = displayName;
    if (n.isEmpty) return '念';
    return String.fromCharCode(n.runes.first);
  }

  bool get hasImages => images.isNotEmpty;

  bool isMine(String? myDeviceId) =>
      myDeviceId != null &&
      myDeviceId.isNotEmpty &&
      deviceId == myDeviceId;

  // ── 序列化 ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'device_id': deviceId,
        'author_name': authorName,
        'anonymous': anonymous,
        'content': content,
        'images': images,
        'mood': mood.label,
        'created_at': createdAt.toIso8601String(),
      };

  /// 同时兼容本机 JSON 与 Supabase 行数据
  factory DiaryPost.fromJson(Map<String, dynamic> m) {
    final rawImages = m['images'];
    return DiaryPost(
      id: (m['id'] ?? '').toString(),
      deviceId: (m['device_id'] ?? '').toString(),
      authorName: (m['author_name'] ?? '').toString(),
      anonymous: m['anonymous'] == true,
      content: (m['content'] ?? '').toString(),
      images: rawImages is List
          ? rawImages.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      mood: DiaryMood.fromLabel(m['mood']?.toString()),
      createdAt: _parseTime(m['created_at']),
    );
  }

  Map<String, dynamic> toInsertMap() => <String, dynamic>{
        'device_id': deviceId,
        'author_name': authorName,
        'anonymous': anonymous,
        'content': content,
        'images': images,
        'mood': mood.label,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static DateTime _parseTime(Object? raw) {
    if (raw == null) return DateTime.now();
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return DateTime.now();
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }
}

/// 发布草稿 —— 发布前只有这些信息，id / 时间由仓库层决定
class DiaryDraft {
  const DiaryDraft({
    required this.authorName,
    required this.anonymous,
    required this.content,
    this.images = const <String>[],
    this.mood = DiaryMood.none,
  });

  final String authorName;
  final bool anonymous;
  final String content;

  /// 本机待入库的图片路径
  final List<String> images;

  final DiaryMood mood;
}
