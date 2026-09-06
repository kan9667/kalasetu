import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Empty-state widget — potter's wheel line-art illustration.
///
/// Shows when a Catalogue category filter or Orders filter has no results.
/// The illustration matches the `i-empty-craft` SVG symbol from the mockup:
/// a stylised potter's wheel with spokes.
///
/// Usage:
/// ```dart
/// EmptyCraftState(
///   title: 'Nothing here yet',
///   subtitle: 'No pottery listed yet. Add one from "Add product" to show it here.',
/// )
/// ```
class EmptyCraftState extends StatelessWidget {
  final String title;
  final String subtitle;

  const EmptyCraftState({
    super.key,
    this.title = 'Nothing here yet',
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.7,
              child: SizedBox(
                width: 88,
                height: 88,
                child: CustomPaint(
                  painter: _PottersWheelPainter(color: AppColors.inkFaint),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppTextStyles.headlineSmall.copyWith(
                fontSize: 16,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.inkSoft,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Potter's wheel with spokes — matches `i-empty-craft` in the HTML mockup.
class _PottersWheelPainter extends CustomPainter {
  final Color color;
  const _PottersWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.625; // 60/96 ≈ 0.625 (wheel y in mockup)

    final outerR = size.width * 0.271; // 26/96
    final innerR = size.width * 0.042; // 4/96

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Outer circle
    canvas.drawCircle(Offset(cx, cy), outerR, stroke);
    // Centre dot
    canvas.drawCircle(Offset(cx, cy), innerR, fill);

    // Spokes — matching the path in the mockup SVG
    // M48 60 L48 36 M48 60 L68 48 M48 60 L28 74 M48 60 L70 72 M48 60 L26 46
    final spokeStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final scale = size.width / 96.0;
    final spokes = [
      [48.0, 60.0, 48.0, 36.0],
      [48.0, 60.0, 68.0, 48.0],
      [48.0, 60.0, 28.0, 74.0],
      [48.0, 60.0, 70.0, 72.0],
      [48.0, 60.0, 26.0, 46.0],
    ];
    for (final s in spokes) {
      canvas.drawLine(
        Offset(s[0] * scale, s[1] * scale),
        Offset(s[2] * scale, s[3] * scale),
        spokeStroke,
      );
    }

    // Clay top arc — M38 30 C38 20 58 20 58 30 C58 36 52 36 52 30
    final arc = Path();
    arc.moveTo(38 * scale, 30 * scale);
    arc.cubicTo(38 * scale, 20 * scale, 58 * scale, 20 * scale, 58 * scale, 30 * scale);
    arc.cubicTo(58 * scale, 36 * scale, 52 * scale, 36 * scale, 52 * scale, 30 * scale);
    canvas.drawPath(arc, stroke);
  }

  @override
  bool shouldRepaint(_PottersWheelPainter old) => old.color != color;
}
