/// 手写笔迹动画
///
/// 原理：先把整段文字按**最终宽度**排好版并缓存每个字的包围盒，
/// 动画时只用一个「已写到第几个字」的进度去裁剪画布 ——
/// 因此换行位置在整个书写过程中完全稳定，不会像逐字拼接那样跳动。
///
/// 笔尖会跟着进度走，最后一个字按小数进度从左往右揭开，看起来就是真的在写。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextSelection;

/// 逐字书写的文字。
///
/// [lines] 给多行时会依次循环书写；[loop] 为 false 时只写第一行然后留在原地。
class HandwritingText extends StatefulWidget {
  const HandwritingText({
    super.key,
    required this.lines,
    required this.style,
    this.loop = false,
    this.charDuration = const Duration(milliseconds: 118),
    this.holdDuration = const Duration(milliseconds: 1750),
    this.fadeDuration = const Duration(milliseconds: 430),
    this.gapDuration = const Duration(milliseconds: 240),
    this.startDelay = Duration.zero,
    this.penColor,
    this.showPenTip = true,
    this.textAlign = TextAlign.left,
  });

  final List<String> lines;
  final TextStyle style;
  final bool loop;

  /// 写一个字用多久
  final Duration charDuration;

  /// 写完停留多久
  final Duration holdDuration;

  /// 出现 / 消失各自用多久
  final Duration fadeDuration;

  /// 消失后隔多久写下一句
  final Duration gapDuration;

  final Duration startDelay;

  /// 笔尖颜色，默认跟随文字色
  final Color? penColor;

  final bool showPenTip;

  final TextAlign textAlign;

  @override
  State<HandwritingText> createState() => _HandwritingTextState();
}

