import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typography system with distinctive type pairing:
/// - Warm serif/slab-serif for headings (product/brand feel)
/// - Humanist sans for body/UI (accessibility for low-literacy users)
class AppTextStyles {
  // Headings - Zilla Slab (warm serif, craft-inspired)
  static TextStyle displayLarge = GoogleFonts.zillaSlab(
    fontSize: 36,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle displayMedium = GoogleFonts.zillaSlab(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static TextStyle displaySmall = GoogleFonts.zillaSlab(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineLarge = GoogleFonts.zillaSlab(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineMedium = GoogleFonts.zillaSlab(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static TextStyle headlineSmall = GoogleFonts.zillaSlab(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  // Body & UI - Nunito Sans (highly legible humanist sans)
  static TextStyle bodyLarge = GoogleFonts.nunitoSans(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium = GoogleFonts.nunitoSans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle bodySmall = GoogleFonts.nunitoSans(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  // Labels - bold, high contrast for buttons and tabs
  static TextStyle labelLarge = GoogleFonts.nunitoSans(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.3,
    color: AppColors.textPrimary,
  );

  static TextStyle labelMedium = GoogleFonts.nunitoSans(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.25,
    color: AppColors.textPrimary,
  );

  static TextStyle labelSmall = GoogleFonts.nunitoSans(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  // Utility
  static TextStyle caption = GoogleFonts.nunitoSans(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textTertiary,
  );

  static TextStyle overline = GoogleFonts.nunitoSans(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.5,
    color: AppColors.textSecondary,
  );

  AppTextStyles._();
}
