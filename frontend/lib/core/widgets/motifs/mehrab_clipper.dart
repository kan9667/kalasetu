import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Mehrab arch clipper — scalloped top edge for the Packaging Guide bottom sheet.
///
/// Produces a repeating arch pattern at the top edge of a container, matching
/// the `i-mehrab-top` SVG pattern in the HTML mockup:
///   arch width = 30px, arch height = 18px, repeating-x.
///
/// Usage (in DraggableScrollableSheet or modal bottom sheet):
/// ```dart
/// ClipPath(
///   clipper: MehrabClipper(),
///   child: Container(color: AppColors.cardSurface, ...),
/// )
/// ```
class MehrabClipper extends CustomClipper<Path> {
  /// Width of each scallop arch
  final double archWidth;
  /// Height (depth) of each scallop
  final double archHeight;

  const MehrabClipper({
    this.archWidth = 30.0,
    this.archHeight = 18.0,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    // Start from bottom-left
    path.moveTo(0, size.height);
    path.lineTo(0, archHeight);

    // Draw repeating scallop arches across the top
    double x = 0;
    while (x < size.width) {
      final midX = x + archWidth / 2;
      final endX = x + archWidth;
      // Cubic bezier producing a rounded arch (convex downward = scallop)
      path.cubicTo(
        x, 0,          // control point 1: left shoulder down to 0
        midX, 0,       // control point 2: peak at 0
        midX, archHeight, // midpoint back down
      );
      path.cubicTo(
        midX, archHeight * 0.4,
        endX, 0,
        endX, archHeight,
      );
      x += archWidth;
    }

    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(MehrabClipper old) =>
      old.archWidth != archWidth || old.archHeight != archHeight;
}

/// A bottom-sheet modal wrapper with a scalloped (mehrab) top edge.
///
/// Replaces the plain-rounded-corner sheet in the Packaging Guide.
/// Slide-up animation is handled by [showMehrabBottomSheet].
class MehrabSheetContainer extends StatelessWidget {
  final Widget child;
  final double archWidth;
  final double archHeight;

  const MehrabSheetContainer({
    super.key,
    required this.child,
    this.archWidth = 30.0,
    this.archHeight = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: MehrabClipper(archWidth: archWidth, archHeight: archHeight),
      child: Container(
        color: AppColors.cardSurface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scallop spacer at top
            SizedBox(height: archHeight + 4),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Shows a bottom sheet with a scalloped mehrab top edge.
///
/// [builder] receives a context and should return the sheet body content
/// (without any outer container — that's provided by this function).
Future<T?> showMehrabBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.overlay,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: true,
    builder: (ctx) => MehrabSheetContainer(child: builder(ctx)),
  );
}
