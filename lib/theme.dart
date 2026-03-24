import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Morpheus / Marketplace-aligned palette (`Morpheus-Marketplace-APP` globals.css).
///
/// Brand: `--matrix-green`, `--eclipse`, `--neon-mint`, `--emerald`, `--midnight`, `--platinum`.
class RedPillTheme {
  /// #0C0C0C — main scaffold / near-black
  static const midnight = Color(0xFF0C0C0C);

  /// Home list cards (wallet, models, resume, privacy): solid black + outline only.
  static const mainPanelFill = midnight;

  /// Default emerald outline for [mainPanelFill] panels.
  static Color mainPanelOutline([double opacity = 0.42]) => emerald.withValues(alpha: opacity);

  /// #03160E — deep green-black (fills, selected chips)
  static const matrixGreen = Color(0xFF03160E);

  /// #1C302F — cards / elevated surfaces (“eclipse”)
  static const eclipse = Color(0xFF1C302F);

  /// #00FF85 — high-contrast accent (use sparingly)
  static const neonMint = Color(0xFF00FF85);

  /// #20DC8E — primary brand green (buttons, links, focus)
  static const emerald = Color(0xFF20DC8E);

  /// #EBEBEB — primary text on dark
  static const platinum = Color(0xFFEBEBEB);

  // --- Aliases used across the app (keep existing names) ---
  static const green = emerald;
  static const greenDark = matrixGreen;
  static const surface = eclipse;
  /// Slightly lifted surface for nested chips / borders
  static const surfaceLight = Color(0xFF243836);

  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  static const _textSecondary = Color(0xFF9CA3AF);
  static const _textMuted = Color(0xFF6B7280);

  static ThemeData get dark {
    final baseDark = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(baseDark.textTheme).apply(
      bodyColor: platinum,
      displayColor: platinum,
    );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: midnight,
      colorScheme: ColorScheme.dark(
        primary: emerald,
        onPrimary: midnight,
        primaryContainer: matrixGreen,
        onPrimaryContainer: emerald,
        secondary: neonMint,
        onSecondary: midnight,
        surface: eclipse,
        onSurface: platinum,
        surfaceContainerHighest: matrixGreen,
        error: red,
        onError: platinum,
        outline: surfaceLight,
        outlineVariant: const Color(0xFF374151),
      ).copyWith(surfaceTint: Colors.transparent),
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 28),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 22),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15, color: platinum),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, color: _textSecondary),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, color: _textMuted),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _textMuted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: midnight,
        foregroundColor: platinum,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: platinum,
        ),
        iconTheme: const IconThemeData(color: platinum),
      ),
      cardTheme: CardThemeData(
        color: eclipse,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: midnight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: midnight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _textSecondary,
          side: const BorderSide(color: surfaceLight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: eclipse,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: emerald, width: 2),
        ),
        hintStyle: const TextStyle(color: _textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: matrixGreen,
        contentTextStyle: GoogleFonts.inter(color: platinum, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: emerald.withValues(alpha: 0.35)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: emerald),
    );
  }
}
