/// 应用主题配置 — 纯黑背景 / Material 3 / 深色模式
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── 品牌色（B站风格） ──────────────────────────────────────────────
  /// 主色 — 荧光青
  static const Color primaryColor = Color(0xFF00AEEC);
  /// 强调色 — B站粉
  static const Color accentColor = Color(0xFFFB7299);
  /// 直播警告色
  static const Color liveColor = Color(0xFFFF3B3B);
  /// 警告/提示色
  static const Color warningColor = Color(0xFFFFB800);
  /// 成功色
  static const Color successColor = Color(0xFF34C759);

  // ── 纯色常量 ───────────────────────────────────────────────────────
  /// 纯黑背景
  static const Color backgroundColor = Colors.black;
  /// 表面色（卡片外层）
  static const Color surfaceColor = Color(0xFF121212);
  /// 卡片色
  static const Color cardColor = Color(0xFF1C1C1C);
  /// 底层表面
  static const Color surfaceDimColor = Color(0xFF0A0A0A);

  // ── 文字色 ─────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 70% 白
  static const Color textTertiary = Color(0x66FFFFFF); // 40% 白
  static const Color textDisabled = Color(0x33FFFFFF); // 20% 白

  // ── MD3 ColorScheme（纯黑背景深色） ────────────────────────────────
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundColor,

    // 主色方案 — 以 B站青 / 粉为基准的 Material 3 完整色板
    colorScheme: const ColorScheme.dark(
      // 主色 / 主色容器
      primary: primaryColor,
      onPrimary: Colors.black,
      primaryContainer: Color(0xFF003D52),
      onPrimaryContainer: Color(0xFFB3E8FF),

      // 次要色
      secondary: accentColor,
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF3D0F24),
      onSecondaryContainer: Color(0xFFFFB8CC),

      // 第三色（中性装饰）
      tertiary: warningColor,
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF4A2E00),
      onTertiaryContainer: Color(0xFFFFDEAD),

      // 错误
      error: liveColor,
      onError: Colors.black,
      errorContainer: Color(0xFF410002),
      onErrorContainer: Color(0xFFFFDAD6),

      // 表面 & 背景
      surface: backgroundColor,
      onSurface: textPrimary,
      surfaceVariant: surfaceColor,
      onSurfaceVariant: textSecondary,
      surfaceContainerHighest: cardColor,
      onSurfaceVariant: textSecondary,

      // Outline / 边框
      outline: Color(0x4DFFFFFF),
      outlineVariant: Color(0x1FFFFFFF),

      // 阴影
      shadow: Colors.black,

      // Scrim
      scrim: Colors.black,
    ),

    // ── MD3 全局交互参数 ────────────────────────────────────────────
    // 扩展最小点击区域（48×48pt），符合 MD3 规范
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // 按下时轻微放大，离开时弹性回弹 — MD3 标准弹簧动画
    visualDensity: VisualDensity.adaptivePlatformDensity,

    // ── 组件样式 ────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      toolbarStyle: MaterialStatePropertyAll(
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.transparent],
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          child: Text(
            'glass',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),

    bottomAppBarTheme: const BottomAppBarTheme(
      color: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
    ),

    // FAB — MD3 filled tonal 样式，带弹簧涟漪
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentColor,
      foregroundColor: Colors.black,
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 6,
      pressedElevation: 2,
    ),

    // 按钮 — MD3 filled 样式（带弹簧涟漪）
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.black,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
        ),
      ),
    ),

    // 文本按钮 — MD3 text 样式（透明背景）
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentColor,
        textStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
        ),
      ),
    ),

    // 出填充按钮 — MD3 outlined 样式
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: const BorderSide(color: Color(0x4DFFFFFF), width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1,
        ),
      ),
    ),

    // 图标按钮 — MD3 filled small（40×40 点击区）
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: surfaceColor,
        foregroundColor: textPrimary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.all(12),
      ),
    ),

    // 分类 Tab（SegmentedControl 风格）
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: MaterialStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),

    // 分隔线 — MD3 弱分隔
    dividerTheme: const DividerThemeData(
      color: Color(0x1AFFFFFF),
      thickness: 1,
      space: 1,
    ),

    // 卡片 — MD3 elevated / filled
    cardTheme: CardTheme(
      color: cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),

    // 输入框 — MD3 filled 样式
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textTertiary, fontSize: 14),
    ),

    // 文字主题
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400, height: 1.12, letterSpacing: -0.25),
      displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400, height: 1.16),
      displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400, height: 1.22),
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, height: 1.25),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, height: 1.29),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.33),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.27),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.50),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.43),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.50),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.43),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.67, color: textTertiary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    ),
  );
}