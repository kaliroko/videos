/// 印章 —— 朱砂方章，用来当头像和落款
library;

import 'package:flutter/material.dart';

import '../theme/diary_palette.dart';

class InkSeal extends StatelessWidget {
  const InkSeal({
    super.key,
    required this.text,
    this.size = 38,
    this.color = DiaryPalette.vermilion,
    this.filled = false,
    this.tilt = -0.055,
  });

  /// 一个字
  final String text;

  final double size;
  final Color color;

  /// 实心（匿名时用，视觉上更「盖住」）
  final bool filled;

  /// 微微歪一点，像手盖的
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(size * 0.24),
          border: Border.all(color: color, width: size * 0.058),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            // ★ 用完整字库的圆体：印章上可能是用户昵称的首字，什么字都可能出现
            fontFamily: DiaryPalette.round,
            fontSize: size * 0.5,
            height: 1.0,
            color: filled ? DiaryPalette.paper : color,
          ),
        ),
      ),
    );
  }
}
