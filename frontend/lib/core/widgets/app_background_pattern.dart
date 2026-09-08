import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Kalasetu Warli-art decorative watermark pattern.
///
/// Displays a subtle traditional Warli line-art motif at the bottom of the screen,
/// sitting just above where the bottom navigation bar begins.
///
/// Features:
/// - [opacity]: Configurable opacity (default 0.06, recommended range 0.05–0.08).
/// - [imagePath]: Path to the line-art asset (defaults to assets/images/warli_pattern.png).
/// - [color]: Blend color (defaults to [AppColors.ink]).
/// - [height]: Optional custom height constraint.
/// - [bottomPadding]: Extra bottom inset above the bottom nav bar or safe boundary.
/// - [alignment]: Alignment within parent (defaults to [Alignment.bottomCenter]).
/// - Uses [IgnorePointer] so touch events pass through to content without interception.
/// - Uses [RepaintBoundary] to avoid repainting during scroll and animation events.
class AppBackgroundPattern extends StatelessWidget {
  final double opacity;
  final String imagePath;
  final Color? color;
  final double? height;
  final double bottomPadding;
  final Alignment alignment;
  final BoxFit fit;

  const AppBackgroundPattern({
    super.key,
    this.opacity = 0.06,
    this.imagePath = 'assets/images/warli_pattern.png',
    this.color,
    this.height,
    this.bottomPadding = 0.0,
    this.alignment = Alignment.bottomCenter,
    this.fit = BoxFit.fitWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0.0) {
      return const SizedBox.shrink();
    }

    final tintColor = (color ?? AppColors.ink).withValues(alpha: opacity);

    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: height,
                  child: Image.asset(
                    imagePath,
                    width: constraints.maxWidth,
                    height: height,
                    fit: fit,
                    alignment: alignment,
                    color: tintColor,
                    colorBlendMode: BlendMode.modulate,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
