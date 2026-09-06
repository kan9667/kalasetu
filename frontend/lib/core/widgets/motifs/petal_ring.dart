import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Kamal pankhudi — petal ring motif.
///
/// Draws 8 petal ellipses radiating from centre at 45° intervals, in a soft
/// gold tint. Matches the SVG `i-petal-ring` symbol in the HTML mockup.
///
/// Wrap around a category icon's [child] widget. The ring is purely decorative
/// and slightly larger than the icon.
///
/// Usage:
/// ```dart
/// PetalRing(
///   size: 38,
///   child: Icon(icon, size: 18, color: color),
/// )
/// ```
class PetalRing extends StatelessWidget {
  final Widget? child;
  final double size;
  final Color color;
  final double opacity;

  const PetalRing({
    super.key,
    this.child,
    this.size = 38,
    this.color = AppColors.gold,
    this.opacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _PetalRingPainter(color: color.withValues(alpha: opacity)),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _PetalRingPainter extends CustomPainter {
  final Color color;
  const _PetalRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Petal ellipse dimensions relative to overall size
    final rx = size.width * 0.075;  // petal half-width
    final ry = size.height * 0.135; // petal half-height
    // Centre of each petal ellipse (offset from canvas centre)
    final offset = size.height * 0.33;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true;

    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4; // 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      // Each petal ellipse centre is at (0, -offset) in local rotated space
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -offset),
          width: rx * 2,
          height: ry * 2,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PetalRingPainter old) => old.color != color;
}
