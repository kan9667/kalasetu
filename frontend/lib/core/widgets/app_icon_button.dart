import 'package:flutter/material.dart';
import '../services/app_sound_service.dart';

/// Tactile icon button component that plays a subtle click and haptic tap on press.
///
/// Drop-in replacement for standard [IconButton].
class AppIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final ButtonStyle? style;
  final VisualDensity? visualDensity;
  final AlignmentGeometry alignment;
  final bool enableFeedback;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize,
    this.padding,
    this.constraints,
    this.style,
    this.visualDensity,
    this.alignment = Alignment.center,
    this.enableFeedback = false, // Handled by AppSoundService
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: AppSoundFeedback.wrap(onPressed),
      tooltip: tooltip,
      color: color,
      iconSize: iconSize,
      padding: padding,
      constraints: constraints,
      style: style,
      visualDensity: visualDensity,
      alignment: alignment,
      enableFeedback: enableFeedback,
    );
  }
}
