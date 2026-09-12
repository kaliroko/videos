/// 应用主题配置 — 深色 B站风格
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // 主色调 - B站粉
  static const Color primaryColor = Color(0xFF00AEEC);
  static const Color accentColor = Color(0xFFFB7299);

  // 背景
  static const Color backgroundColor = Color(0xFF0F0F0F);
  static const Color surfaceColor = Color(0xFF1A1A1A);
  static const Color cardColor = Color(0xFF242424);

  // 文字
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textTertiary = Color(0x66FFFFFF);

  // 状态色
  static const Color successColor = Color(0xFF00AEEC);
  static const Color warningColor = Color(0xFFFFB800);
  static const Color liveColor = Color(0xFFFF3B3B);

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: backgroundColor,
    primaryColor: primaryColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: accentColor,
      surface: surfaceColor,
      onSurface: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: primaryColor,
      unselectedItemColor: textTertiary,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x1AFFFFFF),
      thickness: 1,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
      bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary),
      bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: textSecondary),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: textTertiary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
    ),
  );
}
