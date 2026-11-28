/// Her Haven 设计令牌 —— 全 App 唯一真相源
///
/// 来源：`Her Haven · 私密乌托邦` 原型网页的 CSS 变量。
/// 原来那套「米色纸 + 朱砂印章」整体换成「暗玻璃 + 玫瑰 + 薰衣草」。
///
/// ★ 为什么单独开一个文件而不是直接改 DiaryPalette：
///   DiaryPalette 有 197 个调用点。这里定义真值，DiaryPalette 全体**委托**
///   到这儿，于是旧界面一行不改就整体换皮，新界面直接用 HavenColors。
///   一处改色，两边同时生效。
///
/// ★ 深浅两套都留着：
///   原网页只有暗色，但这个 App 之前已经做了「跟随系统深浅色」。
///   暗色严格照网页来；浅色是同一套语言的「日光玻璃」版本 ——
///   玫瑰和薰衣草还是那两个，只是压在浅底上，所以各自调深以保证对比度。
///
/// ★ 玻璃 ≠ 半透明色：
///   网页的 `backdrop-filter: blur(20px)` 在 Flutter 里要
///   BackdropFilter + ImageFilter.blur 才有真玻璃感。
///   这里给的是**底色**，模糊由 GlassCard 负责。
///   拿不到模糊的地方（比如超长列表）退化成这个半透明底色也站得住。
library;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 当前配色模式
enum HavenMode { dark, light }

class HavenColors {
  HavenColors._();

  // ══════════════════════════════════════════════════════════════════
  // 模式
  // ══════════════════════════════════════════════════════════════════

  static HavenMode _mode = HavenMode.dark;

  static HavenMode get mode => _mode;
  static bool get isDark => _mode == HavenMode.dark;
  static bool get isLight => _mode == HavenMode.light;

  /// 每帧由 MaterialApp.builder 同步系统亮度
  static void syncWith(Brightness brightness) {
    _mode = brightness == Brightness.light ? HavenMode.light : HavenMode.dark;
  }

  /// 测试 / 强制切换用
  static void force(HavenMode m) => _mode = m;

  // ══════════════════════════════════════════════════════════════════
  // 底 —— 网页 --bg-base: #0D0A10
  // ══════════════════════════════════════════════════════════════════

  /// 页面底色
  static Color get bg =>
      isDark ? const Color(0xFF0D0A10) : const Color(0xFFF6F2F5);

  /// 比底色再深/再浅一档：底栏、输入区、弹窗背后
  static Color get bgSoft =>
      isDark ? const Color(0xFF16111A) : const Color(0xFFFFFFFF);

  /// 顶部光晕（网页用背景图 + 渐变遮罩，这里用径向光晕近似）
  static Color get bgGlow =>
      isDark ? const Color(0xFF241C2B) : const Color(0xFFEDE4EA);

  /// 遮罩（弹窗背后的压暗）
  static Color get scrim => isDark
      ? const Color(0xFF0D0A10).withValues(alpha: 0.82)
      : const Color(0xFF2A2230).withValues(alpha: 0.32);

  // ══════════════════════════════════════════════════════════════════
  // 玻璃 —— 网页 --glass-bg / --glass-border
  // ══════════════════════════════════════════════════════════════════

