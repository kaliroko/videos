/// 欢迎页 —— 首次启动的几页介绍，翻完再进引导页填名字和头像
///
/// ★ 为什么要和引导页分开：
///   欢迎页只讲这里有什么，先看个大概；引导页是「必须填完才能进」的门禁。
///   两件事的性子不一样，混在一页里既挤又说不清。
///
/// ★ 深浅色跟随系统：这一页自己 new 了 MaterialApp，所以 OnboardingGate
///   那边给它的 builder 里也调了一次 DiaryPalette.syncWith ——
///   不然调色板会一直停在默认的暗色，系统开浅色模式也不变。
///
/// ★ 动画全程真弹簧，和 spring_sheet / 点赞按钮同一套语言：
///   没有任何 Curve、没有任何 duration —— 只有一个 AnimationController
///   被 SpringSimulation 推着走。
///
/// ★ 翻页是自己搭的，没用 PageView：
///   PageController.animateToPage() 只吃 duration + curve，是补间不是物理，
///   想要弹簧就得绕过它。所以这里用「连续页号」这个 double 当唯一状态，
///   拖拽直接改它、松手用弹簧收回，位移/淡入淡出/圆点全部由它推出来。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../models/diary_post.dart' show DiaryMood;
import '../theme/diary_palette.dart';
import '../widgets/ink_seal.dart';

/// 一页的文字
class _Slide {
  const _Slide({
    required this.title,
    required this.body,
  });

  /// 大字，手写体
  final String title;

  /// 小字，圆体
  final String body;
}

