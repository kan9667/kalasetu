import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Bindi / daane dotted-border motif.
///
/// Wraps [child] in a container with a 1.5px dotted border in [AppColors.dottedBorder]
/// and [AppRadii.card] corner radius. The border is painted via [CustomPainter]
/// since Flutter's [BoxBorder] does not support dash patterns natively.
///
/// Use it around:
///   - The photo-capture box in Add Product Step 1
///   - As a horizontal rule (height: 1, no child) between card groups
class DottedBorderBox extends StatelessWidget {
  final Widget? child;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final double dashLength;
  final double dashGap;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double? width;
  final double? height;

  const DottedBorderBox({
    super.key,
    this.child,
    this.borderColor = AppColors.dottedBorder,
    this.borderWidth = 1.5,
    this.radius = AppSpacing.md,         // 16dp card radius
    this.dashLength = 4.0,
    this.dashGap = 4.0,
    this.padding,
    this.backgroundColor,
    this.width,
    this.height,
  });

  /// Convenience constructor for a horizontal dotted divider line.
  const DottedBorderBox.divider({
    super.key,
    this.borderColor = AppColors.dottedBorder,
    this.borderWidth = 1.5,
    this.dashLength = 5.0,
    this.dashGap = 4.0,
  })  : child = null,
        radius = 0,
        padding = null,
        backgroundColor = null,
        width = double.infinity,
        height = 1;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(
        color: borderColor,
        strokeWidth: borderWidth,
        radius: radius,
        dashLength: dashLength,
        dashGap: dashGap,
        isDivider: height == 1 && child == null,
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: backgroundColor != null
            ? BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(radius),
              )
            : null,
        child: child,
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double dashGap;
  final bool isDivider;

  const _DottedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.dashGap,
    required this.isDivider,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (isDivider) {
      // Simple horizontal dashed line
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset(x + dashLength, size.height / 2),
          paint,
        );
        x += dashLength + dashGap;
      }
      return;
    }

    // Rounded-rect dotted border
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(
          strokeWidth / 2,
          strokeWidth / 2,
          size.width - strokeWidth,
          size.height - strokeWidth,
        ),
        Radius.circular(radius),
      ));

    _drawDashedPath(canvas, path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DottedBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      old.dashLength != dashLength ||
      old.dashGap != dashGap;
}
