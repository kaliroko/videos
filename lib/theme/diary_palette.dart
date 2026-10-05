/// 碎碎念 · 视觉基调：墨 · 朱 · 纸
///
/// 故意不走「暗色 + 渐变 + 霓虹」那套 —— 这里是一张暗桌子上摊着几张纸片，
/// 唯一的高饱和色是印章的朱砂红，只出现在印章、强调和主按钮上。
///
/// ★ 关于纸色：最初用的是很亮的米白（#EFE9DC），在纯黑背景上对比度高达 16:1，
///   整片卡片亮得刺眼。现在换成压暗一半的「黄昏纸」，卡与黑底的对比降到 8.6:1，
///   温和很多。代价是纸变暗后，卡上文字可用的对比度上限也跟着降，
///   所以 onPaper / vermilionDeep 这一整套都跟着重算过，不要单独改某一个。
library;

import 'package:flutter/material.dart';

class DiaryPalette {
  DiaryPalette._();

  // ── 墨底（比 App 纯黑略暖一点，像宣纸压在暗处） ───────────────────
  static const Color ink = Color(0xFF0C0B0A);
  static const Color inkSoft = Color(0xFF16130F);

  // ── 纸 ────────────────────────────────────────────────────────────
  /// 卡片纸色 —— 对黑底 8.6:1
  static const Color paper = Color(0xFFB4AA96);

  /// 纸上的凹陷（输入框底、图片占位）—— 对 paper 有 1.17:1 的层次
  static const Color paperDim = Color(0xFFA79D89);

  /// 描边 / 拖拽把手
  static const Color paperEdge = Color(0xFF8F8674);

  // ── 纸上的字 ──────────────────────────────────────────────────────
  /// 正文 —— 对 paper 7.76:1
  static const Color onPaper = Color(0xFF1A1714);

  /// 次要信息（昵称、标签）—— 5.05:1
  static const Color onPaperSoft = Color(0xFF3D3830);

  /// 最弱的一层（时间、计数）—— 3.21:1，只用于真正的次要提示
  static const Color onPaperFaint = Color(0xFF5C5548);

  /// 纸上的细线
  static const Color rule = Color(0x1A2A241C);

  // ── 朱砂（唯一强调色） ────────────────────────────────────────────
  /// 填充用：印章底、主按钮、FAB
  static const Color vermilion = Color(0xFFC8452F);

  /// ★ 纸上的朱砂文字 —— 必须压得比 vermilion 深，否则在暗纸上读不清（5.29:1）
  static const Color vermilionDeep = Color(0xFF641D11);

  /// 朱砂淡底（标签胶囊）
  static const Color vermilionWash = Color(0x24C8452F);

  /// ★ 朱砂底上的文字 —— 别用 paper，那个色现在压暗了会糊
  static const Color onVermilion = Color(0xFFFBF7EF);

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

  /// 循环书写的那句话（顶部会动的那行小字）
  static const TextStyle brushLine = TextStyle(
    fontFamily: brush,
    fontSize: 23,
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
  /// 纸色压暗之后影子也别再那么重，否则卡片边缘会发脏
  static List<BoxShadow> paperShadow({double lift = 1}) => <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 16 * lift,
          offset: Offset(0, 8 * lift),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
}
