/// 竖屏视频卡片 — 对称双列网格布局（9:14 比例）
/// 适配 VideoItem（旧API AES-CBC / 新API kuleu.com 双数据源）
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:suisuinian/models/video_model.dart';
import 'package:suisuinian/theme/app_theme.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
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
                        // 作者
                        if (video.author.isNotEmpty)
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor:
                                    AppTheme.accentColor.withValues(alpha: 0.2),
                                child: Text(
                                  video.author[0],
                                  style: const TextStyle(
                                      color: AppTheme.accentColor,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  video.author,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
}