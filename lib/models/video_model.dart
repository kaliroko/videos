/// 视频模型
library;

class VideoItem {
  final String id;
  final String title;
  final String author;
  final String authorAvatar;
  final String coverUrl;
  final Duration duration;
  final int playCount;
  final int danmakuCount;
  final DateTime pubDate;

  const VideoItem({
    required this.id,
    required this.title,
    required this.author,
    required this.authorAvatar,
    required this.coverUrl,
    required this.duration,
    required this.playCount,
    required this.danmakuCount,
    required this.pubDate,
  });
}