const List<_Slide> _kSlides = <_Slide>[
  _Slide(
    title: '你好呀',
    body: '这里没什么规矩。想写就写，想发就发。',
  ),
  _Slide(
    title: '碎碎念',
    body: '一句话、一张图，随手贴上去，攒成自己的一面墙。',
  ),
  _Slide(
    title: '挑个心情',
    body: '小确幸、有点 emo、想你了……挑不出来就空着。',
  ),
  _Slide(
    title: '还有两个',
    body: '想说话就去聊天室，想放空就上下滑。',
  ),
];

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  /// 翻完最后一页时调用
  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  /// ★ 唯一的动画状态：连续页号。0.0 = 第 1 页，1.4 = 正从第 2 页滑向第 3 页。
  ///
  /// 用 unbounded：弹簧会过冲，带上界会被削平，回弹就没了。
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: 0);

  /// 整页第一次露面的那一下。同样是弹簧，过冲体现在插画的缩放上。
  late final AnimationController _entrance =
      AnimationController.unbounded(vsync: this, value: 0);

  /// 视口宽度，把像素位移换算成「页」
  double _viewport = 1;

  // ── 弹簧参数（和 spring_sheet 一个路子，只是按各自的场景调阻尼）──────

  /// 翻页：稍微欠阻尼，落位时有一点回弹。
  /// 阻尼再小整页宽度就会晃得人晕，再大就变成纯滑动了。
  static const SpringDescription _springPage =
      SpringDescription(mass: 1, stiffness: 380, damping: 28);

  /// 整页露面：比翻页弹一点，插画那一下才有「落定」的手感
  static const SpringDescription _springEnter =
      SpringDescription(mass: 1, stiffness: 420, damping: 20);

  /// 甩多快就直接翻页（页/秒）
  static const double _flickVelocity = 1.5;

  /// 拖到两端时的橡皮筋系数：越拉越沉
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

  /// 用弹簧停在某一页
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

  void _onDragStart(DragStartDetails details) {
    // 手指一按就接管，别让上一段弹簧还在推
    _pos.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_viewport <= 0) return;
    // 手指往左 → delta.dx 为负 → 页号变大
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

    // 手指往左甩 → 正速度 → 页号变大
    final v = -details.velocity.pixelsPerSecond.dx / _viewport;
    final current = _pos.value.clamp(0.0, _last);

    double target = current.roundToDouble();
    // 甩得够快就再多翻一页，不用等它滑过一半
    if (v > _flickVelocity) {
      target = current.floorToDouble() + 1;
    } else if (v < -_flickVelocity) {
      target = current.ceilToDouble() - 1;
    }

    // 把甩的速度交给弹簧当初始速度 —— 这就是「物理真实」的来处
    _springTo(target, velocity: v);
  }

  void _next() {
    if (_pos.value.round() >= _last) {
      widget.onFinished();
      return;
    }
    _springTo(_pos.value.roundToDouble() + 1);
  }

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiaryPalette.ink,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.05),
            radius: 1.15,
            colors: <Color>[DiaryPalette.inkGlow, DiaryPalette.ink],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 只记下来给手势换算用，不触发重建
              _viewport = constraints.maxWidth;
              return AnimatedBuilder(
                animation: Listenable.merge(<Listenable?>[_pos, _entrance]),
                builder: (context, _) => _buildBody(),
              );
            },
          ),
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
                  // ★ stretch 不能省：Column 要用 mainAxisAlignment.center 居中，
                  //   高度必须是「紧」的。默认 center 会给松约束，Column 缩成
                  //   内容高，居中就失效了，内容会贴在顶上。
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
        const SizedBox(height: 22),
        _buildButton(v),
        const SizedBox(height: 30),
      ],
    );
  }

  /// 文字和整页的渐隐渐现都从 [delta] 推出来。
  ///
  /// [lag] 越大，亮得越晚、淡得越早 —— 标题给 0，正文给 0.3，
  /// 于是标题先浮出来、正文慢半拍跟上，像一句话被分两次说出口。
  ///
  /// 除以 (1 - lag) 是为了让 lag 大的那一项在正中央也能到 1.0，
  /// 不然正文永远差一口气、看着发灰。
  double _lag(double delta, double lag) {
    final raw = (1 - delta * 1.7 - lag) / (1 - lag);
    return raw.clamp(0.0, 1.0);
  }

  Widget _buildPage(int i, double v) {
    final slide = _kSlides[i];

    // 离屏幕中心多远：0 = 正在看，1 = 完全在隔壁
    final delta = (v - i).abs().clamp(0.0, 1.0);
    final pageFade = (1 - delta * 1.7).clamp(0.0, 1.0);

    // ★ 这里故意不夹紧：弹簧过冲时 enter 会略大于 1，
    //   插画就会「压过目标再弹回来」—— 那一下才是弹簧的手感。
    //   透明度不能这么干（Opacity 要求 0~1），所以下面单独夹。
    final enter = _entrance.value;
    final enterFade = enter.clamp(0.0, 1.0);

    return Opacity(
      opacity: pageFade * enterFade,
      child: Transform.translate(
        offset: Offset(0, 24 * delta),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Transform.scale(
                scale: 0.86 + 0.14 * enter,
                child: _artFor(i),
              ),
              const SizedBox(height: 40),
              _fadeText(
                value: _lag(delta, 0.0) * enterFade,
                child: Text(
                  slide.title,
                  textAlign: TextAlign.center,
                  style: DiaryPalette.brushHero.copyWith(fontSize: 42),
                ),
              ),
              const SizedBox(height: 16),
              _fadeText(
                value: _lag(delta, 0.3) * enterFade,
                child: Text(
                  slide.body,
                  textAlign: TextAlign.center,
                  style: DiaryPalette.heroNote.copyWith(
                    fontSize: 14.5,
                    height: 1.7,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 透明度到位移一起给：淡下去的时候同时轻轻往上收
  Widget _fadeText({required double value, required Widget child}) {
    return Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - value)),
        child: child,
      ),
    );
  }

  /// 每页的小插画。都用现成的纸片和印章拼，不引新素材。
  Widget _artFor(int i) {
    switch (i) {
      case 0:
        return const _PaperStack();
      case 1:
        return const _DiarySample();
      case 2:
        return const _MoodChips();
      default:
        return const _TwoTiles();
    }
  }

  /// 圆点指示器。
  ///
  /// ★ 每个点的长短也是 [_pos] 直接推出来的连续值 —— 拖动时点是跟着手指
  ///   一点点长的，不是等翻完才跳过去；而且同样被弹簧带着走。
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
          DiaryPalette.onInkFaint,
          DiaryPalette.vermilion,
          t,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildButton(double v) {
    final atEnd = v.round() >= _last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: _SpringButton(
          label: atEnd ? '开始' : '下一步',
          onPressed: _next,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 弹簧按压的按钮
// ══════════════════════════════════════════════════════════════════════

/// MD3 FilledButton + 弹簧按压反馈。
///
/// 手指按下缩一点、松开弹回来，和点赞按钮同一个手感 ——
/// 没有 Curve、没有 duration，全靠 SpringSimulation。
class _SpringButton extends StatefulWidget {
  const _SpringButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_SpringButton> createState() => _SpringButtonState();
}

class _SpringButtonState extends State<_SpringButton>
    with SingleTickerProviderStateMixin {
  /// 上界开到 2：弹簧的过冲要有地方去，撞到上界会被削平
  late final AnimationController _press = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: 0,
    upperBound: 2,
  );

  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 620, damping: 18);

  void _down(PointerDownEvent event) {
    _press.animateWith(SpringSimulation(_spring, _press.value, 0.96, 0));
  }

  void _up(PointerEvent event) {
    _press.animateWith(SpringSimulation(_spring, _press.value, 1, 6));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ★ 用 Listener 而不是 GestureDetector：
    //   GestureDetector 会和 FilledButton 自己的点击识别器抢手势，
    //   而且如果两边都挂 onTap，一下会触发两次（翻两页 / 直接跳过最后一页）。
    //   Listener 只旁听指针事件、不进手势竞技场，按下去缩、松开弹，
    //   点击仍然由 FilledButton 全权处理。
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: ScaleTransition(
        scale: _press,
        child: FilledButton(
          onPressed: widget.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: DiaryPalette.vermilion,
            foregroundColor: DiaryPalette.onVermilion,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontFamily: DiaryPalette.round,
              fontSize: 17,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 四张小插画
// ══════════════════════════════════════════════════════════════════════

/// 页面尺寸统一，免得翻页时下方文字跳来跳去
const double _kArtHeight = 196;

/// 第一页：三张歪着的纸片叠在一起
class _PaperStack extends StatelessWidget {
  const _PaperStack();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kArtHeight,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _sheet(w: 126, h: 94, tilt: -0.13, dx: -26, dy: 12),
          _sheet(w: 122, h: 90, tilt: 0.09, dx: 26, dy: -8),
          _sheet(w: 152, h: 114, tilt: -0.02, dx: 0, dy: 0),
        ],
      ),
    );
  }

  Widget _sheet({
    required double w,
    required double h,
    required double tilt,
    required double dx,
    required double dy,
  }) {
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: tilt,
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: DiaryPalette.paper,
            borderRadius: BorderRadius.circular(10),
            boxShadow: DiaryPalette.paperShadow(),
          ),
        ),
      ),
    );
  }
}

