/// 竖屏视频卡片 — 对称双列网格布局（9:14 比例）
/// 支持 MovieBean（新API）和 VideoItem（旧API）两种数据源
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/repository/api_gateway.dart';

class VideoCard extends StatelessWidget {
  final MovieBean video;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        splashColor: AppTheme.accentColor.withValues(alpha: 0.15),
        highlightColor: AppTheme.accentColor.withValues(alpha: 0.08),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: video.isVip
                    ? AppTheme.warningColor.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 封面图 ────────────────────────────────────────────────
                Expanded(
                  flex: 7,
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: video.coverUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        httpHeaders: ApiService.imageHeaders(),
                        placeholder: (ctx, url) => Container(
                          color: AppTheme.surfaceColor,
                          child: const Center(
                            child: SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (ctx, url, err) => Container(
                          color: AppTheme.surfaceColor,
                          child: const Icon(
                            Icons.movie,
                            color: AppTheme.textTertiary,
                            size: 24,
                          ),
                        ),
                      ),
                      // VIP 徽章
                      if (video.isVip)
                        Positioned(
                          top: 6, right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'VIP',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      // 时长标签
                      if (video.duration > 0)
                        Positioned(
                          bottom: 6, right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              _formatDuration(video.duration),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ),
                      // 中央播放按钮
                      Center(
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1),
                          ),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      // 底部渐变遮罩
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.55)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── 信息区 ────────────────────────────────────────────────
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 标题
                        Text(
                          video.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // 作者 + 统计
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor:
                                  AppTheme.accentColor.withValues(alpha: 0.2),
                              child: Text(
                                video.author.nickName.isNotEmpty
                                    ? video.author.nickName[0]
                                    : '?',
                                style: const TextStyle(
                                    color: AppTheme.accentColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                video.author.nickName,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // 播放量
                        Row(
                          children: [
                            const Icon(Icons.play_arrow,
                                size: 10, color: AppTheme.textTertiary),
                            const SizedBox(width: 2),
                            Text(
                              _formatCount(video.stats.readNumber),
                              style: const TextStyle(
                                  color: AppTheme.textTertiary, fontSize: 9),
                            ),
                            const Spacer(),
                            if (video.category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  video.category,
                                  style: const TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontSize: 8),
                                ),
                              ),
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

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _formatCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}