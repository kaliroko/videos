/// 评论面板 —— 和发布卡片共用同一套弹簧物理
///
/// 评论全量在 provider 内存里，所以打开面板不用再发请求，
/// 发完一条列表和卡片上的计数会一起更新。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../models/diary_comment.dart';
import '../models/diary_post.dart' show kAnonymousName;
import '../providers/diary_provider.dart';
import '../repository/diary_repository.dart';
import '../theme/diary_palette.dart';
import '../theme/springs.dart';
import '../utils/diary_time.dart';
import '../widgets/ink_seal.dart';
import '../widgets/spring_sheet.dart';

/// 弹出某条动态的评论面板
Future<void> showDiaryCommentsSheet(
  BuildContext context, {
  required String postId,
  required String initialName,
  required bool initialAnonymous,
}) async {
  await showSpringSheet(
    context,
    maxHeightFactor: 0.86,
    // ★ 标题用圆体：毛笔体是裁剪过的子集，没有「评」「论」这两个字，
    //   用毛笔体会回退成系统字体。圆体是完整字库，随便写。
    header: SpringSheetHeader(
      title: '评论',
      sealText: '评',
      titleStyle: TextStyle(
        fontFamily: DiaryPalette.round,
        fontSize: 21,
        height: 1.35,
        color: DiaryPalette.onPaper,
        letterSpacing: 0.5,
      ),
    ),
    scroller: _CommentList(postId: postId),
    footer: _CommentComposer(
      postId: postId,
      initialName: initialName,
      initialAnonymous: initialAnonymous,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════
// 列表
// ══════════════════════════════════════════════════════════════════════

class _CommentList extends StatelessWidget {
  const _CommentList({required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiaryProvider>();
    final comments = provider.commentsFor(postId);

    if (comments.isEmpty) return const _EmptyComments();

    // reverse: true → 最新的贴在最下面，新评论进来自动跟随
    final shown = comments.reversed.toList(growable: false);

    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      itemCount: shown.length,
      separatorBuilder: (context, index) => const SizedBox(height: 15),
      itemBuilder: (context, index) {
        final comment = shown[index];
        return _CommentRow(
          comment: comment,
          mine: comment.isMine(provider.deviceId),
        );
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.mine});

  final DiaryComment comment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkSeal(
          text: comment.initial,
          size: 30,
          filled: comment.anonymous,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      comment.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: DiaryPalette.round,
                        fontSize: 13.5,
                        height: 1.2,
                        color: comment.anonymous
                            ? DiaryPalette.onPaperSoft
                            : DiaryPalette.onPaper,
                      ),
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: DiaryPalette.vermilionWash,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '我',
                        style: TextStyle(
                          fontFamily: DiaryPalette.round,
                          fontSize: 10,
                          height: 1.3,
                          color: DiaryPalette.vermilionDeep,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // ★ 时间和卡片一样单独占一行：完整日期（含年月日）挺长的，
              //   和昵称挤在同一行会把名字压没
              const SizedBox(height: 2),
              Text(
                diaryTimeLabel(comment.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DiaryPalette.timeOnPaper,
              ),
              const SizedBox(height: 4),
              Text(
                comment.content,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.7,
                  color: DiaryPalette.onPaper,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyComments extends StatelessWidget {
  const _EmptyComments();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 46),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkSeal(text: '评', size: 36, filled: true),
          SizedBox(height: 14),
          Text(
            '还没有人说话',
            style: TextStyle(
              fontFamily: DiaryPalette.round,
              fontSize: 14,
              height: 1.4,
              color: DiaryPalette.onPaper,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '你来说第一句',
            style: TextStyle(
              fontFamily: DiaryPalette.brush,
              fontSize: 16,
              height: 1.4,
              color: DiaryPalette.onPaperFaint,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 输入栏
// ══════════════════════════════════════════════════════════════════════

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    required this.postId,
    required this.initialName,
    required this.initialAnonymous,
  });

  final String postId;
  final String initialName;
  final bool initialAnonymous;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final has = _ctrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<DiaryProvider>();
    final ok = await provider.addComment(
      postId: widget.postId,
      authorName: widget.initialName,
      anonymous: widget.initialAnonymous,
      content: text,
    );

    if (!mounted) return;
    if (ok) {
      _ctrl.clear();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '没发出去，再试一次',
            style: TextStyle(
              fontFamily: DiaryPalette.round,
              fontSize: 13.5,
              color: DiaryPalette.onInk,
            ),
          ),
          backgroundColor: DiaryPalette.inkSoft,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  String get _myInitial {
    if (widget.initialAnonymous) return '匿';
    final n = widget.initialName.trim();
    if (n.isEmpty) return '匿';
    return String.fromCharCode(n.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final sending = context.watch<DiaryProvider>().sendingComment;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              widget.initialAnonymous
                  ? '匿名评论'
                  : '以「${widget.initialName.trim().isEmpty ? kAnonymousName : widget.initialName.trim()}」的身份评论',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                fontSize: 11.5,
                height: 1.3,
                color: DiaryPalette.onPaperFaint,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkSeal(text: _myInitial, size: 34, filled: widget.initialAnonymous),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: kDiaryCommentMaxLength,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: DiaryPalette.onPaper,
                  ),
                  cursorColor: DiaryPalette.vermilion,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: '说点什么…',
                    hintStyle: TextStyle(
                      fontSize: 14.5,
                      color: DiaryPalette.onPaperFaint,
                    ),
                    filled: true,
                    fillColor: DiaryPalette.paperDim,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: _border(Colors.transparent),
                    enabledBorder: _border(Colors.transparent),
                    focusedBorder: _border(DiaryPalette.vermilion),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              _SpringSendButton(
                enabled: _hasText && !sending,
                busy: sending,
                onTap: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: 1.4),
      );
}

/// 按下缩小、松手弹回来（会稍微过冲一下）的发送键
class _SpringSendButton extends StatefulWidget {
  const _SpringSendButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_SpringSendButton> createState() => _SpringSendButtonState();
}

class _SpringSendButtonState extends State<_SpringSendButton>
    with SingleTickerProviderStateMixin {
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 420, damping: 16);

  late final AnimationController _ctrl =
      AnimationController.unbounded(vsync: this, value: 1);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _release() {
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, 1, 0));
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;

    return GestureDetector(
      onTapDown: active
          ? (_) => _ctrl.animateWith(
                // ★ 原来是 animateTo(90ms, easeOut)：按下补间、松开弹簧，
                //   同一个手势两种手感，是断的。
                SpringSimulation(Springs.settle, _ctrl.value, 0.88, 0),
              )
          : null,
      onTapUp: active
          ? (_) {
              _release();
              widget.onTap();
            }
          : null,
      onTapCancel: active ? _release : null,
      child: ScaleTransition(
        scale: _ctrl,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? DiaryPalette.vermilion
                : DiaryPalette.paperEdge,
            shape: BoxShape.circle,
          ),
          child: widget.busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DiaryPalette.onVermilion,
                  ),
                )
              : Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: DiaryPalette.onVermilion,
                ),
        ),
      ),
    );
  }
}