/// 第二页：一张写了两行字的纸片
class _DiarySample extends StatelessWidget {
  const _DiarySample();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kArtHeight,
      child: Center(
        child: Transform.rotate(
          angle: -0.025,
          child: Container(
            width: 190,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: DiaryPalette.paper,
              borderRadius: BorderRadius.circular(12),
              boxShadow: DiaryPalette.paperShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const InkSeal(text: '念', size: 30, filled: true),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _line(width: 62, height: 7),
                          const SizedBox(height: 6),
                          _line(width: 40, height: 5),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _line(width: double.infinity, height: 7),
                const SizedBox(height: 8),
                _line(width: 118, height: 7),
                const SizedBox(height: 14),
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: DiaryPalette.paperDim,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 拿纸的颜色当「字」，画成一条条的横杠 —— 比真写字省事，
  /// 也不会因为换了字体就串行。
  Widget _line({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DiaryPalette.onPaperFaint,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// 第三页：三个心情标签
class _MoodChips extends StatelessWidget {
  const _MoodChips();

  @override
  Widget build(BuildContext context) {
    // ★ 直接读 DiaryMood，改枚举这里跟着变，不会和真的心情选项对不上
    const moods = <DiaryMood>[DiaryMood.joy, DiaryMood.miss, DiaryMood.emo];

    return SizedBox(
      height: _kArtHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < moods.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 12),
              Transform.rotate(
                angle: (i.isEven ? -1 : 1) * 0.022,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: i == 0
                        ? DiaryPalette.vermilionWash
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: i == 0
                          ? DiaryPalette.vermilion.withValues(alpha: 0.42)
                          : DiaryPalette.onInkFaint,
                    ),
                  ),
                  child: Text(
                    moods[i].label,
                    style: TextStyle(
                      fontFamily: DiaryPalette.round,
                      fontSize: 14.5,
                      height: 1.1,
                      color: i == 0
                          ? DiaryPalette.vermilion
                          : DiaryPalette.onInkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 第四页：聊天室 / 白丝宝宝 两块小牌子
class _TwoTiles extends StatelessWidget {
  const _TwoTiles();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kArtHeight,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _tile(Icons.chat_bubble_outline, '聊天室'),
            const SizedBox(width: 16),
            _tile(Icons.play_arrow, '白丝宝宝'),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: DiaryPalette.paper,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DiaryPalette.paperShadow(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 26, color: DiaryPalette.vermilion),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: DiaryPalette.round,
              fontSize: 14,
              height: 1.2,
              color: DiaryPalette.onPaper,
            ),
          ),
        ],
      ),
    );
  }
}
