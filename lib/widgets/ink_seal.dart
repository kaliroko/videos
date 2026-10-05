/// 印章 —— 朱砂方章，用来当头像和落款
library;

import 'package:flutter/material.dart';

import '../theme/diary_palette.dart';

class InkSeal extends StatelessWidget {
  const InkSeal({
    super.key,
    required this.text,
    this.size = 38,
    // ★ 这里必须是 null，不能写 = DiaryPalette.vermilion。
    //   默认参数值要求是编译期常量，而调色板为了支持深浅色已经改成 getter，
    //   一旦写进默认值，整个构造函数就失去 const 资格，
    //   所有 `const InkSeal(...)` 的调用点会全部报 const_with_non_const。
    //   所以默认留 null，在 build 里再落回朱砂。
    this.color,
    this.filled = false,
    this.tilt = -0.055,
  });

  /// 一个字
  final String text;

  final double size;

  /// 不传就用朱砂（默认色随深浅色模式变，所以不能做默认值）
  final Color? color;

  /// 实心（匿名时用，视觉上更「盖住」）
  final bool filled;

  /// 微微歪一点，像手盖的
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? DiaryPalette.vermilion;

    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(size * 0.24),
          border: Border.all(color: accent, width: size * 0.058),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            // ★ 用完整字库的圆体：印章上可能是用户昵称的首字，什么字都可能出现
            fontFamily: DiaryPalette.round,
            fontSize: size * 0.5,
            height: 1.0,
            color: filled ? DiaryPalette.onVermilion : accent,
          ),
        ),
      ),
    );
  }
}
