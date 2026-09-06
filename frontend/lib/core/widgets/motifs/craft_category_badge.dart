import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_spacing.dart';
import 'petal_ring.dart';

/// Craft category filter badge — pill chip matching kalasetu-redesign-v3.html.
///
/// - Inactive: white/parchment body, 1.5px terracotta border, terracotta icon + text
/// - Active: terracotta fill, white text/icon
/// - Shows a [PetalRing] behind the pictorial icon (gold tint on inactive,
///   white tint on active)
///
/// The [icon] is a path-based [CustomPainter] to match the mockup's fine
/// line-art style. Use [CraftCategoryIcon] helpers to obtain the right painter.
///
/// Usage:
/// ```dart
/// CraftCategoryBadge(
///   label: 'Pottery',
///   icon: CraftCategoryIcons.pottery,
///   isActive: _selectedCategory == 'pottery',
///   onTap: () => setState(() => _selectedCategory = 'pottery'),
/// )
/// ```
class CraftCategoryBadge extends StatelessWidget {
  final String label;
  final CustomPainter icon;
  final bool isActive;
  final VoidCallback? onTap;
  final bool showPetalRing;

  const CraftCategoryBadge({
    super.key,
    required this.label,
    required this.icon,
    this.isActive = false,
    this.onTap,
    this.showPetalRing = true,
  });

  /// All-crafts badge (no pictorial icon, no petal ring)
  const CraftCategoryBadge.all({
    super.key,
    required this.label,
    this.isActive = false,
    this.onTap,
  })  : icon = const _NullPainter(),
        showPetalRing = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive ? AppColors.terracotta : AppColors.cardSurface;
    final fgColor = isActive ? AppColors.textOnPrimary : AppColors.terracottaDark;
    final borderColor =
        isActive ? AppColors.terracotta : AppColors.terracotta;

    final hasIcon = icon is! _NullPainter;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.only(
          left: hasIcon
              ? (showPetalRing ? AppSpacing.xs : AppSpacing.sm)
              : AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasIcon) ...[
              SizedBox(
                width: showPetalRing ? 26 : 18,
                height: showPetalRing ? 26 : 18,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Petal ring behind icon
                    if (showPetalRing)
                      PetalRing(
                        size: 32,
                        color: isActive ? Colors.white : AppColors.gold,
                        opacity: 0.55,
                      ),
                    CustomPaint(
                      size: const Size(15, 15),
                      painter: _ColoredPainter(
                        delegate: icon,
                        color: fgColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: showPetalRing ? 7 : 5),
            ],
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 12.5,
                color: fgColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a [CustomPainter] delegate and applies a color override to the paint.
class _ColoredPainter extends CustomPainter {
  final CustomPainter delegate;
  final Color color;
  const _ColoredPainter({required this.delegate, required this.color});

  @override
  void paint(Canvas canvas, Size size) => delegate.paint(canvas, size);

  @override
  bool shouldRepaint(_ColoredPainter old) =>
      old.color != color || old.delegate != delegate;
}

class _NullPainter extends CustomPainter {
  const _NullPainter();
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_NullPainter _) => false;
}

// ---------------------------------------------------------------------------
// Craft category icon painters — fine line-art matching the mockup's SVG icons
// ---------------------------------------------------------------------------

/// Pottery wheel icon (matching `i-cat-pottery` SVG)
class PotteryIconPainter extends CustomPainter {
  final Color color;
  const PotteryIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final sw = size.width;
    final sh = size.height;

    // Top rim rectangle
    canvas.drawRect(Rect.fromLTWH(sw * 0.375, 0, sw * 0.25, sh * 0.125), p);
    // Body path: rounded bulging shape
    final body = Path()
      ..moveTo(sw * 0.342, sh * 0.258)
      ..cubicTo(sw * 0.1, sh * 0.379, sw * 0.0, sh * 0.508, sw * 0.042, sh * 0.833)
      ..cubicTo(sw * 0.083, sh * 1.0, sw * 0.25, sh * 1.0, sw * 0.5, sh * 1.0)
      ..cubicTo(sw * 0.75, sh * 1.0, sw * 0.917, sh * 1.0, sw * 0.958, sh * 0.833)
      ..cubicTo(sw * 1.0, sh * 0.508, sw * 0.9, sh * 0.379, sw * 0.658, sh * 0.258);
    canvas.drawPath(body, p);
  }

  @override
  bool shouldRepaint(PotteryIconPainter old) => old.color != color;
}

/// Textile / shuttle-eye icon (matching `i-cat-textile` SVG)
class TextileIconPainter extends CustomPainter {
  final Color color;
  const TextileIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final sw = size.width;
    final sh = size.height;

