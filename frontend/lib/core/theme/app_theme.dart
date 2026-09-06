import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_spacing.dart';

/// Centralized ThemeData for Kalasetu v3
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color scheme — v3 palette
      colorScheme: ColorScheme.light(
        primary:            AppColors.terracotta,
        onPrimary:          AppColors.textOnPrimary,
        primaryContainer:   AppColors.terracottaLight,
        onPrimaryContainer: AppColors.terracottaDark,

        secondary:            AppColors.gold,
        onSecondary:          AppColors.textOnPrimary,
        secondaryContainer:   AppColors.goldLight,
        onSecondaryContainer: AppColors.goldDark,

        tertiary:             AppColors.berry,      // accent — rarely used
        onTertiary:           AppColors.textOnPrimary,
        tertiaryContainer:    AppColors.berryLight,
        onTertiaryContainer:  AppColors.berryDark,

        error:    AppColors.terracottaDark,
        onError:  AppColors.textOnPrimary,

        surface:                   AppColors.cardSurface,
        onSurface:                 AppColors.textPrimary,
        surfaceContainerHighest:   AppColors.parchmentDeep,

        outline:        AppColors.dottedBorder,
        outlineVariant: AppColors.line,
        shadow:         AppColors.shadow,
      ),

      scaffoldBackgroundColor: AppColors.parchment,

      // Typography — Fraunces + Manrope (bundled assets, no GoogleFonts)
      textTheme: TextTheme(
        displayLarge:   AppTextStyles.displayLarge,
        displayMedium:  AppTextStyles.displayMedium,
        displaySmall:   AppTextStyles.displaySmall,
        headlineLarge:  AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        headlineSmall:  AppTextStyles.headlineSmall,
        bodyLarge:      AppTextStyles.bodyLarge,
        bodyMedium:     AppTextStyles.bodyMedium,
        bodySmall:      AppTextStyles.bodySmall,
        labelLarge:     AppTextStyles.labelLarge,
        labelMedium:    AppTextStyles.labelMedium,
        labelSmall:     AppTextStyles.labelSmall,
      ),

      // AppBar — flat parchment background
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.parchment,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.headlineMedium,
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
          size: AppSpacing.iconSize,
        ),
      ),

      // Card — warm shadow instead of border
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: AppColors.line, width: 1),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.sm,
        ),
      ),

      // Elevated Button — primary action: terracotta pill with inset shadow
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: AppTextStyles.labelLarge,
        ),
      ),

      // Outlined Button — card surface bg, line border, ink text — pill
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardSurface,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          side: BorderSide(color: AppColors.line, width: 1.5),
          textStyle: AppTextStyles.labelLarge,
        ),
      ),

      // Text Button — ghost / link style
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.terracotta,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: AppTextStyles.labelMedium,
        ),
      ),

      // Input Decoration — card surface, line border, terracotta focus ring
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.inputField),
          borderSide: BorderSide(color: AppColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.inputField),
          borderSide: BorderSide(color: AppColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.inputField),
          borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.inputField),
          borderSide: const BorderSide(color: AppColors.terracottaDark, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.inputField),
          borderSide: const BorderSide(color: AppColors.terracottaDark, width: 2),
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.terracottaDark),
      ),

      // Chip — pill shape; selected = terracotta fill
      // NOTE: cascades globally — accepted risk per design brief.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.parchmentDeep,
        selectedColor: AppColors.terracotta,
        disabledColor: AppColors.parchmentDeep,
        labelStyle: AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary),
        secondaryLabelStyle: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textOnPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
          side: BorderSide(color: AppColors.line, width: 1.5),
        ),
        elevation: 0,
        pressElevation: 0,
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardSurface,
        selectedItemColor: AppColors.terracotta,
        unselectedItemColor: AppColors.inkFaint,
        selectedLabelStyle: AppTextStyles.labelSmall,
        unselectedLabelStyle: AppTextStyles.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.terracotta,
        foregroundColor: AppColors.textOnPrimary,
        elevation: AppElevation.subtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: AppTextStyles.headlineMedium,
        contentTextStyle: AppTextStyles.bodyMedium,
      ),

      // Bottom Sheet — the MehrabClipper replaces the plain rounded rect in
      // packaging_suggestions_sheet.dart; this theme applies to all other sheets.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.cardSurface,
        modalBackgroundColor: AppColors.cardSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.bottomSheet),
          ),
        ),
        modalElevation: 0,
        shadowColor: AppColors.shadowLifted,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle:
            AppTextStyles.bodyMedium.copyWith(color: AppColors.textOnPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.terracotta,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
    );
  }
}