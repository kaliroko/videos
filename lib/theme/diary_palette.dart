/// 碎碎念 · 视觉基调：墨 · 朱 · 纸
///
/// 故意不走「暗色 + 渐变 + 霓虹」那套 —— 这里是一张暗桌子上摊着几张米色纸片，
/// 唯一的高饱和色是印章的朱砂红，只出现在印章、强调和主按钮上。
library;

import 'package:flutter/material.dart';

class DiaryPalette {
  DiaryPalette._();

  // ── 墨底（比 App 纯黑略暖一点，像宣纸压在暗处） ───────────────────
  static const Color ink = Color(0xFF0C0B0A);
  static const Color inkSoft = Color(0xFF16130F);

  // ── 纸 ────────────────────────────────────────────────────────────
  static const Color paper = Color(0xFFEFE9DC);
  static const Color paperDim = Color(0xFFE2DACA);
  static const Color paperEdge = Color(0xFFD6CCB8);

  // ── 纸上的字 ──────────────────────────────────────────────────────
  static const Color onPaper = Color(0xFF23201C);
  static const Color onPaperSoft = Color(0xFF6C6255);
  static const Color onPaperFaint = Color(0xFF9C9082);

  /// 纸上的细线
  static const Color rule = Color(0x1A3A342C);

  // ── 朱砂（唯一强调色） ────────────────────────────────────────────
  static const Color vermilion = Color(0xFFC8452F);
  static const Color vermilionDeep = Color(0xFF9E3222);
  static const Color vermilionWash = Color(0x1FC8452F);

  // ── 墨底上的字 ────────────────────────────────────────────────────
  static const Color onInk = Color(0xFFF1EBE1);
  static const Color onInkSoft = Color(0x99F1EBE1);
  static const Color onInkFaint = Color(0x42F1EBE1);

  // ── 字体族 ────────────────────────────────────────────────────────
  /// 毛笔手写体 —— 只用于装饰性文字
  static const String brush = 'MaShanZheng';

  /// 圆润可爱体 —— 昵称、标签、按钮
  static const String round = 'ZCOOLKuaiLe';

  // ── 常用文字样式 ──────────────────────────────────────────────────

  /// 页头大字
  static const TextStyle brushHero = TextStyle(
    fontFamily: brush,
    fontSize: 54,
    height: 1.1,
    color: onInk,
    letterSpacing: 1.5,
  );

  /// 循环书写的那句话
  static const TextStyle brushLine = TextStyle(
    fontFamily: brush,
    fontSize: 20,
    height: 1.5,
    color: onInkSoft,
    letterSpacing: 0.8,
  );

  /// 纸片上的日期 / 小字
  static const TextStyle brushOnPaper = TextStyle(
    fontFamily: brush,
    fontSize: 15,
    height: 1.15,
    color: onPaperFaint,
    letterSpacing: 0.6,
  );

  /// 按钮 / 标签
  static const TextStyle roundLabel = TextStyle(
    fontFamily: round,
    fontSize: 13.5,
    height: 1.3,
    color: onPaperSoft,
    letterSpacing: 0.4,
  );

  static const TextStyle roundOnInk = TextStyle(
    fontFamily: round,
    fontSize: 13.5,
    height: 1.3,
    color: onInkSoft,
    letterSpacing: 0.4,
  );

  // ── 影子 ─────────────────────────────────────────────────────────
  static List<BoxShadow> paperShadow({double lift = 1}) => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.42),
          blurRadius: 18 * lift,
          offset: Offset(0, 10 * lift),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
}
