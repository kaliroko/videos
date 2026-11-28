/// 全局 Material 主题 —— 由 Her Haven 设计令牌驱动
///
/// ★ 这个文件原来是「B站青 / B站粉 / 纯黑」那一套。现在整包换成
///   网页《Her Haven · 私密乌托邦》的暗玻璃玫瑰语言：
///     底  #0D0A10  玻璃 #16111A  玫瑰 #D17997  薰衣草 #8E7BB5
///   真值在 `theme/haven.dart`，这里只负责把它们翻译成 Material 3 的槽位。
///
/// ★ 字段名一个都没改（primaryColor / accentColor / cardColor …）。
///   视频流、停服页、公告弹窗这些老界面引用了它们 60 多次，
///   改值不改名 → 一行调用点都不用动，整包跟着换肤。
///
/// ★ 字体：
///   标题类（display / headline / title）走打包进来的 Noto Serif SC 子集，
///   正文与控件走系统无衬线（声明 'PingFang SC'，Android 上优雅回退）。
///   用户输入的正文不会被衬线体渲染 —— 子集不含用户字，会混排。
library;

import 'package:flutter/material.dart';

import 'haven.dart';

class AppTheme {
  AppTheme._();

  // ── 品牌色 ─────────────────────────────────────────────────────────
  /// 主色 —— 玫瑰（网页 --rose: #D17997）
  static const Color primaryColor = Color(0xFFD17997);
  /// 强调色 —— 与主色同源，保留旧名字给老界面用
  static const Color accentColor = Color(0xFFD17997);
  /// 第二强调色 —— 薰衣草（网页 --lavender: #8E7BB5）
  static const Color lavenderColor = Color(0xFF8E7BB5);
  /// 危险 / 直播（网页里用玫瑰深一档）
  static const Color liveColor = Color(0xFFE05C7A);
  /// 警告 / 提示
  static const Color warningColor = Color(0xFFE0A85C);
  /// 成功
  static const Color successColor = Color(0xFF5FB878);

  // ── 底色 ───────────────────────────────────────────────────────────
  /// 页面底（网页 --bg-base）
  static const Color backgroundColor = Color(0xFF0D0A10);
  /// 表面（比底色亮一档：底栏、输入区）
  static const Color surfaceColor = Color(0xFF16111A);
  /// 卡片（玻璃底下那一层实色）
  static const Color cardColor = Color(0xFF1A1420);
  /// 更深的底
  static const Color surfaceDimColor = Color(0xFF0A070D);

  // ── 文字色 ─────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3EAE5ED);
  static const Color textTertiary = Color(0x66EAE5ED);
  static const Color textDisabled = Color(0x33EAE5ED);

  // ── 形状 ───────────────────────────────────────────────────────────
  static const double _radiusCard = 12;
  static const double _radiusField = 8;
  static const double _radiusButton = 4;

