import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Kalasetu v3 typography tokens.
///
/// Display font : Fraunces (variable OTF) — serif, warm, expressive.
///   At display/headline sizes use opsz ≈ 9 (smaller optical size = more expressive
///   "swash" character that reads more playfully at large sizes — opposite of most
///   fonts; see Fraunces specimen).  At smaller UI headings use opsz ≈ 36.
///
/// Body/UI font : Manrope (variable TTF) — geometric sans, clean, legible.
///   All body, label, caption, and overline styles.
///
/// Both fonts are bundled as assets — safe for offline/zero-connectivity use.
class AppTextStyles {
  // --- Fraunces helpers ---
  static const _fraunces = 'Fraunces';

  /// Fraunces at "expressive" display opsz (9 = most swashy)
  static List<FontVariation> _displayOpsz(double opsz) =>
      [FontVariation('opsz', opsz)];

  // ---------------------------------------------------------------------------
  // Display  — Fraunces, large, opsz=9 (expressive optical size)
  // ---------------------------------------------------------------------------
  static TextStyle displayLarge = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(9),
    fontSize: 36,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle displayMedium = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(9),
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static TextStyle displaySmall = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(9),
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  // ---------------------------------------------------------------------------
  // Headline — Fraunces, opsz=36 (slightly less expressive for smaller headings)
  // ---------------------------------------------------------------------------
  static TextStyle headlineLarge = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(36),
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineMedium = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(36),
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineSmall = TextStyle(
    fontFamily: _fraunces,
    fontVariations: _displayOpsz(36),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  // ---------------------------------------------------------------------------
  // Body — Manrope, regular
  // ---------------------------------------------------------------------------
  static const _manrope = 'Manrope';

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _manrope,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _manrope,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _manrope,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  // ---------------------------------------------------------------------------
  // Labels — Manrope, bold, high contrast for buttons, tabs, chips
  // ---------------------------------------------------------------------------
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _manrope,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: _manrope,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.25,
    color: AppColors.textPrimary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------
  static const TextStyle caption = TextStyle(
    fontFamily: _manrope,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textTertiary,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: _manrope,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.5,
    color: AppColors.textSecondary,
  );

  AppTextStyles._();
}