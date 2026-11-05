import 'package:flutter/material.dart';

/// Visual direction from PLAN.md §5.1: a restrained navy palette with bright
/// accent colours for turn ownership and attack feedback.
class AppTheme {
  const AppTheme._();

  /// Deep ocean navy used for the app background.
  static const Color background = Color(0xFF0B1B2B);

  /// Slightly lighter navy used for surfaces and cards.
  static const Color surface = Color(0xFF14293D);

  /// Border colour for surfaces.
  static const Color surfaceBorder = Color(0xFF1E3A52);

  /// Primary text colour.
  static const Color textPrimary = Color(0xFFF2F7FB);

  /// Secondary text colour.
  static const Color textSecondary = Color(0xFF9DB4C8);

  /// Accent used for the active player and primary actions.
  static const Color accent = Color(0xFF3DD6C4);

  /// Accent used for a confirmed hit.
  static const Color hit = Color(0xFFFF6B5B);

  /// Accent used for a miss.
  static const Color miss = Color(0xFF7FA5C4);

  /// Accent used for a sunk ship.
  static const Color sunk = Color(0xFFFFB547);

  /// Colour used for destructive or abort states.
  static const Color danger = Color(0xFFE4572E);

  /// Builds the dark theme used by the whole application.
  static ThemeData dark() {
    final ColorScheme scheme = const ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF04241F),
      secondary: sunk,
      onSecondary: Color(0xFF2A1A00),
      error: danger,
      onError: Color(0xFF2A0B04),
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: surfaceBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF04241F),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: surfaceBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: surfaceBorder),
        labelStyle: TextStyle(color: textPrimary),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelSmall: TextStyle(color: textSecondary),
      ),
    );
  }
}