  // ══════════════════════════════════════════════════════════════════
  // 深色
  // ══════════════════════════════════════════════════════════════════

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundColor,
    canvasColor: backgroundColor,
    fontFamily: 'PingFang SC',

    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF4A2233),
      onPrimaryContainer: Color(0xFFFFD9E5),

      secondary: lavenderColor,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF362C4A),
      onSecondaryContainer: Color(0xFFE4DBFF),

      tertiary: warningColor,
      onTertiary: Color(0xFF2A1B00),
      tertiaryContainer: Color(0xFF4A2E00),
      onTertiaryContainer: Color(0xFFFFDEAD),

      error: liveColor,
      onError: Colors.white,
      errorContainer: Color(0xFF410002),
      onErrorContainer: Color(0xFFFFDAD6),

      surface: backgroundColor,
      onSurface: Color(0xFFFFFFFF),
      surfaceContainerHighest: cardColor,
      onSurfaceVariant: textSecondary,

      outline: Color(0x4DFFFFFF),
      outlineVariant: Color(0x1FFFFFFF),

      shadow: Colors.black,
      scrim: Colors.black,
    ),

    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.adaptivePlatformDensity,

    // 网页所有视图切换都是 fadeUp，这里让路由也跟着淡入上移
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSerifSC',
        fontSize: 20,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
        color: textPrimary,
      ),
    ),

    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 6,
      shape: CircleBorder(),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x33D17997),
        disabledForegroundColor: textDisabled,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusButton),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: Color(0x4DFFFFFF), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusButton),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(12),
      ),
    ),

    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0x0FFFFFFF),
      thickness: 1,
      space: 1,
    ),

    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusCard),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x14FFFFFF)),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'NotoSerifSC',
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
        color: textPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        fontSize: 13.5,
        height: 1.7,
        color: textSecondary,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalBackgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFFC06A86),
      contentTextStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        fontSize: 13,
        letterSpacing: 1,
        color: Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x1A000000),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        color: textTertiary,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: Color(0x0FFFFFFF), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: Color(0x0FFFFFFF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: primaryColor, width: 1),
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 48, fontWeight: FontWeight.w300, height: 1.2, letterSpacing: 2, color: textPrimary),
      displayMedium: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 40, fontWeight: FontWeight.w300, height: 1.25, letterSpacing: 2, color: textPrimary),
      displaySmall: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 34, fontWeight: FontWeight.w300, height: 1.3, letterSpacing: 2, color: textPrimary),
      headlineLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 28, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 2, color: textPrimary),
      headlineMedium: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 24, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 2, color: textPrimary),
      headlineSmall: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 21, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 1.5, color: textPrimary),
      titleLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 19, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 1, color: textPrimary),
      titleMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 15, fontWeight: FontWeight.w500, height: 1.5, letterSpacing: 0.5, color: textPrimary),
      titleSmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5, letterSpacing: 0.5, color: textPrimary),
      bodyLarge: TextStyle(fontFamily: 'PingFang SC', fontSize: 15, fontWeight: FontWeight.w400, height: 1.75, letterSpacing: 0.3, color: Color(0xFFEAE5ED)),
      bodyMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.8, letterSpacing: 0.3, color: Color(0xFFEAE5ED)),
      bodySmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 12, fontWeight: FontWeight.w400, height: 1.7, letterSpacing: 0.4, color: textTertiary),
      labelLarge: TextStyle(fontFamily: 'PingFang SC', fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1),
      labelMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 1),
      labelSmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 11, fontWeight: FontWeight.w400, letterSpacing: 1),
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  // 浅色 —— 同一套语言的「日光玻璃」
  // ══════════════════════════════════════════════════════════════════

  static const Color lightBackgroundColor = Color(0xFFF6F2F5);
  static const Color lightSurfaceColor = Color(0xFFFFFFFF);
  static const Color lightCardColor = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1C1620);
  static const Color lightTextSecondary = Color(0xB31C1620);
  static const Color lightTextTertiary = Color(0x8A1C1620);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBackgroundColor,
    canvasColor: lightBackgroundColor,
    fontFamily: 'PingFang SC',

    colorScheme: const ColorScheme.light(
      primary: Color(0xFFB04264),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFF7D9E2),
      onPrimaryContainer: Color(0xFF3E0C1C),

      secondary: Color(0xFF6B5A8E),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE7E0F5),
      onSecondaryContainer: Color(0xFF241B36),

      tertiary: Color(0xFF8A6420),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF5E4C4),
      onTertiaryContainer: Color(0xFF2C1F00),

      error: Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),

      surface: lightBackgroundColor,
      onSurface: lightTextPrimary,
      surfaceContainerHighest: lightCardColor,
      onSurfaceVariant: lightTextSecondary,

      outline: Color(0x331C1620),
      outlineVariant: Color(0x1A1C1620),

      shadow: Colors.black,
      scrim: Colors.black,
    ),

    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.adaptivePlatformDensity,

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: lightTextPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSerifSC',
        fontSize: 20,
        fontWeight: FontWeight.w300,
        letterSpacing: 2,
        color: lightTextPrimary,
      ),
    ),

    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFFB04264),
      foregroundColor: Colors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFB04264),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusButton),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFB04264),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightTextPrimary,
        side: const BorderSide(color: Color(0x331C1620), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusButton),
        ),
        textStyle: const TextStyle(
          fontFamily: 'PingFang SC',
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: lightTextPrimary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(12),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0x141C1620),
      thickness: 1,
      space: 1,
    ),

    cardTheme: CardThemeData(
      color: lightCardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radiusCard),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: lightCardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x141C1620)),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'NotoSerifSC',
        fontSize: 18,
        fontWeight: FontWeight.w300,
        letterSpacing: 1,
        color: lightTextPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        fontSize: 13.5,
        height: 1.7,
        color: Color(0xFF443B4E),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: lightCardColor,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: lightCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF3A2B36),
      contentTextStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        fontSize: 13,
        letterSpacing: 1,
        color: Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x0A1C1620),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(
        fontFamily: 'PingFang SC',
        color: lightTextTertiary,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: Color(0x141C1620), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: Color(0x141C1620), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radiusField),
        borderSide: const BorderSide(color: Color(0xFFB04264), width: 1),
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 48, fontWeight: FontWeight.w300, height: 1.2, letterSpacing: 2, color: lightTextPrimary),
      displayMedium: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 40, fontWeight: FontWeight.w300, height: 1.25, letterSpacing: 2, color: lightTextPrimary),
      displaySmall: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 34, fontWeight: FontWeight.w300, height: 1.3, letterSpacing: 2, color: lightTextPrimary),
      headlineLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 28, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 2, color: lightTextPrimary),
      headlineMedium: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 24, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 2, color: lightTextPrimary),
      headlineSmall: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 21, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 1.5, color: lightTextPrimary),
      titleLarge: TextStyle(fontFamily: 'NotoSerifSC', fontSize: 19, fontWeight: FontWeight.w300, height: 1.4, letterSpacing: 1, color: lightTextPrimary),
      titleMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 15, fontWeight: FontWeight.w500, height: 1.5, letterSpacing: 0.5, color: lightTextPrimary),
      titleSmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5, letterSpacing: 0.5, color: lightTextPrimary),
      bodyLarge: TextStyle(fontFamily: 'PingFang SC', fontSize: 15, fontWeight: FontWeight.w400, height: 1.75, letterSpacing: 0.3, color: lightTextPrimary),
      bodyMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.8, letterSpacing: 0.3, color: lightTextPrimary),
      bodySmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 12, fontWeight: FontWeight.w400, height: 1.7, letterSpacing: 0.4, color: lightTextTertiary),
      labelLarge: TextStyle(fontFamily: 'PingFang SC', fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1),
      labelMedium: TextStyle(fontFamily: 'PingFang SC', fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 1),
      labelSmall: TextStyle(fontFamily: 'PingFang SC', fontSize: 11, fontWeight: FontWeight.w400, letterSpacing: 1),
    ),
  );

  // ══════════════════════════════════════════════════════════════════
  // 给新模块用的小工具
  // ══════════════════════════════════════════════════════════════════

  /// 跟随当前明暗模式的玫瑰色 —— 新界面不要写死 0xFFD17997
  static Color get rose => HavenColors.rose;

  /// 跟随当前明暗模式的正文色
  static Color get ink => HavenColors.ink;

  /// 跟随当前明暗模式的底色
  static Color get surfaceOf => HavenColors.bg;
}
