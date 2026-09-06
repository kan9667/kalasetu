import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// Standard confirmation dialog following the KalaSetu design system.
///
/// Features a stacked button layout:
///   1. Primary action button (full width on top)
///   2. Cancel button (centered directly below, matching width)
class AppConfirmationDialog extends StatelessWidget {
  final String title;
  final Widget? contentWidget;
  final String? message;
  final IconData? icon;
  final Color? iconColor;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final Color? confirmColor;
  final bool isDestructive;
  final bool isLoading;

  const AppConfirmationDialog({
    super.key,
    required this.title,
    this.contentWidget,
    this.message,
    this.icon,
    this.iconColor,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel,
    this.onCancel,
    this.confirmColor,
    this.isDestructive = false,
    this.isLoading = false,
  }) : assert(contentWidget != null || message != null, 'Provide either message or contentWidget');

  @override
  Widget build(BuildContext context) {
    final effectiveCancelLabel = cancelLabel ?? 'cancel'.tr();
    final effectiveConfirmColor = confirmColor ?? (isDestructive ? AppColors.brick : AppColors.terracotta);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Optional Icon
            if (icon != null) ...[
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (iconColor ?? effectiveConfirmColor).withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: iconColor ?? effectiveConfirmColor,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Title
            Text(
              title,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 19),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),

            // Content or Message
            if (message != null)
              Text(
                message!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ?contentWidget,

            const SizedBox(height: AppSpacing.lg),

            // Stacked Actions: Primary Confirm on Top
            AppButton(
              label: confirmLabel,
              customColor: effectiveConfirmColor,
              isLoading: isLoading,
              onPressed: onConfirm,
            ),
            const SizedBox(height: AppSpacing.xs),

            // Cancel Button: Centered directly below primary button
            SizedBox(
              width: double.infinity,
              height: AppSpacing.minTouchTarget,
              child: TextButton(
                onPressed: onCancel ?? () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                ),
                child: Text(
                  effectiveCancelLabel,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience helper to show an [AppConfirmationDialog].
Future<bool?> showAppConfirmationDialog({
  required BuildContext context,
  required String title,
  String? message,
  Widget? contentWidget,
  IconData? icon,
  Color? iconColor,
  required String confirmLabel,
  required VoidCallback onConfirm,
  String? cancelLabel,
  VoidCallback? onCancel,
  Color? confirmColor,
  bool isDestructive = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppConfirmationDialog(
      title: title,
      message: message,
      contentWidget: contentWidget,
      icon: icon,
      iconColor: iconColor,
      confirmLabel: confirmLabel,
      onConfirm: onConfirm,
      cancelLabel: cancelLabel,
      onCancel: onCancel,
      confirmColor: confirmColor,
      isDestructive: isDestructive,
    ),
  );
}
