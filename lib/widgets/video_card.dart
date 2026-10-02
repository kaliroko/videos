/// 竖屏视频卡片 — 对称双列网格布局（9:14 比例）
/// 适配新 API（无封面、无作者信息）
library;

import 'package:flutter/material.dart';
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
                // ── 封面占位区（新 API 无封面图）──────────────────────────
                Expanded(
                  flex: 7,
                  child: Container(
                    color: AppTheme.surfaceColor,
                    child: Center(
                      child: Icon(Icons.movie, color: AppTheme.textTertiary.withValues(alpha: 0.4), size: 32),
                    ),
                  ),
                ),
                // ── 信息区（标题）─────────────────────────────────────────
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
                    child: Text(
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
