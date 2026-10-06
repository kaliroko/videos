/// 用弹簧把滚动位置推到某处
///
/// ★ 为什么不能直接用 ScrollController.animateTo / PageController.nextPage：
///   它们的签名只吃 duration + curve —— 是补间，没有质量、没有速度，
///   手指甩动的速度也没法传进去。
///
/// ★ 为什么不用「弹簧控制器 + 每帧 jumpTo」那套土办法：
///   jumpTo 内部会 goIdle() 再 goBallistic()，每帧都发一轮
///   滚动开始/结束通知 —— 靠滚动通知来收底栏的地方会被刷爆。
///
/// ★ 正确姿势是往 ScrollPosition 里塞一个自己的 ScrollActivity：
///   beginActivity() 就是框架留给这个用的口子，
///   BallisticScrollActivity 自己也是这么实现的。
library;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/springs.dart';

/// 用弹簧把 [position] 滚到 [target]（像素）。
///
/// [velocity] 是手指离开时的速度，直接当弹簧的初始条件 ——
/// 「甩一下滑得更远」就是这么来的。
void springScrollTo(
  ScrollPosition position,
  double target, {
  SpringDescription spring = Springs.settle,
  double velocity = 0,
}) {
  position.beginActivity(
    _SpringScrollActivity(
      position,
      // 目标和当前之间用 ScrollSpringSimulation：
      // 它在 SpringSimulation 之上把结果夹到 >= 0，避免过冲进负值
      ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
      ),
    ),
  );
}

class _SpringScrollActivity extends ScrollActivity {
  _SpringScrollActivity(super.delegate, Simulation simulation) {
    _controller = AnimationController.unbounded(vsync: delegate.vsync)
      ..addListener(_tick)
      ..animateWith(simulation);
  }

  late final AnimationController _controller;

  void _tick() {
    // 每帧都把当前值落下去；收尾那一帧也得算数，
    // 不然最后会差那么几个像素没走到。
    delegate.setPixels(_controller.value);

    if (_controller.isAnimating) return;

    // 弹簧停稳 → 把控制权还给滚动位置。
    // 这一下会 dispose 掉当前 activity（也就是自己），
    // 但框架的 BallisticScrollActivity 同样是在 _tick 里这么收尾的，安全。
    delegate.goIdle();
  }

  @override
  bool get isScrolling => true;

  @override
  void applyNewDimensions() {
    // 视口尺寸中途变了不打断弹簧：目标像素没变，
    // setPixels 那边的边界条件会把它收住。
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
