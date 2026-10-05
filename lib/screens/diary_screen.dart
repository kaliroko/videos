/// 碎碎念 —— 日记分享动态
///
/// 页头是一段会自己写出来的手写体：先写「碎碎念」，
/// 再一句一句地写心里话，写完停一会儿、淡掉，再写下一句。
/// 下面是上下分布的纸片卡片流。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../models/diary_post.dart';
import '../providers/diary_provider.dart';
import '../theme/diary_palette.dart';
import '../widgets/diary_card.dart';
import '../widgets/handwriting_text.dart';
import '../widgets/ink_seal.dart';
import 'diary_compose_sheet.dart';

/// 页头循环书写的那几句话
const List<String> _kWhispers = <String>[
  '今天也没发生什么大事',
  '但有点想跟你说说话',
  '小事也值得记一下',
  '忽然想吃楼下那家面',
  '写下来就不算白过了',
  '要记得好好吃饭',
];

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openCompose() async {
    final provider = context.read<DiaryProvider>();
    final before = provider.posts.length;

    await showDiaryComposeSheet(
      context,
      initialName: provider.nickname,
      initialAnonymous: provider.anonymous,
    );

    if (!mounted) return;
    if (provider.posts.length > before && _scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 让每张纸片歪得不太一样 —— 用 id 定死，重建也不会跳
  double _tiltFor(DiaryPost post) {
    final bucket = post.id.hashCode.abs() % 3;
    return (bucket - 1) * 0.006;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiaryProvider>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.05),
          radius: 1.15,
          colors: <Color>[Color(0xFF1F1A14), DiaryPalette.ink],
        ),
      ),
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: provider.refresh,
            color: DiaryPalette.vermilion,
            backgroundColor: DiaryPalette.paper,
            child: _buildList(provider, bottomInset),
          ),
          Positioned(
            right: 18,
            bottom: 104 + bottomInset,
            child: _SpringTap(
              onTap: _openCompose,
              child: const _ComposeButton(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(DiaryProvider provider, double bottomInset) {
    if (provider.loading && provider.posts.isEmpty) {
      return ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 180 + bottomInset),
        children: [
          _buildHeader(provider),
          const SizedBox(height: 60),
          Center(
            child: HandwritingText(
              lines: const <String>['翻一翻…'],
              style: DiaryPalette.brushLine,
              loop: true,
              charDuration: const Duration(milliseconds: 150),
              penColor: DiaryPalette.vermilion,
            ),
          ),
        ],
      );
    }

    if (provider.posts.isEmpty) {
      return ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 180 + bottomInset),
        children: [
          _buildHeader(provider),
          const SizedBox(height: 40),
          const Center(child: _EmptyPaper()),
        ],
      );
    }

    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 190 + bottomInset),
      itemCount: provider.posts.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(provider);

        final post = provider.posts[index - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DiaryCard(
            post: post,
            mine: post.isMine(provider.deviceId),
            tilt: _tiltFor(post),
            onDelete: () async {
              await provider.remove(post);
            },
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 页头
  // ══════════════════════════════════════════════════════════════════

  Widget _buildHeader(DiaryProvider provider) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 26, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: HandwritingText(
                  lines: const <String>['碎碎念'],
                  style: DiaryPalette.brushHero,
                  charDuration: const Duration(milliseconds: 300),
                  startDelay: const Duration(milliseconds: 240),
                  penColor: DiaryPalette.vermilion,
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _DelayedFade(
                  delay: Duration(milliseconds: 1000),
                  child: InkSeal(text: '念', size: 42),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _DelayedFade(
            delay: Duration(milliseconds: 1150),
            child: _BrushStroke(),
          ),
          const SizedBox(height: 20),
          const _DelayedFade(
            delay: Duration(milliseconds: 1250),
            child: HandwritingText(
              lines: _kWhispers,
              style: DiaryPalette.brushLine,
              loop: true,
              charDuration: const Duration(milliseconds: 135),
              holdDuration: const Duration(milliseconds: 2100),
              fadeDuration: const Duration(milliseconds: 460),
              gapDuration: const Duration(milliseconds: 300),
              startDelay: Duration(milliseconds: 150),
              penColor: DiaryPalette.vermilion,
            ),
          ),
          const SizedBox(height: 26),
          _DelayedFade(
            delay: const Duration(milliseconds: 1400),
            child: Row(
              children: [
                const Expanded(
                  child: Divider(
                    color: DiaryPalette.onInkFaint,
                    height: 1,
                    thickness: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  provider.posts.isEmpty
                      ? '还空着'
                      : '${provider.posts.length} 条',
                  style: DiaryPalette.roundOnInk,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 「写」按钮
// ══════════════════════════════════════════════════════════════════════

class _ComposeButton extends StatelessWidget {
  const _ComposeButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DiaryPalette.vermilion,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DiaryPalette.vermilion.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Text(
        '写',
        style: TextStyle(
          fontFamily: DiaryPalette.brush,
          fontSize: 27,
          height: 1.0,
          color: DiaryPalette.paper,
        ),
      ),
    );
  }
}

/// 按下缩小、松手用弹簧弹回来（会稍微过冲一下）
class _SpringTap extends StatefulWidget {
  const _SpringTap({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<_SpringTap>
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

  void _press() {
    _ctrl.animateTo(
      0.9,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    _ctrl.animateWith(
      SpringSimulation(_spring, _ctrl.value, 1, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press(),
      onTapUp: (_) {
        _release();
        widget.onTap();
      },
      onTapCancel: _release,
      child: ScaleTransition(scale: _ctrl, child: widget.child),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 空状态
// ══════════════════════════════════════════════════════════════════════

class _EmptyPaper extends StatelessWidget {
  const _EmptyPaper();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.012,
      child: Container(
        width: 236,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        decoration: BoxDecoration(
          color: DiaryPalette.paper,
          borderRadius: BorderRadius.circular(18),
          boxShadow: DiaryPalette.paperShadow(lift: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const InkSeal(text: '空', size: 40, filled: true),
            const SizedBox(height: 16),
            const Text(
              '还没有人写过什么',
              style: TextStyle(
                fontFamily: DiaryPalette.round,
                fontSize: 15,
                height: 1.4,
                color: DiaryPalette.onPaper,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '第一句留给你',
              style: TextStyle(
                fontFamily: DiaryPalette.brush,
                fontSize: 17,
                height: 1.4,
                color: DiaryPalette.onPaperFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 小零件
// ══════════════════════════════════════════════════════════════════════

/// 延迟淡入 + 轻微上移
class _DelayedFade extends StatefulWidget {
  const _DelayedFade({
    required this.child,
    this.delay = Duration.zero,
    this.slide = 8,
  });

  final Widget child;
  final Duration delay;
  final double slide;

  @override
  State<_DelayedFade> createState() => _DelayedFadeState();
}

class _DelayedFadeState extends State<_DelayedFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  late final Animation<double> _curved =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curved.value) * widget.slide),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 朱砂一笔 —— 手绘感的短线，会自己画出来
class _BrushStroke extends StatefulWidget {
  const _BrushStroke({this.width = 74, this.height = 9});

  final double width;
  final double height;

  @override
  State<_BrushStroke> createState() => _BrushStrokeState();
}

class _BrushStrokeState extends State<_BrushStroke>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _BrushStrokePainter(progress: _ctrl),
      ),
    );
  }
}

class _BrushStrokePainter extends CustomPainter {
  _BrushStrokePainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value.clamp(0.0, 1.0).toDouble();
    if (t <= 0) return;

    final endX = size.width * t;
    final path = Path()
      ..moveTo(0, size.height * 0.62)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.05,
        size.width * 0.66,
        size.height * 0.98,
        endX,
        size.height * 0.34,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = DiaryPalette.vermilion
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BrushStrokePainter oldDelegate) => false;
}
