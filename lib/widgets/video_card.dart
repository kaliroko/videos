/// 竖屏视频卡片 — 类似 TikTok / Shorts 的竖屏布局
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilibili_glass/models/video_model.dart';
import 'package:bilibili_glass/theme/app_theme.dart';
import 'package:bilibili_glass/utils/format_utils.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: AppTheme.accentColor.withOpacity(0.15),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: video.fullCached
                      ? AppTheme.successColor.withOpacity(0.3)
                      : video.headCached
                          ? AppTheme.primaryColor.withOpacity(0.3)
                          : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 竖屏封面 9:16 ──────────────────────────────
                  _buildCover(context),
                  // ── 信息区 ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题（最多 2 行）
                        Text(
                          video.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // 作者 + 时间行
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: AppTheme.accentColor.withOpacity(0.2),
                              child: Text(
                                (video.author.isNotEmpty && video.author.length >= 1)
                                    ? video.author[0]
                                    : '?',
                                style: const TextStyle(
                                  color: AppTheme.accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                video.author,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (video.created.isNotEmpty)
                              Text(
                                _formatDate(video.created),
                                style: const TextStyle(
                                  color: AppTheme.textTertiary,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                        // 缓存状态条
                        if (video.fullCached || video.headCached)
                          _buildCachedBar(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 9 / 16,
          child: CachedNetworkImage(
            imageUrl: video.coverUrl,
            fit: BoxFit.cover,
            placeholder: (ctx, url) => Container(
              color: AppTheme.surfaceColor,
              child: const Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (ctx, url, err) => Container(
              color: AppTheme.surfaceColor,
              child: const Icon(Icons.movie, color: AppTheme.textTertiary, size: 32),
            ),
          ),
        ),
        // 播放按钮（居中半透明圆）
        Center(
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
          ),
        ),
        // 缓存徽章
        if (video.fullCached)
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.successColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('⚡', style: TextStyle(fontSize: 10)),
            ),
          )
        else if (video.headCached)
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('🚀', style: TextStyle(fontSize: 10)),
            ),
          ),
        // 底部渐变遮罩
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCachedBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      height: 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        gradient: LinearGradient(
          colors: video.fullCached
              ? [AppTheme.successColor, AppTheme.successColor.withOpacity(0.3)]
              : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.3)],
        ),
      ),
    );
  }

  String _formatDate(String created) {
    if (created.length < 10) return '';
    final dateStr = created.split(' ')[0];
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    final month = parts[1];
    final day = parts[2].replaceAll(RegExp(r'\D'), '');
    return '$month/$day';
  }
}
