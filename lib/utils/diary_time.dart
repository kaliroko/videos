/// 日记模块的时间文案
///
/// 卡片和评论行共用一份逻辑，避免两边格式不一致。
///
/// ★ 这里用的都是毛笔体子集里已经包含的字（刚刚/分钟前/小时前/昨天/天前），
///   不要随手加「周前」「个月前」之类 —— 那些字不在子集里，
///   会悄悄回退成系统字体，一列时间看起来就花了。
library;

/// 格式化动态/评论时间
String diaryTimeLabel(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);

  if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天 ${_two(t.hour)}:${_two(t.minute)}';
  if (diff.inDays < 8) return '${diff.inDays} 天前';
  return '${t.year}.${_two(t.month)}.${_two(t.day)}';
}

String _two(int v) => v.toString().padLeft(2, '0');
