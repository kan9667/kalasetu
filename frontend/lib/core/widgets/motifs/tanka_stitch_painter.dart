import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Tanka / stitch dashed line motif.
///
/// Paints a repeating dashed line (e.g. 5px dash, 4px gap) representing
/// traditional Indian embroidery running stitches ("tanka").
/// Used primarily for completed progress stepper segments between steps.
class TankaStitchPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;

  const TankaStitchPainter({
    this.color = AppColors.success,
    this.strokeWidth = 2.0,
    this.dashLength = 5.0,
    this.dashGap = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      final endX = (x + dashLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += dashLength + dashGap;
    }
  }

  @override
  bool shouldRepaint(TankaStitchPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashGap != dashGap;
  }
}
