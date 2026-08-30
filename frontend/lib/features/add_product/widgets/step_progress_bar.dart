import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      alignment: Alignment.center,
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            return Expanded(
              child: Container(
                height: 3,
                color: isCompleted ? const Color(0xFF437A57) : const Color(0xFFE2D7C7),
              ),
            );
          } else {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            final isCurrent = stepIndex == currentStep;

            Color bgColor = const Color(0xFFF2ECE1);
            Color borderColor = const Color(0xFFD6C7B2);
            Widget child = Text(
              '${stepIndex + 1}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7D7265),
              ),
            );

            if (isCompleted) {
              bgColor = const Color(0xFF437A57);
              borderColor = const Color(0xFF437A57);
              child = const Icon(Icons.check, size: 16, color: Colors.white);
            } else if (isCurrent) {
              bgColor = const Color(0xFFC86D51);
              borderColor = const Color(0xFFC86D51);
              child = Text(
                '${stepIndex + 1}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              );
            }

            return GestureDetector(
              onTap: onStepTapped != null ? () => onStepTapped!(stepIndex) : null,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: 2),
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