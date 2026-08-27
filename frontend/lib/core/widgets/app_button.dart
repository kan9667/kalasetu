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
    final buttonHeight = height ?? (isCompact ? 40.0 : AppSpacing.minTouchTarget);

    if (isLoading) {
      return SizedBox(
        width: width ?? double.infinity,
        height: buttonHeight,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: type == AppButtonType.primary
                  ? AppColors.terracotta
                  : AppColors.indigo,
            ),
          ),
        ),
      );
    }

    Widget button;
    final textStyle = isCompact
        ? AppTextStyles.labelMedium.copyWith(color: AppColors.textOnPrimary)
        : AppTextStyles.labelLarge.copyWith(color: AppColors.textOnPrimary);

    switch (type) {
      case AppButtonType.primary:
        if (icon != null) {
          button = ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: isCompact ? 18 : AppSpacing.iconSize),
            label: Text(
              label,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: customColor ?? AppColors.terracotta,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
          );
        } else {
          button = ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: customColor ?? AppColors.terracotta,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
            child: Text(
              label,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }
        break;

      case AppButtonType.secondary:
        final secondaryTextStyle = textStyle.copyWith(color: AppColors.textOnPrimary);
        if (icon != null) {
          button = ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: isCompact ? 18 : AppSpacing.iconSize),
            label: Text(
              label,
              style: secondaryTextStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: customColor ?? AppColors.indigo,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
          );
        } else {
          button = ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: customColor ?? AppColors.indigo,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
            child: Text(
              label,
              style: secondaryTextStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }
        break;

      case AppButtonType.outlined:
        final outlinedTextStyle = textStyle.copyWith(
          color: customColor ?? AppColors.terracotta,
        );
        if (icon != null) {
          button = OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: isCompact ? 18 : AppSpacing.iconSize, color: customColor ?? AppColors.terracotta),
            label: Text(
              label,
              style: outlinedTextStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: customColor ?? AppColors.terracotta,
              side: BorderSide(color: customColor ?? AppColors.terracotta, width: 1.8),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
          );
        } else {
          button = OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: customColor ?? AppColors.terracotta,
              side: BorderSide(color: customColor ?? AppColors.terracotta, width: 1.8),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
                vertical: isCompact ? AppSpacing.xs : AppSpacing.md,
              ),
            ),
            child: Text(
              label,
              style: outlinedTextStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }
        break;

      case AppButtonType.text:
        final textButtonStyle = AppTextStyles.labelMedium.copyWith(
          color: customColor ?? AppColors.terracotta,
        );
        if (icon != null) {
          button = TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: isCompact ? 18 : AppSpacing.iconSize),
            label: Text(
              label,
              style: textButtonStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        } else {
          button = TextButton(
            onPressed: onPressed,
            child: Text(
              label,
              style: textButtonStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }
        break;
    }

    return SizedBox(
      width: width ?? (type == AppButtonType.text ? null : double.infinity),
      height: type == AppButtonType.text ? null : buttonHeight,
      child: button,
    );
  }
}