class _HandwritingTextState extends State<HandwritingText>
    with TickerProviderStateMixin {
  late final AnimationController _ink;
  late final AnimationController _fade;

  _InkLayout? _layout;
  String _laidOutText = '';
  double _laidOutWidth = -1;
  TextStyle? _laidOutStyle;

  int _lineIndex = 0;

  /// 每次重开循环就 +1，旧的循环发现编号变了会自己退出
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _ink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = AnimationController(vsync: this, value: 0);
    unawaited(_runLoop());
  }

  @override
  void didUpdateWidget(covariant HandwritingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = !_sameLines(oldWidget.lines, widget.lines) ||
        oldWidget.loop != widget.loop ||
        oldWidget.charDuration != widget.charDuration;
    if (changed) {
      _lineIndex = 0;
      _layout = null;
      _laidOutText = '';
      unawaited(_runLoop());
    }
  }

  @override
  void dispose() {
    _run++;
    _ink.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// 手写比较，不依赖 foundation 的 listEquals 是否被 material 转出
  static bool _sameLines(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _runLoop() async {
    final myRun = ++_run;

    // 先让首帧落地，避免在 initState 里同步 setState
    await Future<void>.delayed(Duration.zero);
    if (!mounted || myRun != _run) return;

    final lines = widget.lines;
    if (lines.isEmpty) return;

    if (widget.startDelay > Duration.zero) {
      await Future<void>.delayed(widget.startDelay);
      if (!mounted || myRun != _run) return;
    }

    var index = 0;
    while (mounted && myRun == _run) {
      final text = lines[index % lines.length];

      if (mounted) setState(() => _lineIndex = index % lines.length);
      _ink.value = 0;
      _fade.value = 0;

      await _fade.animateTo(1, duration: widget.fadeDuration);
      if (!mounted || myRun != _run) return;

      if (text.isNotEmpty) {
        final ms = widget.charDuration.inMilliseconds * text.length;
        await _ink.animateTo(
          1,
          duration: Duration(milliseconds: ms.clamp(180, 24000).toInt()),
          curve: Curves.linear,
        );
        if (!mounted || myRun != _run) return;
      }

      if (!widget.loop) break;

      await Future<void>.delayed(widget.holdDuration);
      if (!mounted || myRun != _run) return;

      await _fade.animateTo(0, duration: widget.fadeDuration);
      if (!mounted || myRun != _run) return;

      await Future<void>.delayed(widget.gapDuration);
      if (!mounted || myRun != _run) return;

      index++;
    }
  }

  void _ensureLayout({
    required String text,
    required double width,
    required TextStyle style,
  }) {
    if (_layout != null &&
        _laidOutText == text &&
        _laidOutWidth == width &&
        _laidOutStyle == style) {
      return;
    }
    _layout = _InkLayout.build(
      text: text,
      style: style,
      maxWidth: width,
      textAlign: widget.textAlign,
    );
    _laidOutText = text;
    _laidOutWidth = width;
    _laidOutStyle = style;
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final text = lines.isEmpty ? '' : lines[_lineIndex % lines.length];

    return AnimatedBuilder(
      animation: _fade,
      builder: (context, child) {
        final v = _fade.value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 5),
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite && constraints.maxWidth > 1
              ? constraints.maxWidth
              : 240.0;

          _ensureLayout(text: text, width: width, style: widget.style);
          final layout = _layout;
          final double height = layout?.size.height ?? 0;

          return SizedBox(
            width: width,
            height: height,
            child: layout == null || layout.length == 0
                ? const SizedBox.shrink()
                : CustomPaint(
                    size: Size(width, height),
                    painter: _InkPainter(
                      layout: layout,
                      progress: _ink,
                      penColor: widget.penColor ??
                          widget.style.color ??
                          Colors.white,
                      showPenTip: widget.showPenTip,
                    ),
                  ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 排版缓存
// ══════════════════════════════════════════════════════════════════════

class _InkLayout {
  _InkLayout._(this.painter, this.boxes);

  final TextPainter painter;

  /// 每个字在画布上的包围盒，下标即「第几个字」
  final List<Rect> boxes;

  int get length => boxes.length;

  Size get size => Size(painter.width, painter.height);

  static _InkLayout build({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextAlign textAlign,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout(maxWidth: maxWidth);

    final starts = _graphemeStarts(text);
    final boxes = <Rect>[];

    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      var rect = Rect.zero;
      try {
        final tb = painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        if (tb.isNotEmpty) {
          rect = Rect.fromLTRB(
            tb.first.left,
            tb.first.top,
            tb.last.right,
            tb.last.bottom,
          );
        }
      } catch (_) {
        // 极少数排版边界情况，跳过这个字就好
      }
      boxes.add(rect);
    }

    return _InkLayout._(painter, boxes);
  }

  /// 按「字」切分（把代理对当成一个字，避免把 emoji 劈成两半）
  static List<int> _graphemeStarts(String text) {
    final starts = <int>[];
    var i = 0;
    while (i < text.length) {
      starts.add(i);
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
        final low = text.codeUnitAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          i += 2;
          continue;
        }
      }
      i += 1;
    }
    return starts;
  }
}

// ══════════════════════════════════════════════════════════════════════
// 绘制
// ══════════════════════════════════════════════════════════════════════

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.layout,
    required this.progress,
    required this.penColor,
    required this.showPenTip,
  }) : super(repaint: progress);

  final _InkLayout layout;
  final Animation<double> progress;
  final Color penColor;
  final bool showPenTip;

  @override
  void paint(Canvas canvas, Size size) {
    final total = layout.length;
    if (total == 0) return;

    final revealed = progress.value.clamp(0.0, 1.0).toDouble() * total;
    final whole = revealed.floor().clamp(0, total).toInt();
    final frac = (revealed - whole).clamp(0.0, 1.0).toDouble();

    if (whole > 0 || frac > 0.002) {
      final clip = Path();

      for (var i = 0; i < whole; i++) {
        final r = layout.boxes[i];
        if (r.isEmpty) continue;
        // 稍微外扩一点，避免相邻字的抗锯齿被切出缝
        clip.addRect(r.inflate(1.2));
      }

      if (whole < total && frac > 0.002) {
        final r = layout.boxes[whole];
        if (!r.isEmpty) {
          clip.addRect(
            Rect.fromLTRB(r.left, r.top, r.left + r.width * frac, r.bottom),
          );
        }
      }

      canvas.save();
      canvas.clipPath(clip);
      layout.painter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    if (showPenTip && whole < total) {
      final r = layout.boxes[whole];
      if (!r.isEmpty) {
        _paintPen(canvas, Offset(r.left + r.width * frac, r.center.dy));
      }
    }
  }

  void _paintPen(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      9,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            penColor.withValues(alpha: 0.42),
            penColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: 9)),
    );
    canvas.drawCircle(
      at,
      1.9,
      Paint()..color = penColor.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.penColor != penColor ||
      oldDelegate.showPenTip != showPenTip;
}
