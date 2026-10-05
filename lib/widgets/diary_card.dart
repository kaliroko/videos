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
import '../utils/diary_time.dart';
import 'diary_image_viewer.dart';
import 'ink_seal.dart';

class DiaryCard extends StatefulWidget {
  const DiaryCard({
    super.key,
    required this.post,
    this.mine = false,
    this.tilt = 0,
    this.commentCount = 0,
    this.onComment,
    this.onDelete,
  });

  final DiaryPost post;

  /// 是不是自己写的 —— 决定能不能删
  final bool mine;

  /// 弧度，给每张卡片一点随机感
  final double tilt;

  /// 这条动态有几条评论
  final int commentCount;

  /// 点评论按钮
  final VoidCallback? onComment;

  final Future<void> Function()? onDelete;

  @override
  State<DiaryCard> createState() => _DiaryCardState();
}

class _DiaryCardState extends State<DiaryCard> {
  bool _expanded = false;

  /// 正文超过这么多字就折叠
  static const int _kCollapsedChars = 50;

  /// 折叠后只露 2 行（按当前字号和卡片宽度，大约就是 50 字）
  static const int _kCollapsedLines = 2;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final content = post.content.trim();
    final collapsible = content.length > _kCollapsedChars;

    return Transform.rotate(
      angle: widget.tilt,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DiaryPalette.paper,
          borderRadius: BorderRadius.circular(16),
          boxShadow: DiaryPalette.paperShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onLongPress: widget.mine ? _confirmDelete : null,
            splashColor: DiaryPalette.vermilionWash,
            highlightColor: DiaryPalette.vermilionWash,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(post),
                  if (content.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      content,
                      // ★ 只有「真的超了 50 字」才裁：短动态若也按 2 行裁，
                      //   会被切掉却没有「展开」可点。
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.68,
                        letterSpacing: 0.15,
                        color: DiaryPalette.onPaper,
                      ),
                      maxLines: _expanded || !collapsible ? null : _kCollapsedLines,
                      overflow: _expanded || !collapsible
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                    ),
                    if (collapsible) _buildExpandToggle(),
                  ],
                  if (post.hasImages) ...[
                    const SizedBox(height: 9),
                    _buildImages(post.images),
                  ],
                  const SizedBox(height: 8),
                  _buildFooter(post),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 底部：评论入口 + 自己的动态提示 ──────────────────────────────

  Widget _buildFooter(DiaryPost post) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: DiaryPalette.rule, height: 1, thickness: 1),
        const SizedBox(height: 4),
        Row(
          children: [
            _CommentButton(
              count: widget.commentCount,
              onTap: widget.onComment,
            ),
            const Spacer(),
            if (widget.mine)
              const Text(
                '长按可以删掉',
                style: TextStyle(
                  fontFamily: DiaryPalette.round,
                  fontSize: 10.5,
                  height: 1.2,
                  color: DiaryPalette.vermilionDeep,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── 顶部：印章 + 昵称 + 时间 + 心情 ────────────────────────────────

  Widget _buildHeader(DiaryPost post) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkSeal(
          text: post.initial,
          size: 32,
          filled: post.anonymous,
        ),
        const SizedBox(width: 9),
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
                  fontSize: 14,
                  height: 1.25,
                  color: post.anonymous
                      ? DiaryPalette.onPaperSoft
                      : DiaryPalette.onPaper,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                diaryTimeLabel(post.createdAt),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          fontSize: 11,
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
          minimumSize: const Size(0, 27),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: DiaryPalette.vermilionDeep,
        ),
        child: Text(
          _expanded ? '收起' : '展开',
          style: const TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 12,
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
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 3 / 2,
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
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: n,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => showDiaryImageViewer(context, images, initialIndex: i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
            color: DiaryPalette.onPaperSoft,
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
}

/// 评论入口 —— 有评论就把数字带上
class _CommentButton extends StatelessWidget {
  const _CommentButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.chat_bubble_outline, size: 15),
      label: Text(has ? '评论 $count' : '评论'),
      style: TextButton.styleFrom(
        foregroundColor:
            has ? DiaryPalette.vermilionDeep : DiaryPalette.onPaperSoft,
        minimumSize: const Size(0, 29),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontFamily: DiaryPalette.round,
          fontSize: 12,
        ),
      ),
    );
  }
}
