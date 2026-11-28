/// 旧配色门面 —— 现在只是 [HavenColors] 的转发层
///
/// ★ 为什么不直接删掉它：
///   全 App 有 197 个 `DiaryPalette.xxx` 调用点。保留这一层转发，
///   旧界面一行不用改就整体换成 Her Haven 的暗玻璃玫瑰风；
///   新界面直接写 HavenColors。两边共用同一份真值，改一处全都生效。
///
/// ★ 名字保留但语义已经变了，对照表（旧 → 新）：
///     ink          页面底        → HavenColors.bg
///     paper        卡片底        → HavenColors.glass
///     onPaper      卡片上的字    → HavenColors.ink
///     vermilion    朱砂          → HavenColors.rose（玫瑰）
///     brush        毛笔体        → 衬线体 Noto Serif SC
///     round        圆体          → 系统无衬线（PingFang SC）
///   「纸」和「朱砂」这套词已经名不副实，但改名等于动 197 个调用点，
///   所以先留着，等新模块铺完再逐步收掉。
library;

import 'package:flutter/material.dart';

import 'haven.dart';

/// 当前配色模式（旧名，实际值来自 HavenColors）
enum DiaryMode { dark, light }

class DiaryPalette {
  DiaryPalette._();

  // ══════════════════════════════════════════════════════════════════
  // 模式开关
  // ══════════════════════════════════════════════════════════════════

  static DiaryMode get mode =>
      HavenColors.isLight ? DiaryMode.light : DiaryMode.dark;

  static bool get isLight => HavenColors.isLight;

  /// 由 MaterialApp 的 builder 每帧调用一次，跟随系统深/浅色。
  /// 直接转发给 HavenColors —— 两个门面必须同步，否则会一半新色一半旧色。
  static void syncWith(Brightness brightness) {
    HavenColors.syncWith(brightness);
  }

  // ══════════════════════════════════════════════════════════════════
  // 底色
  // ══════════════════════════════════════════════════════════════════

  static Color get ink => HavenColors.bg;
  static Color get inkSoft => HavenColors.bgSoft;
  static Color get inkGlow => HavenColors.bgGlow;

  // ══════════════════════════════════════════════════════════════════
  // 「纸」→ 玻璃卡
  // ══════════════════════════════════════════════════════════════════

  static Color get paper => HavenColors.glass;
  static Color get paperDim => HavenColors.glassSunken;
  static Color get paperEdge => HavenColors.glassBorder;

  static Color get onPaper => HavenColors.ink;
  static Color get onPaperSoft => HavenColors.inkSoft;
  static Color get onPaperFaint => HavenColors.inkFaint;

  static Color get rule => HavenColors.hairline;

  // ══════════════════════════════════════════════════════════════════
  // 「朱砂」→ 玫瑰
  // ══════════════════════════════════════════════════════════════════

  static Color get vermilion => HavenColors.rose;
  static Color get vermilionDeep => HavenColors.roseDeep;
  static Color get vermilionWash => HavenColors.roseWash;
  static Color get onVermilion => HavenColors.onRose;

  // ══════════════════════════════════════════════════════════════════
  // 底色上的字
  // ══════════════════════════════════════════════════════════════════

  static Color get onInk => HavenColors.ink;
  static Color get onInkSoft => HavenColors.inkSoft;
  static Color get onInkFaint => HavenColors.inkFaint;

  // ══════════════════════════════════════════════════════════════════
  // 聊天室
  // ══════════════════════════════════════════════════════════════════

  static Color get chatBubbleOther => HavenColors.bubbleOther;
  static Color get chatInputBg => HavenColors.chatInput;
  static Color get chatAccent => HavenColors.rose;
  static Color get chatTimeOther => HavenColors.inkFaint;

  /// 在线小绿点 —— 绿色是状态语义，Her Haven 的玫瑰里没有对应色，
  /// 保留绿，只把明度调到和暗玻璃搭得上。
  static Color get chatOnline =>
      isLight ? const Color(0xFF3E9E5B) : const Color(0xFF5FB878);

  // ══════════════════════════════════════════════════════════════════
  // 字体族
  // ══════════════════════════════════════════════════════════════════

  /// 衬线体 —— 标题、题词。
  ///
  /// ★ 打包的是子集版（只含 UI 固定文案），用户输入的正文走系统字库。
  ///   完整 Noto Serif SC 有 24MB，全量打包 APK 直接爆。
  static const String brush = 'NotoSerifSC';

  /// 无衬线体 —— 标签、按钮、正文小字。
  ///
  /// ★ 故意**不打包**：完整中文无衬线也有 10MB+。
  ///   'PingFang SC' 在 iOS 上是系统字体，能直接解析；
  ///   Android 上没有这个族名，Flutter 会优雅回退到系统默认中文字体。
  ///   这跟原网页写 `"PingFang SC", "Microsoft YaHei", sans-serif`
  ///   的策略是一样的 —— 声明优先，没有就用系统的。
  static const String round = 'PingFang SC';

  // ══════════════════════════════════════════════════════════════════
  // 常用文字样式
  // ══════════════════════════════════════════════════════════════════

  /// 页头大字
  static TextStyle get brushHero => TextStyle(
        fontFamily: brush,
        fontSize: 52,
        height: 1.15,
        color: HavenColors.inkStrong,
        fontWeight: FontWeight.w300,
        letterSpacing: 3,
      );

  /// 循环书写的那句话
  static TextStyle get brushLine => TextStyle(
        fontFamily: brush,
        fontSize: 22,
        height: 1.5,
        color: HavenColors.inkSoft,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
      );

  /// 卡片上的日期 / 小字
  static TextStyle get brushOnPaper => TextStyle(
        fontFamily: brush,
        fontSize: 14,
        height: 1.2,
        color: HavenColors.inkFaint,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
      );

  /// 页头那句固定题词
  static TextStyle get heroTagline => TextStyle(
        fontFamily: round,
        fontSize: 14,
        height: 1.6,
        color: HavenColors.inkSoft,
        letterSpacing: 2,
      );

  /// 题词的英文翻译 —— 比中文小一号、更淡，当注解看
  static TextStyle get heroTaglineEn => TextStyle(
        fontFamily: round,
        fontSize: 11.5,
        height: 1.6,
        color: HavenColors.inkFaint,
        letterSpacing: 1.2,
      );

  /// 卡片上的时间 / 日期
  static TextStyle get timeOnPaper => TextStyle(
        fontFamily: round,
        fontSize: 11.5,
        height: 1.35,
        color: HavenColors.inkFaint,
        letterSpacing: 0.4,
      );

  /// 页头大字下方的小字
  static TextStyle get heroNote => TextStyle(
        fontFamily: round,
        fontSize: 12.5,
        height: 1.7,
        color: HavenColors.inkSoft,
        letterSpacing: 0.8,
      );

  /// 按钮 / 标签
  static TextStyle get roundLabel => TextStyle(
        fontFamily: round,
        fontSize: 13,
        height: 1.35,
        color: HavenColors.inkSoft,
        letterSpacing: 1,
      );

  static TextStyle get roundOnInk => TextStyle(
        fontFamily: round,
        fontSize: 13,
        height: 1.35,
        color: HavenColors.inkSoft,
        letterSpacing: 1,
      );

  // ══════════════════════════════════════════════════════════════════
  // 影子
  // ══════════════════════════════════════════════════════════════════

  static List<BoxShadow> paperShadow({double lift = 1}) =>
      HavenColors.glassShadow(lift: lift);
}
