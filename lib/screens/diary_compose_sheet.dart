/// 发布卡片 —— 弹簧弹出的米色纸片
///
/// 交互：
///   • 入场用欠阻尼弹簧，会轻轻过冲一下再落定
///   • 顶部把手跟手拖拽，向上拖带阻尼（拖不太动），向下拖 1:1
///   • 松手按速度判断：甩得够快或者拖得够远就顺势飞走，否则弹回原位
///   • 拖拽时卡片带一点 3D 透视倾斜，松手回正
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/diary_post.dart';
import '../providers/diary_provider.dart';
import '../repository/diary_repository.dart';
import '../theme/diary_palette.dart';
import '../widgets/ink_seal.dart';

/// 弹出发布卡片
Future<void> showDiaryComposeSheet(
  BuildContext context, {
  required String initialName,
  required bool initialAnonymous,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '写点什么',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, animation, secondaryAnimation) => DiaryComposeSheet(
      initialName: initialName,
      initialAnonymous: initialAnonymous,
    ),
  );
}

class DiaryComposeSheet extends StatefulWidget {
  const DiaryComposeSheet({
    super.key,
    this.initialName = '',
    this.initialAnonymous = false,
  });

  final String initialName;
  final bool initialAnonymous;

  @override
  State<DiaryComposeSheet> createState() => _DiaryComposeSheetState();
}

