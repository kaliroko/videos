/// 视频卡片 — B站经典上下结构 + MD3 风格涟漪
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/utils/format_utils.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
  const VideoCard({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Material(
        // MD3 弹簧涟漪（elevation: 0 保证不抬升，ripple 带动画）
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // 封面图
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: video.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => Container(
                          color: AppTheme.cardColor,
                          child: const Center(
                            child: SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (ctx, url, err) => Container(
                          color: AppTheme.cardColor,
                          child: const Icon(Icons.video_library,
                              color: AppTheme.textTertiary, size: 32),
                        ),
                      ),
                      // 底部渐变遮罩
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                            ),
                          ),
                        ),
                      ),
                      // 时长标签
                      Positioned(
                        bottom: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatDuration(video.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 内容区（叠加在封面底部）
                Positioned(
                  top: 0, left: 0, right: 0, bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          flex: 3,
                          child: Text(
                            video.title,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: NetworkImage(video.authorAvatar),
                                    backgroundColor: AppTheme.surfaceColor,
                                    onBackgroundImageError: (_, __) {},
                                    child: const Icon(Icons.person, size: 14, color: AppTheme.textTertiary),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      video.author,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_arrow, size: 12, color: AppTheme.textTertiary),
                            const SizedBox(width: 2),
                            Text(formatCount(video.playCount),
                                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}