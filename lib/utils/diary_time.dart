/// 日记模块的时间文案
///
/// 卡片和评论行共用一份逻辑，避免两边格式不一致。
///
/// ★ 关于字体：日期里的「年」「月」和分隔用的「·」**不在毛笔子集里**
///   （毛笔体是裁剪过的，见 assets/fonts/README.md）。
///   所以时间这一行必须用圆体（完整字库），用毛笔体会回退成系统字体、
///   一行时间里两种字形。
///
/// ★ 卡片用完整版（相对时间 + 年月日），评论行用紧凑版
///   （评论那一行本来就窄，再塞完整日期会把昵称挤掉）。
library;

/// 格式化成 `2026年10月5日`
String diaryDate(DateTime t) => '${t.year}年${t.month}月${t.day}日';

/// 相对时间部分；超过 8 天返回空串（那时日期本身就够说明了）
String _relative(Duration diff) {
  if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 8) return '${diff.inDays} 天前';
  return '';
}

String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');

/// 卡片上的时间：`3 小时前 · 2026年10月5日`
///
/// 老于 8 天的动态不再显示相对时间，直接给 `2026年9月20日 14:30`。
String diaryTimeLabel(DateTime t) {
  final rel = _relative(DateTime.now().difference(t));
  if (rel.isEmpty) return '${diaryDate(t)} ${_hm(t)}';
  return '$rel · ${diaryDate(t)}';
}

/// 评论行的时间：那一行窄，所以只在不属于「刚刚/今天/昨天/近一周」时才补日期
String diaryTimeLabelCompact(DateTime t) {
  final rel = _relative(DateTime.now().difference(t));
  return rel.isEmpty ? diaryDate(t) : rel;
}
