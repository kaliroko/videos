/// 弹簧驱动的开/关包装器
///
/// 丢一个 bool 进来，它用 [SpringSimulation] 把 0 ↔ 1 推过去；
/// builder 拿到的值**不做夹紧**，会带过冲 —— 那一下回弹正是弹簧的手感来源。
///
/// ★ 需要喂给 Opacity / Color.lerp 这类只吃 0~1 的地方时，自己在 builder
///   里夹一下：`final t = value.clamp(0.0, 1.0);`
///
/// ★ 替代的是 AnimatedSlide / AnimatedScale / AnimatedOpacity 这些**隐式**
///   动画 —— 它们只吃 duration + curve，是补间不是物理。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/springs.dart';

class SpringToggle extends StatefulWidget {
  const SpringToggle({
    super.key,
    required this.active,
    required this.builder,
    this.spring = Springs.gentle,
    this.startActive,
  });

  /// 目标状态：true → 推到 1，false → 拉回 0
  final bool active;

  /// 拿当前的弹簧值（未夹紧）来搭界面
  final Widget Function(BuildContext context, double value) builder;

  final SpringDescription spring;

  /// 首帧的初值。不传就按 [active] 取，避免进场时先弹一下
  final bool? startActive;

  @override
  State<SpringToggle> createState() => _SpringToggleState();
}

class _SpringToggleState extends State<SpringToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    // 用 unbounded：有上下界的话过冲会被削平，回弹就没了
    value: (widget.startActive ?? widget.active) ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant SpringToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _t.animateWith(
        SpringSimulation(
          widget.spring,
          _t.value,
          widget.active ? 1 : 0,
          0,
        ),
      );
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => widget.builder(context, _t.value),
    );
  }
}