    // Outer eye ellipse
    final eye = Path()
      ..moveTo(sw * 0.083, sh * 0.5)
      ..cubicTo(sw * 0.267, sh * 0.1, sw * 0.733, sh * 0.1, sw * 0.917, sh * 0.5)
      ..cubicTo(sw * 0.733, sh * 0.9, sw * 0.267, sh * 0.9, sw * 0.083, sh * 0.5)
      ..close();
    canvas.drawPath(eye, stroke);
    // Centre dot
    canvas.drawCircle(Offset(sw * 0.5, sh * 0.5), sw * 0.067, fill);
  }

  @override
  bool shouldRepaint(TextileIconPainter old) => old.color != color;
}

/// Gem / jewelry icon (matching `i-cat-jewelry` SVG)
class JewelryIconPainter extends CustomPainter {
  final Color color;
  const JewelryIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final sw = size.width;
    final sh = size.height;

    final gem = Path()
      ..moveTo(sw * 0.271, sh * 0.125)
      ..lineTo(sw * 0.729, sh * 0.125)
      ..lineTo(sw * 1.0, sh * 0.375)
      ..lineTo(sw * 0.5, sh * 1.0)
      ..lineTo(sw * 0.0, sh * 0.375)
      ..close();
    canvas.drawPath(gem, p);

    // Horizontal belt line
    canvas.drawLine(
        Offset(sw * 0.0, sh * 0.375), Offset(sw * 1.0, sh * 0.375), p);
  }

  @override
  bool shouldRepaint(JewelryIconPainter old) => old.color != color;
}

/// Wood-work / chisel icon (matching `i-cat-wood` SVG)
class WoodworkIconPainter extends CustomPainter {
  final Color color;
  const WoodworkIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final sw = size.width;
    final sh = size.height;

    // Chisel head (parallelogram)
    final head = Path()
      ..moveTo(sw * 0.604, sh * 0.104)
      ..lineTo(sw * 0.896, sh * 0.396)
      ..lineTo(sw * 0.771, sh * 0.521)
      ..lineTo(sw * 0.479, sh * 0.229)
      ..close();
    canvas.drawPath(head, p);

    // Handle
    final handle = Path()
      ..moveTo(sw * 0.479, sh * 0.229)
      ..lineTo(sw * 0.104, sh * 0.604)
      ..lineTo(sw * 0.104, sh * 0.875)
      ..lineTo(sw * 0.375, sh * 0.875)
      ..lineTo(sw * 0.771, sh * 0.5);
    canvas.drawPath(handle, p);
  }

  @override
  bool shouldRepaint(WoodworkIconPainter old) => old.color != color;
}

/// Convenience namespace for accessing craft icon painters.
abstract class CraftCategoryIcons {
  static CustomPainter pottery({Color color = const Color(0xFF8C371A)}) =>
      PotteryIconPainter(color: color);
  static CustomPainter textile({Color color = const Color(0xFF8C371A)}) =>
      TextileIconPainter(color: color);
  static CustomPainter jewelry({Color color = const Color(0xFF8C371A)}) =>
      JewelryIconPainter(color: color);
  static CustomPainter woodwork({Color color = const Color(0xFF8C371A)}) =>
      WoodworkIconPainter(color: color);
}