class _DiaryComposeSheetState extends State<DiaryComposeSheet>
    with TickerProviderStateMixin {
  /// 入场用：欠阻尼，落到 1 之前会过冲一点
  static const SpringDescription _springIn =
      SpringDescription(mass: 1, stiffness: 400, damping: 26);

  /// 出场用：接近临界阻尼，不回头
  static const SpringDescription _springOut =
      SpringDescription(mass: 1, stiffness: 420, damping: 41);

  /// 入场位移距离
  static const double _kRise = 430;

  /// 拖到这个距离就顺势关掉
  static const double _kDismissDistance = 140;

  /// 甩到这个速度就顺势关掉
  static const double _kDismissVelocity = 620;

  late final AnimationController _enter;
  late final AnimationController _drag;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();

  final List<String> _images = <String>[];

  DiaryMood _mood = DiaryMood.none;
  bool _anonymous = false;
  bool _closing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController.unbounded(vsync: this, value: 0);
    _drag = AnimationController.unbounded(vsync: this, value: 0);

    _anonymous = widget.initialAnonymous;
    _nameCtrl.text = widget.initialName;

    _enter.animateWith(SpringSimulation(_springIn, 0, 1, 0));
  }

  @override
  void dispose() {
    _enter.dispose();
    _drag.dispose();
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ── 手势 ──────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    final delta = details.delta.dy;
    final next = _drag.value + delta;
    // 往上拖给 0.25 倍阻尼，手感上「拉不太动」
    _drag.value = next < 0 ? next * 0.25 : next;
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.velocity.pixelsPerSecond.dy;

    if (velocity > _kDismissVelocity || _drag.value > _kDismissDistance) {
      _dismiss();
      return;
    }
    _drag.animateWith(
      SpringSimulation(_springIn, _drag.value, 0, velocity),
    );
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    setState(() => _closing = true);

    _drag.animateWith(SpringSimulation(_springOut, _drag.value, 900, 0));
    await _enter.animateWith(
      SpringSimulation(_springOut, _enter.value, -0.4, 0),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ── 发布 ──────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_busy) return;

    final body = _bodyCtrl.text.trim();
    if (body.isEmpty && _images.isEmpty) {
      _toast('写两个字，或者配张图');
      return;
    }

    setState(() => _busy = true);
    final provider = context.read<DiaryProvider>();

    final ok = await provider.publish(
      DiaryDraft(
        authorName: _nameCtrl.text.trim(),
        anonymous: _anonymous,
        content: body,
        images: List<String>.from(_images),
        mood: _mood,
      ),
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      _toast('没发出去，再试一次');
    }
  }

  Future<void> _pickImages() async {
    final room = kDiaryMaxImages - _images.length;
    if (room <= 0) {
      _toast('最多九张啦');
      return;
    }

    try {
      final picked = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked.isEmpty || !mounted) return;

      setState(() {
        for (final file in picked.take(room)) {
          _images.add(file.path);
        }
      });
    } catch (e) {
      debugPrint('[Diary] 选图失败: $e');
      if (mounted) _toast('打不开相册');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
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

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // ★ 要扣掉键盘高度，否则弹出输入法后卡片会顶出屏幕
    final available = media.size.height - media.viewInsets.bottom;
    final maxHeight = (available > 240 ? available : media.size.height) * 0.88;

    // 两层 AnimatedBuilder 分别监听弹簧与拖拽，避免依赖 Listenable.merge
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) => AnimatedBuilder(
        animation: _drag,
        builder: (context, innerChild) {
          final raw = _enter.value;
          final visible = raw.clamp(0.0, 1.0).toDouble();
          final dy = (1 - raw) * _kRise + _drag.value;
          final tilt = (_drag.value / _kRise).clamp(0.0, 1.0).toDouble() * 0.12;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closing ? null : _dismiss,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.66 * visible),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateX(tilt),
                      child: Opacity(
                        opacity: visible,
                        child: Transform.scale(
                          scale: 0.94 + 0.06 * visible,
                          alignment: Alignment.bottomCenter,
                          child: innerChild,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: child,
      ),
      child: _buildCard(context, maxHeight),
    );
  }

  Widget _buildCard(BuildContext context, double maxHeight) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: DiaryPalette.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTitleRow(),
                    const SizedBox(height: 16),
                    _buildIdentityRow(),
                    const SizedBox(height: 14),
                    _buildBodyField(),
                    const SizedBox(height: 16),
                    _buildMoodRow(),
                    const SizedBox(height: 16),
                    _buildImageGrid(),
                  ],
                ),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 42,
            height: 4.5,
            decoration: BoxDecoration(
              color: DiaryPalette.paperEdge,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const InkSeal(text: '记', size: 32, filled: true),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            '写点什么',
            style: TextStyle(
              fontFamily: DiaryPalette.brush,
              fontSize: 25,
              height: 1.2,
              color: DiaryPalette.onPaper,
            ),
          ),
        ),
        IconButton(
          onPressed: _closing ? null : _dismiss,
          icon: const Icon(Icons.close_rounded, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: DiaryPalette.paperDim,
            foregroundColor: DiaryPalette.onPaperSoft,
            minimumSize: const Size(34, 34),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                enabled: !_anonymous,
                maxLength: 12,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  fontFamily: DiaryPalette.round,
                  fontSize: 15,
                  color: _anonymous
                      ? DiaryPalette.onPaperFaint
                      : DiaryPalette.onPaper,
                ),
                cursorColor: DiaryPalette.vermilion,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: '留个名字',
                  hintStyle: const TextStyle(
                    fontFamily: DiaryPalette.round,
                    fontSize: 15,
                    color: DiaryPalette.onPaperFaint,
                  ),
                  filled: true,
                  fillColor: DiaryPalette.paperDim,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: _fieldBorder(Colors.transparent),
                  enabledBorder: _fieldBorder(Colors.transparent),
                  disabledBorder: _fieldBorder(Colors.transparent),
                  focusedBorder: _fieldBorder(DiaryPalette.vermilion),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _anonymous,
                  onChanged: _closing
                      ? null
                      : (v) => setState(() => _anonymous = v),
                  thumbColor: const WidgetStatePropertyAll(
                    DiaryPalette.onVermilion,
                  ),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    return states.contains(WidgetState.selected)
                        ? DiaryPalette.vermilion
                        : DiaryPalette.paperEdge;
                  }),
                ),
                Text(
                  '匿名',
                  style: TextStyle(
                    fontFamily: DiaryPalette.round,
                    fontSize: 11.5,
                    height: 1.1,
                    color: _anonymous
                        ? DiaryPalette.vermilionDeep
                        : DiaryPalette.onPaperFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _anonymous ? '谁也不知道是谁写的' : '不填名字也会显示「匿名」',
          style: const TextStyle(
            fontFamily: DiaryPalette.round,
            fontSize: 11.5,
            height: 1.3,
            color: DiaryPalette.onPaperFaint,
          ),
        ),
      ],
    );
  }

  Widget _buildBodyField() {
    return TextField(
      controller: _bodyCtrl,
      minLines: 4,
      maxLines: 10,
      maxLength: kDiaryMaxLength,
      textInputAction: TextInputAction.newline,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontSize: 15.5,
        height: 1.85,
        color: DiaryPalette.onPaper,
      ),
      cursorColor: DiaryPalette.vermilion,
      decoration: InputDecoration(
        hintText: '今天想说点什么…',
        hintStyle: const TextStyle(
          fontSize: 15,
          height: 1.85,
          color: DiaryPalette.onPaperFaint,
        ),
        filled: true,
        fillColor: DiaryPalette.paperDim,
        counterStyle: const TextStyle(
          fontFamily: DiaryPalette.round,
          fontSize: 11,
          color: DiaryPalette.onPaperFaint,
        ),
        contentPadding: const EdgeInsets.all(15),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(DiaryPalette.vermilion),
      ),
    );
  }

  Widget _buildMoodRow() {
    final moods = DiaryMood.values.where((m) => !m.isEmpty).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: moods.map((mood) {
        final selected = _mood == mood;
        return GestureDetector(
          onTap: () => setState(() {
            _mood = selected ? DiaryMood.none : mood;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? DiaryPalette.vermilion
                  : DiaryPalette.paperDim,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              mood.label,
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                fontSize: 12.5,
                height: 1.2,
                color: selected
                    ? DiaryPalette.onVermilion
                    : DiaryPalette.onPaperSoft,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildImageGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '配张图',
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                fontSize: 13,
                color: DiaryPalette.onPaperSoft,
              ),
            ),
            const Spacer(),
            Text(
              '${_images.length}/$kDiaryMaxImages',
              style: const TextStyle(
                fontFamily: DiaryPalette.round,
                fontSize: 11.5,
                color: DiaryPalette.onPaperFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 7,
            mainAxisSpacing: 7,
          ),
          itemCount: _images.length + (_images.length < kDiaryMaxImages ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _images.length) return _buildAddTile();
            return _buildThumb(index);
          },
        ),
      ],
    );
  }

  Widget _buildAddTile() {
    return GestureDetector(
      onTap: _pickImages,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DiaryPalette.paperDim,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: DiaryPalette.paperEdge,
            style: BorderStyle.solid,
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 22,
            color: DiaryPalette.onPaperSoft,
          ),
        ),
      ),
    );
  }

  Widget _buildThumb(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(_images[index]),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: DiaryPalette.paperDim,
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => setState(() => _images.removeAt(index)),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final provider = context.watch<DiaryProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _publish,
              style: FilledButton.styleFrom(
                backgroundColor: DiaryPalette.vermilion,
                foregroundColor: DiaryPalette.onVermilion,
                disabledBackgroundColor: DiaryPalette.vermilionDeep,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DiaryPalette.onVermilion,
                      ),
                    )
                  : const Text(
                      '写好了',
                      style: TextStyle(
                        fontFamily: DiaryPalette.round,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            provider.isCloud ? '发出去大家都看得到' : '先存在这台手机上',
            style: const TextStyle(
              fontFamily: DiaryPalette.round,
              fontSize: 11.5,
              color: DiaryPalette.onPaperFaint,
            ),
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: 1.4),
      );
}
