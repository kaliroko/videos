/// 一张「纸片」动态卡片
///
/// 米色纸 + 朱砂印章 + 微小的倾角 —— 像贴在桌面上的便签，
/// 而不是那种一眼看上去就很套路的暗色圆角卡片。
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/diary_post.dart';
import '../theme/diary_palette.dart';
import 'diary_image_viewer.dart';
import 'ink_seal.dart';

class DiaryCard extends StatefulWidget {
  const DiaryCard({
    super.key,
    required this.post,
    this.mine = false,
    this.tilt = 0,
    this.onDelete,
  });

  final DiaryPost post;

  /// 是不是自己写的 —— 决定能不能删
  final bool mine;

  /// 弧度，给每张卡片一点随机感
  final double tilt;

  final Future<void> Function()? onDelete;

  @override
  State<DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<DiaryCard> {
  bool _expanded = false;

  static const int _kCollapsedLines = 7;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final content = post.content.trim();
    final collapsible = content.length > 96;

    return Transform.rotate(
      angle: widget.tilt,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DiaryPalette.paper,
          borderRadius: BorderRadius.circular(18),
          boxShadow: DiaryPalette.paperShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onLongPress: widget.mine ? _confirmDelete : null,
            splashColor: DiaryPalette.vermilionWash,
            highlightColor: DiaryPalette.vermilionWash,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(post),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 13),
                    Text(
                      content,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.85,
                        letterSpacing: 0.2,
                        color: DiaryPalette.onPaper,
                      ),
                      maxLines: _expanded ? null : _kCollapsedLines,
                      overflow: _expanded
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                    ),
                    if (collapsible) _buildExpandToggle(),
                  ],
                  if (post.hasImages) ...[
                    const SizedBox(height: 13),
                    _buildImages(post.images),
                  ],
                  if (widget.mine) ...[
                    const SizedBox(height: 12),
                    Text(
                      '长按可以删掉',
                      style: TextStyle(
                        fontFamily: DiaryPalette.round,
                        fontSize: 11,
                        height: 1.2,
                        color: DiaryPalette.vermilionDeep
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 顶部：印章 + 昵称 + 时间 + 心情 ────────────────────────────────

  Widget _buildHeader(DiaryPost post) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkSeal(
          text: post.initial,
          size: 38,
          filled: post.anonymous,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                post.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DiaryPalette.round,
                  fontSize: 15.5,
                  height: 1.25,
                  color: post.anonymous
                      ? DiaryPalette.onPaperSoft
                      : DiaryPalette.onPaper,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _timeLabel(post.createdAt),
                style: DiaryPalette.brushOnPaper,
              ),
            ],
          ),
        ),
        if (!post.mood.isEmpty) ...[
          const SizedBox(width: 8),
          _buildMoodChip(post.mood),
        ],
      ],
    );
  }

  Widget _buildMoodChip(DiaryMood mood) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: DiaryPalette.vermilionWash,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: DiaryPalette.vermilion.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        mood.label,
        style: const TextStyle(
          fontFamily: DiaryPalette.round,
          fontSize: 11.5,
          height: 1.15,
          color: DiaryPalette.vermilionDeep,
        ),
      ),
    );
  }

  // ── 正文折叠 ──────────────────────────────────────────────────────

  Widget _buildExpandToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: DiaryPalette.vermilionDeep,
        ),
        child: Text(
          _expanded ? '收起' : '展开',
          style: const TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  // ── 图片 ──────────────────────────────────────────────────────────

  Widget _buildImages(List<String> images) {
    final n = images.length;

    if (n == 1) {
      return GestureDetector(
        onTap: () => showDiaryImageViewer(context, images, initialIndex: 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: _buildImage(images.first),
          ),
        ),
      );
    }

    final columns = (n == 2 || n == 4) ? 2 : 3;
    return GridView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: n,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => showDiaryImageViewer(context, images, initialIndex: i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: _buildImage(images[i]),
        ),
      ),
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(color: DiaryPalette.paperDim),
        errorWidget: (_, __, ___) => _brokenImage(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _brokenImage(),
    );
  }

  Widget _brokenImage() => const ColoredBox(
        color: DiaryPalette.paperDim,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 20,
            color: DiaryPalette.onPaperFaint,
          ),
        ),
      );

  // ── 删除 ──────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryPalette.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          '删掉这一条？',
          style: TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 17,
            color: DiaryPalette.onPaper,
          ),
        ),
        content: const Text(
          '删了就找不回来了',
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: DiaryPalette.onPaperSoft,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: DiaryPalette.onPaperSoft,
            ),
            child: const Text('算了', style: TextStyle(fontFamily: DiaryPalette.round)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: DiaryPalette.vermilionDeep,
            ),
            child: const Text('删掉', style: TextStyle(fontFamily: DiaryPalette.round)),
          ),
        ],
      ),
    );

    if (ok == true) await onDelete();
  }

  // ── 时间文案 ──────────────────────────────────────────────────────

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);

    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天 ${_two(t.hour)}:${_two(t.minute)}';
    if (diff.inDays < 8) return '${diff.inDays} 天前';
    return '${t.year}.${_two(t.month)}.${_two(t.day)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
