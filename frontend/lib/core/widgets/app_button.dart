import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

enum AppButtonType { primary, secondary, outlined, text }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonType type;
  final bool isLoading;
  final Color? customColor;
  final double? width;
  final double? height;
  final bool isCompact;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.type = AppButtonType.primary,
    this.isLoading = false,
    this.customColor,
    this.width,
    this.height,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final minButtonHeight = height ?? AppSpacing.minTouchTarget;

    if (isLoading) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: width ?? (type == AppButtonType.text ? 0.0 : double.infinity),
          minHeight: minButtonHeight,
        ),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: type == AppButtonType.primary
                  ? AppColors.textOnPrimary
                  : (customColor ?? AppColors.terracotta),
            ),
          ),
        ),
      );
    }

    final TextStyle baseTextStyle = isCompact
        ? AppTextStyles.labelMedium
        : AppTextStyles.labelLarge;

    final EdgeInsets padding = EdgeInsets.symmetric(
      horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
      vertical: isCompact ? AppSpacing.sm : AppSpacing.md,
    );

    Widget buildButtonChild({required Color textColor, required Color iconColor}) {
      if (icon == null) {
        return Text(
          label,
          textAlign: TextAlign.center,
          style: baseTextStyle.copyWith(color: textColor, height: 1.2),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: isCompact ? 18 : AppSpacing.iconSize, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: baseTextStyle.copyWith(color: textColor, height: 1.2),
            ),
          ),
        ],
      );
    }

    Widget button;

    switch (type) {
      case AppButtonType.primary:
        final Color bgColor = customColor ?? AppColors.terracotta;
        final Color fgColor = AppColors.textOnPrimary;
        button = ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: fgColor,
            elevation: 0,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: buildButtonChild(textColor: fgColor, iconColor: fgColor),
        );
        break;

      case AppButtonType.secondary:
        final Color bgColor = customColor ?? AppColors.charcoal;
        final Color fgColor = AppColors.textOnPrimary;
        button = ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: fgColor,
            elevation: 0,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: buildButtonChild(textColor: fgColor, iconColor: fgColor),
        );
        break;

      case AppButtonType.outlined:
        final Color fgColor = customColor ?? AppColors.charcoal;
        button = OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fgColor,
            side: BorderSide(color: customColor ?? AppColors.oak, width: 1.5),
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: buildButtonChild(textColor: fgColor, iconColor: fgColor),
        );
        break;

      case AppButtonType.text:
        final Color fgColor = customColor ?? AppColors.terracotta;
        button = TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: fgColor,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: buildButtonChild(textColor: fgColor, iconColor: fgColor),
        );
        break;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: width ?? (type == AppButtonType.text ? 0.0 : double.infinity),
        minHeight: type == AppButtonType.text ? 0.0 : minButtonHeight,
      ),
      child: button,
    );
  }
}