/// 碎碎念 · 视觉基调：墨 · 朱 · 纸
///
/// 深色是「暗桌上摊着纸片」，浅色是「浅木桌上摊着纸片」。
/// 唯一的高饱和色始终是印章的朱砂红，只出现在印章、强调和主按钮上。
///
/// ★ 关于「为什么会有一个可变的静态 mode」
///   这些颜色被 197 处引用，而且大量嵌在 `const` 构造里。
///   要改成按 BuildContext 取色（ThemeExtension 那一套），
///   就得把整棵树的 const 全部摘掉、引用全部重写 —— 改动面极大、
///   而且没法在本地编译验证。
///   所以这里用「静态当前模式 + getter」：
///   成员名一个都不变，调用点完全不用动，只在 MaterialApp 的 builder 里
///   每帧同步一次系统亮度。系统切深浅色时 MaterialApp 会重建，
///   builder 跟着跑，整棵树就用新颜色重建了。
///
/// ★ 纸色调过两轮：最初 #EFE9DC（对黑底 16.3:1）刺眼，
///   后来压到 #B4AA96（8.6:1）又偏暗，现在深色取中间值 #CFC8B8（11.8:1）。
library;

import 'package:flutter/material.dart';

/// 当前配色模式
enum DiaryMode { dark, light }

class DiaryPalette {
  DiaryPalette._();

  // ══════════════════════════════════════════════════════════════════
  // 模式开关
  // ══════════════════════════════════════════════════════════════════

  static DiaryMode _mode = DiaryMode.dark;

  static DiaryMode get mode => _mode;
  static bool get isLight => _mode == DiaryMode.light;

  /// 由 MaterialApp 的 builder 每帧调用一次，跟随系统深/浅色
  static void syncWith(Brightness brightness) {
    final next =
        brightness == Brightness.light ? DiaryMode.light : DiaryMode.dark;
    if (next != _mode) _mode = next;
  }

  // ══════════════════════════════════════════════════════════════════
  // 颜色 —— 深色 / 浅色两套
  // ══════════════════════════════════════════════════════════════════

  // ── 底色（App 背景）──────────────────────────────────────────────
  static Color get ink =>
      isLight ? const Color(0xFFEDE7DA) : const Color(0xFF0C0B0A);

  static Color get inkSoft =>
      isLight ? const Color(0xFFE3DCCB) : const Color(0xFF16130F);

  /// 背景顶部那层很淡的光晕（碎碎念首页和聊天室都用它）
  static Color get inkGlow =>
      isLight ? const Color(0xFFFBF8F1) : const Color(0xFF1F1A14);

  // ── 纸（卡片 / 弹窗）────────────────────────────────────────────
  /// 深色对底 11.8:1；浅色靠影子分层，不靠对比
  static Color get paper =>
      isLight ? const Color(0xFFFFFDF8) : const Color(0xFFCFC8B8);

  /// 纸上的凹陷（输入框底、图片占位）
  static Color get paperDim =>
      isLight ? const Color(0xFFF2EDE2) : const Color(0xFFC2BBAB);

  /// 描边 / 拖拽把手
  static Color get paperEdge =>
      isLight ? const Color(0xFFDED6C6) : const Color(0xFFACA595);

  // ── 纸上的字 ────────────────────────────────────────────────────
  static Color get onPaper =>
      isLight ? const Color(0xFF23201C) : const Color(0xFF1A1714);

  static Color get onPaperSoft =>
      isLight ? const Color(0xFF5A5245) : const Color(0xFF3D3830);

  static Color get onPaperFaint =>
      isLight ? const Color(0xFF8A8070) : const Color(0xFF5C5548);

  /// 纸上的细线
  static Color get rule =>
      isLight ? const Color(0x1A3A342C) : const Color(0x1A2A241C);

  // ── 朱砂（唯一强调色）──────────────────────────────────────────
  static Color get vermilion => const Color(0xFFC8452F);

  /// 纸上的朱砂文字 —— 比 vermilion 深，保证读得清
  static Color get vermilionDeep =>
      isLight ? const Color(0xFFB03A26) : const Color(0xFF641D11);

  /// 朱砂淡底（标签胶囊）
  static Color get vermilionWash =>
      isLight ? const Color(0x1FC8452F) : const Color(0x24C8452F);

  /// 朱砂底上的文字 —— 别用 paper，纸色在深色模式下会糊
  static Color get onVermilion => const Color(0xFFFBF7EF);

  // ── 底色上的字 ──────────────────────────────────────────────────
  static Color get onInk =>
      isLight ? const Color(0xFF23201C) : const Color(0xFFF1EBE1);

  static Color get onInkSoft =>
      isLight ? const Color(0xFF5A5245) : const Color(0x99F1EBE1);