  /// 玻璃卡底色（模糊由 GlassCard 加，这里只是颜色）
  static Color get glass => isDark
      ? const Color(0xFF16111A).withValues(alpha: 0.60)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.72);

  /// 更厚一点的玻璃：输入框、聊天区、次级面板
  static Color get glassSunken => isDark
      ? const Color(0xFF000000).withValues(alpha: 0.24)
      : const Color(0xFF2A2230).withValues(alpha: 0.05);

  /// 玻璃描边 —— 网页 rgba(255,255,255,.08)
  static Color get glassBorder => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      : const Color(0xFF1C1620).withValues(alpha: 0.08);

  /// 细分隔线 —— 网页 --line: rgba(255,255,255,.06)
  static Color get hairline => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.06)
      : const Color(0xFF1C1620).withValues(alpha: 0.09);

  /// 玻璃卡投影 —— 网页 0 20px 40px rgba(0,0,0,.6)
  /// ★ 阴影从 40/20 收到 22/10、透明度也降了 ——
  ///   滚动时大半径阴影每帧都要重新合成，是掉帧的隐形大户；
  ///   收小之后卡片的层级反而更干净。
  static List<BoxShadow> glassShadow({double lift = 1}) => <BoxShadow>[
        BoxShadow(
          color: isDark
              ? const Color(0xFF000000).withValues(alpha: 0.42)
              : const Color(0xFF2A2230).withValues(alpha: 0.08),
          blurRadius: 22 * lift,
          offset: Offset(0, 10 * lift),
        ),
      ];

  /// 不开背景模糊时用的「厚玻璃」底色
  ///
  /// 模糊很贵：滚动列表里每张卡一层 BackdropFilter，等于每帧多几次
  /// 离屏合成。关掉模糊之后底色要稍微实一点，字才不会和背景图打架。
  static Color get glassOpaque => isDark
      ? const Color(0xFF16111A).withValues(alpha: 0.74)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.86);

  // ══════════════════════════════════════════════════════════════════
  // 玫瑰 —— 网页 --rose: #D17997
  // ══════════════════════════════════════════════════════════════════

  /// 主强调色
  ///
  /// 浅色模式下调深：玫瑰压在浅底上如果还用 #D17997，
  /// 对比度只有 2.6:1，做正文强调是看不清的。
  static Color get rose =>
      isDark ? const Color(0xFFD17997) : const Color(0xFFB04264);

  /// 按下 / hover 那一档 —— 网页 .btn.primary:hover #C06A86
  static Color get roseDeep =>
      isDark ? const Color(0xFFC06A86) : const Color(0xFF8E2F4C);

  /// 玫瑰的高亮底 —— 网页 --rose-light: rgba(209,121,151,.12)
  static Color get roseWash => isDark
      ? const Color(0xFFD17997).withValues(alpha: 0.12)
      : const Color(0xFFB04264).withValues(alpha: 0.10);

  /// 玫瑰描边（选中的 chip、危险按钮）
  static Color get roseEdge => isDark
      ? const Color(0xFFD17997).withValues(alpha: 0.45)
      : const Color(0xFFB04264).withValues(alpha: 0.45);

  /// 玫瑰上的字 —— 网页统一 #fff
  static Color get onRose => const Color(0xFFFFFFFF);

  // ══════════════════════════════════════════════════════════════════
  // 薰衣草 —— 网页 --lavender: #8E7BB5
  // ══════════════════════════════════════════════════════════════════

  /// 第二强调色：和玫瑰组成网页那种 135° 渐变
  static Color get lavender =>
      isDark ? const Color(0xFF8E7BB5) : const Color(0xFF6B5A8E);

  /// 玫瑰 → 薰衣草 的对角渐变（首页主视觉那条）
  static LinearGradient get tintGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          rose.withValues(alpha: 0.05),
          lavender.withValues(alpha: 0.05),
        ],
      );

  // ══════════════════════════════════════════════════════════════════
  // 字 —— 网页 --ink #EAE5ED / --muted #8E8395
  // ══════════════════════════════════════════════════════════════════

  /// 主文字
  static Color get ink =>
      isDark ? const Color(0xFFEAE5ED) : const Color(0xFF1C1620);

  /// 次级文字（网页 #C4BDCB）
  static Color get inkSoft =>
      isDark ? const Color(0xFFC4BDCB) : const Color(0xFF443B4E);

  /// 弱化文字（网页 --muted #8E8395）
  static Color get inkFaint =>
      isDark ? const Color(0xFF8E8395) : const Color(0xFF6E6377);

  /// 页脚那种几乎看不见的字（网页 #49414E）
  static Color get inkGhost =>
      isDark ? const Color(0xFF49414E) : const Color(0xFFA79EAF);

  /// 纯白强调（网页里标题大量用 #fff）
  static Color get inkStrong => isDark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF1C1620);

  // ══════════════════════════════════════════════════════════════════
  // 聊天 —— 网页 .msg.her / .msg.me
  // ══════════════════════════════════════════════════════════════════

  /// 对方气泡：rgba(255,255,255,.08)
  static Color get bubbleOther => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      : const Color(0xFF1C1620).withValues(alpha: 0.06);

  /// 自己气泡：rose-light + 玫瑰描边
  static Color get bubbleMine => roseWash;

  /// 聊天输入区底：rgba(0,0,0,.4)
  static Color get chatInput => isDark
      ? const Color(0xFF000000).withValues(alpha: 0.40)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.72);

  // ══════════════════════════════════════════════════════════════════
  // 形状与间距 —— 网页 --radius: 12px
  // ══════════════════════════════════════════════════════════════════

  /// 卡片
  static const double radiusCard = 12;

  /// 次级面板 / 图片 / 输入框
  static const double radiusSm = 8;

  /// 输入框
  static const double radiusField = 6;

  /// 按钮 / chip
  static const double radiusChip = 4;

  /// 胶囊（头像、浮动提示）
  static const double radiusPill = 999;

  // ══════════════════════════════════════════════════════════════════
  // 背景遮罩 —— 网页 #bgOverlay
  //   linear-gradient(180deg, rgba(13,10,16,.5) 0%, rgba(13,10,16,.9) 60%, var(--bg-base) 100%)
  // ══════════════════════════════════════════════════════════════════

  /// 压在背景图上的那条渐变。上方留一点图，越往下越沉，最后完全接到底色，
  /// 这样内容区永远坐在实色上，卡片再透也读得清。
  static LinearGradient get overlayGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          bg.withValues(alpha: isDark ? 0.50 : 0.70),
          bg.withValues(alpha: isDark ? 0.90 : 0.88),
          bg,
        ],
        stops: const <double>[0.0, 0.60, 1.0],
      );

  /// 背景图本身的压暗/提亮层。网页是 filter: brightness(.65)，浅色模式反过来提亮。
  static Color get backdropVeil => isDark
      ? const Color(0xFF0D0A10).withValues(alpha: 0.38)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.66);

  /// 玫瑰光晕 —— 首页 hero、呼吸圆、FAB 的投影都用它
  static Color get roseGlow => rose.withValues(alpha: isDark ? 0.35 : 0.22);

  // ══════════════════════════════════════════════════════════════════
  // 字体族 —— 网页 font-family 的对应关系
  //
  //   网页 h1/h2/h3/.serif → "Noto Serif SC", "Songti SC", serif
  //   网页 body           → "PingFang SC", "Microsoft YaHei", sans-serif
  //
  // ★ 衬线体是**打包进 APK 的子集**（assets/fonts/NotoSerifSC-*.ttf），
  //   只含界面固定文案；用户输入的长文本一律走 [sans]，避免缺字回退混排。
  // ★ 无衬线体故意不打包：完整中文无衬线 10MB+，声明的族名在 iOS 有、
  //   Android 上没有，Flutter 会优雅回退到系统默认中文字体 ——
  //   这跟网页写 "PingFang SC", sans-serif 的策略完全一致。
  // ══════════════════════════════════════════════════════════════════

  /// 衬线体（标题、题词、计时数字）
  static const String serif = 'NotoSerifSC';

  /// 无衬线体（正文、标签、按钮）
  static const String sans = 'PingFang SC';

  // ══════════════════════════════════════════════════════════════════
  // 文字样式 —— 字号/字距严格照网页
  // ══════════════════════════════════════════════════════════════════

  /// .brand h1 —— 26px / 字距 3 / 纯白
  static TextStyle get brand => TextStyle(
        fontFamily: serif,
        fontSize: 26,
        height: 1.25,
        fontWeight: FontWeight.w300,
        letterSpacing: 3,
        color: inkStrong,
      );

  /// .brand p —— 11px / 字距 3 / 玫瑰
  static TextStyle get brandSub => TextStyle(
        fontFamily: sans,
        fontSize: 11,
        height: 1.4,
        letterSpacing: 3,
        color: rose,
      );

  /// .view-title —— 22px 衬线标题
  static TextStyle get viewTitle => TextStyle(
        fontFamily: serif,
        fontSize: 22,
        height: 1.35,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
        color: inkStrong,
      );

  /// .view-title small —— 12px 弱化注解
  static TextStyle get viewTitleNote => TextStyle(
        fontFamily: sans,
        fontSize: 12,
        height: 1.5,
        letterSpacing: 0,
        color: inkFaint,
      );

  /// .hero h2 —— 28px
  static TextStyle get heroTitle => TextStyle(
        fontFamily: serif,
        fontSize: 28,
        height: 1.4,
        fontWeight: FontWeight.w400,
        letterSpacing: 2,
        color: inkStrong,
      );

  /// .eyebrow —— 11px 大写字距 2
  static TextStyle get eyebrow => TextStyle(
        fontFamily: sans,
        fontSize: 11,
        height: 1.5,
        letterSpacing: 2,
        color: inkFaint,
      );

  /// .hero .sub —— 13.5px / 行高 1.8
  static TextStyle get body => TextStyle(
        fontFamily: sans,
        fontSize: 13.5,
        height: 1.8,
        letterSpacing: 0.3,
        color: inkSoft,
      );

  /// .entry-note —— 正文
  static TextStyle get bodyOnGlass => TextStyle(
        fontFamily: sans,
        fontSize: 13.5,
        height: 1.8,
        letterSpacing: 0.3,
        color: inkSoft,
      );

  /// 小字注解（12px）
  static TextStyle get small => TextStyle(
        fontFamily: sans,
        fontSize: 12,
        height: 1.7,
        letterSpacing: 0.5,
        color: inkFaint,
      );

  /// 标签 / 按钮（13px）
  static TextStyle get label => TextStyle(
        fontFamily: sans,
        fontSize: 13,
        height: 1.4,
        letterSpacing: 1,
        color: inkSoft,
      );

  /// 标题下的说明（12.5px）
  static TextStyle get caption => TextStyle(
        fontFamily: sans,
        fontSize: 12.5,
        height: 1.75,
        letterSpacing: 0.4,
        color: inkFaint,
      );

  /// .quick-timer / .sync-timer-val —— 衬线等宽数字
  static TextStyle timer({double size = 36, Color? color}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        height: 1.1,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        color: color ?? inkStrong,
      );

  /// .mini b —— 14px
  static TextStyle get cardTitle => TextStyle(
        fontFamily: sans,
        fontSize: 14,
        height: 1.4,
        letterSpacing: 1,
        color: inkStrong,
      );

  /// .stat b —— 28px 衬线数字
  static TextStyle get statNumber => TextStyle(
        fontFamily: serif,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
        color: inkStrong,
      );

  /// 页脚 / 免责声明（11px 几乎看不见）
  static TextStyle get footnote => TextStyle(
        fontFamily: sans,
        fontSize: 11,
        height: 1.9,
        letterSpacing: 0.5,
        color: inkGhost,
      );
}
