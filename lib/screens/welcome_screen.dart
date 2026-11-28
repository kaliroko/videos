/// 欢迎页 —— 第一次打开 Her Haven 的四页介绍
///
/// ★ 视觉完全换成网页那套：同一张 1.png 背景、同一组玫瑰/薰衣草色、
///   同一款衬线字体；每页配一张网页同源的动漫图（可点「换一张」）。
/// ★ 翻页仍然是真弹簧：没有任何 Curve/duration 推页面，
///   只有一个 AnimationController 被 SpringSimulation 推着走，
///   甩动的速度会交给弹簧当初始速度。
/// ★ 最后一页要确认「已满 18 岁」才能进入 —— 网页锁屏的年龄门槛保留，
///   只是不再额外做一层启动锁屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/haven.dart';
import '../widgets/haven_widgets.dart';

class _Slide {
  const _Slide({
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final String eyebrow;
  final String title;
  final String body;
}

const List<_Slide> _kSlides = <_Slide>[
  _Slide(
    eyebrow: 'Her Haven',
    title: '今晚，\n只属于你',
    body: '这里没有凝视，也没有评判。\n'
        '只有女孩和女孩之间，心照不宣的那点事。',
  ),
  _Slide(
    eyebrow: 'Private',
    title: '想被怎样对待',
    body: '情绪、身体、节奏、欲望 ——\n'
        '写下来，只留在这台设备里。',
  ),
  _Slide(
    eyebrow: 'Together',
    title: '和她一起',
    body: '匹配一个懂你的女孩，一起共振、一起呼吸，\n'
        '或者只是听她说一句「我在」。',
  ),
  _Slide(
    eyebrow: 'Come In',
    title: '门没锁',
    body: '成年女孩的乌托邦。\n'
        '随时可以进来，也随时可以停。',
  ),
];

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  /// 翻完最后一页、确认年龄之后调用
  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  /// 连续页号：0.0 = 第 1 页，1.4 = 正从第 2 页滑向第 3 页。
  /// 用 unbounded：弹簧会过冲，带上界会被削平，回弹就没了。
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: 0);

  /// 整页第一次露面的那一下
  late final AnimationController _entrance =
      AnimationController.unbounded(vsync: this, value: 0);

  double _viewport = 1;

  /// 每页动漫图的初始种子
  late final int _baseSeed = DateTime.now().millisecondsSinceEpoch;

  static const SpringDescription _springPage =
      SpringDescription(mass: 1, stiffness: 380, damping: 28);

  static const SpringDescription _springEnter =
      SpringDescription(mass: 1, stiffness: 420, damping: 20);

  static const double _flickVelocity = 1.5;
  static const double _rubberBand = 0.35;

  double get _last => (_kSlides.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _entrance.animateWith(SpringSimulation(_springEnter, 0, 1, 0));
  }

  @override
  void dispose() {
    _pos.dispose();
    _entrance.dispose();
    super.dispose();
  }

  // ── 翻页 ──────────────────────────────────────────────────────────

  void _springTo(double target, {double velocity = 0}) {
    _pos.animateWith(
      SpringSimulation(
        _springPage,
        _pos.value,
        target.clamp(0, _last),
        velocity,
      ),
    );
  }

  void _onDragStart(DragStartDetails details) => _pos.stop();

  void _onDragUpdate(DragUpdateDetails details) {
    if (_viewport <= 0) return;
    final next = _pos.value - details.delta.dx / _viewport;

    if (next < 0) {
      _pos.value = next * _rubberBand;
    } else if (next > _last) {
      _pos.value = _last + (next - _last) * _rubberBand;
    } else {
      _pos.value = next;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_viewport <= 0) return;

    final v = -details.velocity.pixelsPerSecond.dx / _viewport;
    final current = _pos.value.clamp(0.0, _last);

    double target = current.roundToDouble();
    if (v > _flickVelocity) {
      target = current.floorToDouble() + 1;
    } else if (v < -_flickVelocity) {
      target = current.ceilToDouble() - 1;
    }

    _springTo(target, velocity: v);
  }

  void _next() {
    if (_pos.value.round() < _last) {
      _springTo(_pos.value.roundToDouble() + 1);
      return;
    }
    widget.onFinished();
  }

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return HavenBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewport = constraints.maxWidth;
            return AnimatedBuilder(
              animation: Listenable.merge(<Listenable?>[_pos, _entrance]),
              builder: (context, _) => _buildBody(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    final v = _pos.value;

    return Column(
      children: <Widget>[
        Expanded(
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Transform.translate(
                offset: Offset(-v * _viewport, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < _kSlides.length; i++)
                      SizedBox(
                        width: _viewport,
                        child: _buildPage(i, v),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildDots(v),
        const SizedBox(height: 18),
        _buildButton(v),
        const SizedBox(height: 26),
      ],
    );
  }

  double _lag(double delta, double lag) {
    final raw = (1 - delta * 1.7 - lag) / (1 - lag);
    return raw.clamp(0.0, 1.0);
  }

  Widget _buildPage(int i, double v) {
    final slide = _kSlides[i];
    final delta = (v - i).abs().clamp(0.0, 1.0);
    final pageFade = (1 - delta * 1.7).clamp(0.0, 1.0);

    final enter = _entrance.value;
    final enterFade = enter.clamp(0.0, 1.0);

    return Opacity(
      opacity: pageFade * enterFade,
      child: Transform.translate(
        offset: Offset(0, 24 * delta),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                const SizedBox(height: 12),
                Transform.scale(
                  scale: 0.86 + 0.14 * enter,
                  child: MoeImagePanel(
                    initialSeed: _baseSeed + i * 31,
                    width: 170,
                    height: 232,
                    kenBurns: true,
                  ),
                ),
                const SizedBox(height: 30),
                _fadeText(
                  value: _lag(delta, 0.0) * enterFade,
                  child: Column(
                    children: <Widget>[
                      Text(
                        slide.eyebrow.toUpperCase(),
                        style: HavenColors.brandSub,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slide.title,
                        textAlign: TextAlign.center,
                        style: HavenColors.heroTitle.copyWith(
                          fontSize: 32,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _fadeText(
                  value: _lag(delta, 0.3) * enterFade,
                  child: Text(
                    slide.body,
                    textAlign: TextAlign.center,
                    style: HavenColors.body.copyWith(height: 1.9),
                  ),
                ),
                const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fadeText({required double value, required Widget child}) {
    return Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - value)),
        child: child,
      ),
    );
  }

  Widget _buildDots(double v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _kSlides.length; i++) _dot(i, v),
      ],
    );
  }

  Widget _dot(int i, double v) {
    final t = 1 - (v - i).abs().clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3.5),
      width: 7 + 13 * t,
      height: 7,
      decoration: BoxDecoration(
        color: Color.lerp(
          HavenColors.inkGhost,
          HavenColors.rose,
          t,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildButton(double v) {
    final atEnd = v.round() >= _last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: HavenButton(
        label: atEnd ? '进来' : '再近一点',
        expand: true,
        height: 52,
        onPressed: _next,
      ),
    );
  }
}