  static Color get onInkFaint =>
      isLight ? const Color(0xFF8A8070) : const Color(0x42F1EBE1);

  // ── 聊天室专用（和碎碎念同一套，只是各模式取值不同）──────────────
  /// 别人的气泡
  static Color get chatBubbleOther =>
      isLight ? const Color(0xFFE8E2D5) : const Color(0xFF221E19);

  /// 输入框 / 顶栏的底
  static Color get chatInputBg =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1C1813);

  /// 暗底上的朱砂提亮版（深色下朱砂原色对比不够）
  static Color get chatAccent =>
      isLight ? const Color(0xFFB03A26) : const Color(0xFFE07A62);

  /// 别人气泡上的时间
  static Color get chatTimeOther =>
      isLight ? const Color(0xFF7A7266) : const Color(0xFF8C8375);

  /// 在线小绿点
  static Color get chatOnline =>
      isLight ? const Color(0xFF3E9E5B) : const Color(0xFF5FB878);

  // ══════════════════════════════════════════════════════════════════
  // 字体族
  // ══════════════════════════════════════════════════════════════════

  /// 毛笔手写体 —— 只用于装饰性文字
  static const String brush = 'MaShanZheng';

  /// 圆润可爱体 —— 昵称、标签、按钮
  static const String round = 'ZCOOLKuaiLe';

  // ══════════════════════════════════════════════════════════════════
  // 常用文字样式（随模式变化，所以是 getter 不是 const）
  // ══════════════════════════════════════════════════════════════════

  /// 页头大字
  static TextStyle get brushHero => TextStyle(
        fontFamily: brush,
        fontSize: 54,
        height: 1.1,
        color: onInk,
        letterSpacing: 1.5,
      );

  /// 循环书写的那句话（顶部会动的那行小字）
  static TextStyle get brushLine => TextStyle(
        fontFamily: brush,
        fontSize: 23,
        height: 1.5,
        color: onInkSoft,
        letterSpacing: 0.8,
      );

  /// 纸片上的日期 / 小字
  static TextStyle get brushOnPaper => TextStyle(
        fontFamily: brush,
        fontSize: 15,
        height: 1.15,
        color: onPaperFaint,
        letterSpacing: 0.6,
      );

  /// 页头那句固定题词（不参与动态书写）。
  /// ★ 用圆体：这句话里有「棵树藏秘密」等毛笔子集里没有的字，
  ///   硬用毛笔体只会回退成系统字体。
  static TextStyle get heroTagline => TextStyle(
        fontFamily: round,
        fontSize: 15,
        height: 1.5,
        color: onInkSoft,
        letterSpacing: 1.6,
      );

  /// 题词的英文翻译 —— 比中文小一号、更淡，当注解看
  static TextStyle get heroTaglineEn => TextStyle(
        fontFamily: round,
        fontSize: 12,
        height: 1.5,
        color: onInkFaint,
        letterSpacing: 0.5,
      );

  /// 纸片上的时间 / 日期。
  /// ★ 圆体：日期里的「年」「月」不在毛笔子集里，用毛笔体会回退成系统字体。
  static TextStyle get timeOnPaper => TextStyle(
        fontFamily: round,
        fontSize: 12,
        height: 1.3,
        color: onPaperFaint,
        letterSpacing: 0.2,
      );

  /// 页头大字下方的小字
  static TextStyle get heroNote => TextStyle(
        fontFamily: round,
        fontSize: 12.5,
        height: 1.6,
        color: onInkSoft,
        letterSpacing: 0.3,
      );

  /// 按钮 / 标签
  static TextStyle get roundLabel => TextStyle(
        fontFamily: round,
        fontSize: 13.5,
        height: 1.3,
        color: onPaperSoft,
        letterSpacing: 0.4,
      );

  static TextStyle get roundOnInk => TextStyle(
        fontFamily: round,
        fontSize: 13.5,
        height: 1.3,
        color: onInkSoft,
        letterSpacing: 0.4,
      );

  // ══════════════════════════════════════════════════════════════════
  // 影子
  // ══════════════════════════════════════════════════════════════════

  /// 浅色模式下卡片和背景对比很低，全靠这层影子分层，所以要更实一点
  static List<BoxShadow> paperShadow({double lift = 1}) {
    if (isLight) {
      return <BoxShadow>[
        BoxShadow(
          color: const Color(0xFF3A342C).withValues(alpha: 0.18),
          blurRadius: 16 * lift,
          offset: Offset(0, 8 * lift),
        ),
        BoxShadow(
          color: const Color(0xFF3A342C).withValues(alpha: 0.08),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
    }
    return <BoxShadow>[
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
}
