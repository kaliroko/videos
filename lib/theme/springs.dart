/// 全 App 共用的弹簧参数表
///
/// ★ 为什么要有这张表：
///   所有动画都从这儿取，别在每个页面里各写各的 —— 不然同一个应用里
///   会冒出好几种「回弹手感」，看起来像几个人拼起来的。
///
/// ★ 只有真弹簧，没有 Curve：
///   Curves.easeOutBack 那种「先冲过头再回来」的曲线是在**模仿**弹簧，
///   但它没有质量、没有速度、也不受手指甩动的影响。
///   要物理真实就用 SpringSimulation。
///
/// ★ 关于阻尼比 ζ = damping / (2·√(stiffness·mass))：
///   ζ < 1 欠阻尼会过冲，ζ = 1 临界阻尼刚好不回头，ζ > 1 过阻尼慢慢爬。
///   下面每一档都把 ζ 和大致过冲量写在注释里，调的时候心里有数。
library;

import 'package:flutter/physics.dart';

class Springs {
  Springs._();

  /// 面板/弹窗进场 —— ζ≈0.65，过冲约 7%
  ///
  /// 落位时轻轻顿一下，不晃。
  static const SpringDescription sheetIn =
      SpringDescription(mass: 1, stiffness: 400, damping: 26);

  /// 面板出场 —— ζ≈1.0，临界阻尼，不回头
  ///
  /// 关掉就是关掉，再弹回来会显得拖沓。
  static const SpringDescription sheetOut =
      SpringDescription(mass: 1, stiffness: 420, damping: 41);

  /// 轻快的一档 —— ζ≈0.36，过冲约 30%
  ///
  /// 按钮按压、开关这种小位移用它：范围小，过冲多一点也不会晃眼。
  static const SpringDescription snappy =
      SpringDescription(mass: 1, stiffness: 620, damping: 18);

  /// 常规位移 —— ζ≈0.72，过冲约 4%
  ///
  /// 底栏、翻页这类**整块**东西的移动用它。阻尼再小整页宽度摆起来会晕。
  static const SpringDescription gentle =
      SpringDescription(mass: 1, stiffness: 380, damping: 28);

  /// 明显回弹 —— ζ≈0.49，过冲约 17%
  ///
  /// 需要「弹一下」才有生气的地方，比如元素进场。
  static const SpringDescription bouncy =
      SpringDescription(mass: 1, stiffness: 420, damping: 20);

  /// 跟手的一档 —— ζ≈0.55，回中快、不过冲太多
  ///
  /// 手势松开之后归位用它：手指刚离开时还带着速度，阻尼太小会甩过头。
  static const SpringDescription settle =
      SpringDescription(mass: 1, stiffness: 420, damping: 24);
}
