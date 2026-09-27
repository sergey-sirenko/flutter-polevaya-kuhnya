import 'package:flutter/material.dart';

abstract final class AppTheme {
  // Значения из css/variables/_colors.css действующего сайта.
  static const primary = Color(0xFFB8572A);
  static const background = Color(0xFFFAF8F5);
  static const text = Color(0xFF4A3429);
  static const textLight = Color(0xFF6B5349);
  static const primaryLight = Color(0xFFF4EDE8);
  static const gold = Color(0xFFD4A865);
  static const border = Color(0xFFE8E0D8);
  static const danger = Color(0xFFA84442);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: primary).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: gold,
      onSecondary: text,
      surface: background,
      onSurface: text,
      onSurfaceVariant: textLight,
      surfaceContainerLow: Colors.white,
      surfaceContainerHighest: primaryLight,
      outline: border,
      error: danger,
    ),
    scaffoldBackgroundColor: background,
    dividerColor: border,
    // Сайт использует Arial, sans-serif; системный sans-serif — запасной шрифт.
    fontFamily: 'Arial',
    fontFamilyFallback: const ['sans-serif'],
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.6),
      bodyMedium: TextStyle(fontSize: 14.4, height: 1.6),
    ),
  );
}
