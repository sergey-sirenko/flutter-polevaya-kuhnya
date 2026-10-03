import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primary = Color(0xFF305F3D);
  static const background = Color(0xFFFFFFFF);
  static const text = Color(0xFF223027);
  static const textLight = Color(0xFF626D64);
  static const primaryLight = Color(0xFFF0F5EF);
  static const link = primary;
  static const border = Color(0xFFDCE5DD);
  static const accent = Color(0xFFECAF3F);
  static const accentLight = Color(0xFFFAF4E5);
  static const footer = Color(0xFF28513A);
  static const danger = Color(0xFFB3261E);
  static const radius = BorderRadius.all(Radius.circular(12));
  static const controlSize = Size(44, 44);
  static const _shape = RoundedRectangleBorder(borderRadius: radius);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: primary).copyWith(
      // Общая палитра «Белая кухня»: фото белые, действия зелёные.
      primary: link,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primary,
      secondary: link,
      onSecondary: Colors.white,
      secondaryContainer: primaryLight,
      onSecondaryContainer: text,
      tertiary: accent,
      onTertiary: text,
      tertiaryContainer: accentLight,
      onTertiaryContainer: text,
      surface: background,
      onSurface: text,
      onSurfaceVariant: textLight,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: primaryLight,
      surfaceContainerHigh: primaryLight,
      surfaceContainerHighest: primaryLight,
      surfaceTint: Colors.transparent,
      outline: border,
      outlineVariant: border,
      error: danger,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: background,
    dividerColor: border,
    fontFamily: 'Arial',
    fontFamilyFallback: const ['sans-serif'],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      titleMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      bodySmall: TextStyle(fontSize: 14, height: 1.4),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: controlSize,
        shape: _shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: link,
        minimumSize: controlSize,
        shape: _shape,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: link,
        minimumSize: controlSize,
        shape: _shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: controlSize,
        foregroundColor: text,
        shape: _shape,
      ),
    ),
    cardTheme: const CardThemeData(
      color: background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      errorMaxLines: 4,
      helperMaxLines: 4,
      filled: true,
      fillColor: background,
      contentPadding: EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: link, width: 2),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: _shape,
      backgroundColor: background,
      selectedColor: primaryLight,
      side: BorderSide(color: border),
      labelStyle: TextStyle(
        color: text,
        fontFamily: 'Arial',
        fontFamilyFallback: ['sans-serif'],
        fontSize: 14,
        height: 1.4,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: background,
      indicatorColor: primaryLight,
      selectedIconTheme: IconThemeData(color: link),
      unselectedIconTheme: IconThemeData(color: textLight),
      selectedLabelTextStyle: TextStyle(
        color: link,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(color: textLight),
    ),
  );
}
