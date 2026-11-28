/// Her Haven 本地记录模型 —— 私密日记 / 自慰时刻
///
/// ★ 这两个模块的数据只存在本机 SharedPreferences 里（JSON），
///   不上传、不联网 —— 和网页「所有数据均加密保存在本机」的说法一致。
///   真正加密需要平台 Keychain + SQLCipher，这里保持诚实的「仅本机」表述。
library;

/// 私密日记的情绪选项（网页 .chips 的那一排）
const List<String> kHavenMoods = <String>[
  '平静',
  '开心',
  '满足',
  '想念',
  '低落',
  '焦虑',
  '疲惫',
];

/// 身体感受标签
const List<String> kHavenBodyTags = <String>[
  '温暖',
  '紧绷',
  '酥麻',
  '轻盈',
  '酸胀',
  '疲惫',
];

/// 自慰时刻的「当时状态」
const List<String> kHavenMomentStates = <String>[
  '独处',
  '两个人',
  '温柔',
  '强烈',
  '探索',
  '慢慢来',
];

/// 自慰时刻的「方式」——详细记录用的多选项
const List<String> kHavenMethods = <String>[
  '手指',
  '玩具',
  '水流',
  '枕头',
  '摩擦',
  '其他',
];

/// 强度 0~5 的文案（0 表示没记）
const List<String> kHavenPleasureLabels = <String>[
  '没记录',
  '很轻',
  '轻',
  '刚好',
  '明显',
  '强烈',
  '到顶',
];

/// 注意力程度 0~5 的文案（网页 #intensityLabel）
const List<String> kHavenIntensityLabels = <String>[
  '几乎没注意',
  '稍微留意',
  '有些在意',
  '明显感受到',
  '几乎占据全部',
  '完全沉浸',
];

/// 一条私密日记
class PrivateDiaryEntry {
  const PrivateDiaryEntry({
    required this.id,
    required this.date,
    required this.mood,
    required this.tags,
    required this.intensity,
    required this.note,
  });

  final String id;
  final DateTime date;

  /// 情绪（kHavenMoods 之一，可为空串）
  final String mood;

  /// 身体感受标签（kHavenBodyTags 子集）
  final List<String> tags;

  /// 0~5
  final int intensity;

  final String note;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': date.toIso8601String(),
        'mood': mood,
        'tags': tags,
        'intensity': intensity,
        'note': note,
      };

  factory PrivateDiaryEntry.fromJson(Map<String, dynamic> m) {
    final rawTags = m['tags'];
    return PrivateDiaryEntry(
      id: (m['id'] ?? '').toString(),
      date: DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now(),
      mood: (m['mood'] ?? '').toString(),
      tags: rawTags is List
          ? rawTags.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      intensity: _asInt(m['intensity']),
      note: (m['note'] ?? '').toString(),
    );
  }
}

/// 一条自慰时刻记录
class MomentEntry {
  const MomentEntry({
    required this.id,
    required this.at,
    required this.minutes,
    required this.state,
    required this.before,
    required this.during,
    required this.after,
    required this.pain,
    this.methods = const <String>[],
    this.pleasure = 0,
    this.orgasm = false,
    this.orgasmCount = 0,
  });

  final String id;
  final DateTime at;

  /// 持续时长（分钟，0~60）
  final int minutes;

  /// 当时状态（kHavenMomentStates 之一）
  final String state;

  final String before;
  final String during;
  final String after;

  /// 是否有疼痛或不适 —— 记录卡上会打一个「需要照顾自己」的标记
  final bool pain;

  // ── 详细记录（都可以不填）──────────────────────────────────────

  /// 方式（kHavenMethods 的子集）
  final List<String> methods;

  /// 强度 0~5
  final int pleasure;

  /// 有没有到
  final bool orgasm;

  /// 到了几次
  final int orgasmCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'at': at.toIso8601String(),
        'minutes': minutes,
        'state': state,
        'before': before,
        'during': during,
        'after': after,
        'pain': pain,
        'methods': methods,
        'pleasure': pleasure,
        'orgasm': orgasm,
        'orgasm_count': orgasmCount,
      };

  factory MomentEntry.fromJson(Map<String, dynamic> m) {
    final rawMethods = m['methods'];
    return MomentEntry(
      id: (m['id'] ?? '').toString(),
      at: DateTime.tryParse((m['at'] ?? '').toString()) ?? DateTime.now(),
      minutes: _asInt(m['minutes']),
      state: (m['state'] ?? '').toString(),
      before: (m['before'] ?? '').toString(),
      during: (m['during'] ?? '').toString(),
      after: (m['after'] ?? '').toString(),
      pain: m['pain'] == true,
      methods: rawMethods is List
          ? rawMethods.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      pleasure: _asInt(m['pleasure']),
      orgasm: m['orgasm'] == true,
      orgasmCount: _asInt(m['orgasm_count']),
    );
  }
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
