/// 格式化工具函数
library;

/// 格式化播放量：1024000 → 102.4万
String formatCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  } else if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  } else {
    return count.toString();
  }
}

/// 格式化时长：90秒 → 1:30，3600秒 → 1:00:00
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 格式化发布时间：2小时前、3天前
String formatRelativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}周前';
  return '${(diff.inDays / 30).floor()}个月前';
}
