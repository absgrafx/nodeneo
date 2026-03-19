import 'package:flutter/material.dart';

class RedPillTheme {
  static const _bg = Color(0xFF030712);
  static const _surface = Color(0xFF111827);
  static const _surfaceLight = Color(0xFF1E293B);
  static const _green = Color(0xFF22C55E);
  static const _greenDark = Color(0xFF052E16);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _textPrimary = Color(0xFFF9FAFB);
  static const _textSecondary = Color(0xFF9CA3AF);
  static const _textMuted = Color(0xFF6B7280);

  static const green = _green;
  static const greenDark = _greenDark;
  static const amber = _amber;
  static const red = _red;
  static const surface = _surface;
  static const surfaceLight = _surfaceLight;

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bg,
    colorScheme: const ColorScheme.dark(
      primary: _green,
      secondary: _amber,
      surface: _surface,
      error: _red,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: _textPrimary,
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      foregroundColor: _textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _textSecondary,
        side: const BorderSide(color: _surfaceLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _surfaceLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _surfaceLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _green, width: 1.5),
      ),
      hintStyle: const TextStyle(color: _textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w800, fontSize: 28),
      headlineMedium: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
      titleLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      titleMedium: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
      bodyLarge: TextStyle(color: _textPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: _textSecondary, fontSize: 14),
      bodySmall: TextStyle(color: _textMuted, fontSize: 12),
      labelSmall: TextStyle(color: _textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2),
    ),
  );
}
