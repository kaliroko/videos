/// 弹簧按压 —— 手指按下缩一点、松开弹回来
///
/// ★ 和「欢迎页按钮」同一个写法：
///   用 [Listener] 旁听指针事件，**不**进手势竞技场。
///   如果这里用 GestureDetector 的 onTapDown 再套一个可点的子组件，
///   两边会抢手势，而且都挂 onTap 的话一下会触发两次。
///
/// ★ 没有 Curve、没有 duration —— 全靠 SpringSimulation。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/springs.dart';

class SpringTap extends StatefulWidget {
  const SpringTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.spring = Springs.snappy,
    this.haptic = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下去缩到的比例。整块大面板别给小值，会晃。
  final double pressedScale;

  final SpringDescription spring;

  /// 按下时轻震一下 —— 只给主要操作开，列表项全开太吵
  final bool haptic;

  final HitTestBehavior behavior;

  @override
  State<SpringTap> createState() => _SpringTapState();
}

class _SpringTapState extends State<SpringTap>
    with SingleTickerProviderStateMixin {
  /// unbounded：弹簧的回弹要有地方去，卡在 0.9~1 之间会被削平
  late final AnimationController _ctrl =
      AnimationController.unbounded(vsync: this, value: 1);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    _to(widget.pressedScale);
  }

  void _up(PointerEvent event) => _to(1);

  void _to(double target) {
    _ctrl.animateWith(
      SpringSimulation(widget.spring, _ctrl.value, target, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ScaleTransition(scale: _ctrl, child: widget.child),
      ),
    );
  }
}
