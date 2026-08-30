import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Responsive container that adapts padding and sizing based on device width
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double? maxWidth;
  final bool center;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.maxWidth,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final responsivePadding =
        padding ?? EdgeInsets.symmetric(horizontal: AppSpacing.getScreenPadding(context));

    Widget content = Padding(
      padding: responsivePadding,
      child: child,
    );

    if (maxWidth != null && width > maxWidth!) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Responsive card widget — flat with a thin border by default (per the
/// "no harsh drop shadows" design requirement), matching CardTheme.
/// Pass [elevation] explicitly only when a screen genuinely needs to lift
/// off the page (e.g. a modal-like card).
class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final double? elevation;
  final BorderRadius? borderRadius;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.onTap,
    this.elevation,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final responsivePadding = padding ?? const EdgeInsets.all(AppSpacing.cardPadding);
    final responsiveRadius =
        borderRadius ?? BorderRadius.circular(AppRadii.getCardRadius(context));

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: elevation ?? AppElevation.none,
        shape: RoundedRectangleBorder(
          borderRadius: responsiveRadius,
          side: elevation == null
              ? const BorderSide(color: AppColors.oak, width: 0.6)
              : BorderSide.none,
        ),
        color: backgroundColor ?? AppColors.surface,
        child: Padding(
          padding: responsivePadding,
          child: child,
        ),
      ),
    );
  }
}

/// Responsive grid view that adapts column count based on device width
class ResponsiveGridView extends StatelessWidget {
  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double spacing;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;

  const ResponsiveGridView({
    super.key,
    required this.children,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 4,
    this.spacing = AppSpacing.md,
    this.physics,
    this.padding,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    late int columnCount;

    if (width < 600) {
      columnCount = mobileColumns;
    } else if (width < 900) {
      columnCount = tabletColumns;
    } else {
      columnCount = desktopColumns;
    }

    return GridView.count(
      crossAxisCount: columnCount,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      children: children,
    );
  }
}

/// Responsive button row that stacks on small devices
class ResponsiveButtonRow extends StatelessWidget {
  final List<Widget> buttons;
  final MainAxisAlignment alignment;
  final double spacing;
  final bool stackOnSmallScreens;

  const ResponsiveButtonRow({
    super.key,
    required this.buttons,
    this.alignment = MainAxisAlignment.spaceEvenly,
    this.spacing = AppSpacing.md,
    this.stackOnSmallScreens = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final shouldStack = stackOnSmallScreens && width < 480;

    if (shouldStack) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          buttons.length,
          (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index < buttons.length - 1 ? spacing : 0,
            ),
            child: buttons[index],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: alignment,
      children: List.generate(
        buttons.length,
        (index) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index < buttons.length - 1 ? spacing : 0,
            ),
            child: buttons[index],
          ),
        ),
      ),
    );
  }
}

/// Responsive text that scales based on device size
class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const ResponsiveText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppSpacing.getResponsiveFontScale(context);
    final scaledStyle = style.copyWith(
      fontSize: (style.fontSize ?? 16) * scale,
    );

    return Text(
      text,
      style: scaledStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}