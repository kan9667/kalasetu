import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';

class StepProgressBar extends StatelessWidget {
  final int currentStep;
  final Function(int) onStepTapped;

  const StepProgressBar({
    super.key,
    required this.currentStep,
    required this.onStepTapped,
  });

  static const List<String> _stepKeys = [
    'step_capture',
    'step_describe',
    'step_ai_review',
    'step_pricing',
    'step_confirm',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(_stepKeys.length * 2 - 1, (index) {
              if (index.isOdd) {
                final stepIndex = index ~/ 2;
                final isCompleted = stepIndex < currentStep;
                return Expanded(
                  child: Container(
                    height: 3,
                    color: isCompleted ? AppColors.terracotta : AppColors.divider,
                  ),
                );
              }

              final stepIndex = index ~/ 2;
              final isActive = stepIndex == currentStep;
              final isCompleted = stepIndex < currentStep;

              return GestureDetector(
                onTap: () {
                  if (stepIndex <= currentStep) {
                    onStepTapped(stepIndex);
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.terracotta
                        : (isCompleted ? AppColors.forestGreen : AppColors.surfaceVariant),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive
                          ? AppColors.terracotta
                          : (isCompleted ? AppColors.forestGreen : AppColors.border),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 16, color: AppColors.textOnPrimary)
                        : Text(
                            '${stepIndex + 1}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isActive ? AppColors.textOnPrimary : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _stepKeys[currentStep].tr(),
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.terracottaDark,
            ),
          ),
        ],
      ),
    );
  }
}
