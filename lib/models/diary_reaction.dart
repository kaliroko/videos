/// 碎碎念 · 动态表情反应（类似点赞）
///
/// 固定四个表情，不做自定义 —— 选择太多反而没人点。
/// 一条动态上，同一个人对同一种表情只能算一次；再点一次就是取消。
library;

/// 四个反应表情
const List<String> kDiaryReactions = <String>['❤️', '😂', '👍', '😢'];

/// 单个表情的说明，给无障碍朗读用
const Map<String, String> kDiaryReactionLabels = <String, String>{
  '❤️': '喜欢',
  '😂': '好笑',
  '👍': '赞同',
  '😢': '心疼',
};

/// 一条反应记录
///
/// 没有单独的主键：`(postId, deviceId, emoji)` 本身就是唯一键，
/// 靠数据库的唯一约束防重复。
class DiaryReaction {
  const DiaryReaction({
    required this.postId,
    required this.deviceId,
    required this.emoji,
  });

  final String postId;
  final String deviceId;
  final String emoji;

  /// 本地存储用的唯一键
  String get key => '$postId|$deviceId|$emoji';

  bool isMine(String? myDeviceId) =>
      myDeviceId != null && myDeviceId.isNotEmpty && deviceId == myDeviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'post_id': postId,
        'device_id': deviceId,
        'emoji': emoji,
      };

  Map<String, dynamic> toInsertMap() => toJson();

  factory DiaryReaction.fromJson(Map<String, dynamic> m) => DiaryReaction(
        postId: (m['post_id'] ?? '').toString(),
        deviceId: (m['device_id'] ?? '').toString(),
        emoji: (m['emoji'] ?? '').toString(),
      );

  /// 只有固定的四个表情才认，脏数据直接丢掉
  static bool isValidEmoji(String? e) =>
      e != null && kDiaryReactions.contains(e);
}
