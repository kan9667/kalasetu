import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/motifs/tanka_stitch_painter.dart';

class StepProgressBar extends StatelessWidget {
  final int currentStep; // 0 to 4
  final int totalSteps;
  final ValueChanged<int>? onStepTapped;

  const StepProgressBar({
    super.key,
    required this.currentStep,
    this.totalSteps = 5,
    this.onStepTapped,
  });

  static const List<IconData> _stepIcons = [
    Icons.photo_camera_outlined,
    Icons.mic_none_outlined,
    Icons.auto_awesome_outlined,
    Icons.sell_outlined,
    Icons.cloud_upload_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      alignment: Alignment.center,
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: SizedBox(
                  height: 2,
                  child: isCompleted
                      ? const CustomPaint(
                          painter: TankaStitchPainter(
                            color: AppColors.success,
                            strokeWidth: 2,
                            dashLength: 5,
                            dashGap: 4,
                          ),
                        )
                      : Container(
                          height: 2,
                          color: AppColors.line,
                        ),
                ),
              ),
            );
          } else {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            final isCurrent = stepIndex == currentStep;
            final iconData = stepIndex < _stepIcons.length
                ? _stepIcons[stepIndex]
                : Icons.circle;

            Color bgColor = AppColors.cardSurface;
            Color borderColor = AppColors.line;
            Color iconColor = AppColors.inkFaint;
            List<BoxShadow>? shadows;
            Widget child;

            if (isCompleted) {
              bgColor = AppColors.success;
              borderColor = AppColors.success;
              iconColor = Colors.white;
              child = const Icon(Icons.check, size: 16, color: Colors.white);
            } else if (isCurrent) {
              bgColor = AppColors.terracotta;
              borderColor = AppColors.terracotta;
              iconColor = Colors.white;
              shadows = const [
                BoxShadow(
                  color: AppColors.terracottaLight,
                  spreadRadius: 4,
                  blurRadius: 0,
                ),
              ];
              child = Icon(iconData, size: 16, color: Colors.white);
            } else {
              child = Icon(iconData, size: 16, color: iconColor);
            }

            return GestureDetector(
              onTap: onStepTapped != null ? () => onStepTapped!(stepIndex) : null,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: shadows,
                ),
                alignment: Alignment.center,
                child: child,
              ),
            );
          }
        }),
      ),
    );
  }
}