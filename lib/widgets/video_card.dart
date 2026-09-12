/// 竖屏视频卡片 — 对称双列网格布局（9:14 比例，性能优化版）
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/theme/app_theme.dart';

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
        // 移除 splashColor — 节省每次 tap 的离屏渲染
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: video.fullCached
                    ? const Color(0xFF34C759).withValues(alpha: 0.35)
                    : video.headCached
                        ? const Color(0xFF00AEEC).withValues(alpha: 0.35)
                        : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 封面图 ─────────────────────────────────────────
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (ctx, url, err) => Container(
                          color: AppTheme.surfaceColor,
                          child: const Icon(Icons.movie, color: AppTheme.textTertiary, size: 24),
                        ),
                      ),
                      // 播放按钮
                      Center(
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0x80000000), // 直接写 hex alpha，避免 withOpacity 分配新对象
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x40FFFFFF), width: 1),
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                        ),
                      ),
                      // 缓存徽章
                      if (video.fullCached)
                        _badge(const Color(0xFF34C759), '⚡')
                      else if (video.headCached)
                        _badge(const Color(0xFF00AEEC), '🚀'),
                      // 底部渐变遮罩（纯颜色叠加，无动画）
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 28,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x8A000000)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── 信息区 ─────────────────────────────────────────
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          video.title,
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: const Color(0x3300AEEC),
                              child: Text(
                                (video.author.isNotEmpty && video.author.length >= 1)
                                    ? video.author[0]
                                    : '?',
                                style: const TextStyle(color: AppTheme.accentColor, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                video.author,
                                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 10),
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

  Widget _badge(Color color, String icon) {
    return Positioned(
      top: 6, left: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(icon, style: const TextStyle(fontSize: 8)),
      ),
    );
  }
}