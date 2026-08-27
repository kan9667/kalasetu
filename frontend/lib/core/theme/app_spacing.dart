import 'package:flutter/material.dart';

/// Responsive spacing system that adapts to device size
class AppSpacing {
  // Base spacing units - 8pt grid
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Semantic spacing
  static const double screenPadding = 20.0;
  static const double cardPadding = 16.0;
  static const double sectionSpacing = 24.0;
  static const double itemSpacing = 12.0;

  // Touch targets - minimum 48dp for accessibility
  static const double minTouchTarget = 48.0;
  static const double minTouchTargetCompact = 40.0;

  // Icon sizes
  static const double iconSize = 24.0;
  static const double iconSizeLarge = 32.0;
  static const double iconSizeSmall = 20.0;
  static const double iconSizeXLarge = 48.0;

  // Responsive screen padding based on width
  static double getScreenPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 12.0; // Extra small phones
    if (width < 480) return 16.0; // Small phones
    if (width < 600) return 20.0; // Regular phones
    if (width < 900) return 28.0; // Tablets
    return 40.0; // Large tablets and desktops
  }

  // Responsive font size scale
  static double getResponsiveFontScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 0.85;
    if (width < 480) return 0.92;
    if (width < 600) return 1.0;
    if (width < 900) return 1.08;
    return 1.15;
  }

  // Responsive button height
  static double getButtonHeight(BuildContext context, {bool compact = false}) {
    final width = MediaQuery.of(context).size.width;
    if (compact) {
      return width < 480 ? 36.0 : minTouchTargetCompact;
    }
    return width < 480 ? 44.0 : minTouchTarget;
  }

  // Responsive gap for lists
  static double getListGap(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 480) return 8.0;
    if (width < 600) return 12.0;
    if (width < 900) return 16.0;
    return 20.0;
  }

  AppSpacing._();
}

/// Soft rounded corners for warm, approachable feel
class AppRadii {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  // Semantic radii
  static const double button = 12.0;
  static const double card = 16.0;
  static const double chip = 20.0;
  static const double bottomSheet = 24.0;
  static const double dialog = 20.0;

  // Responsive radius based on device
  static double getCardRadius(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 12.0;
    if (width < 600) return 16.0;
    return 20.0;
  }

  AppRadii._();
}

/// Elevation and shadow definitions
class AppElevation {
  static const double none = 0;
  static const double subtle = 2;
  static const double low = 4;
  static const double medium = 8;
  static const double high = 12;
  static const double highest = 16;

  // Responsive shadow based on device
  static List<BoxShadow> getCardShadow(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final blur = width < 600 ? 4.0 : 8.0;
    return [
      BoxShadow(
        color: const Color(0x20000000),
        blurRadius: blur,
        offset: Offset(0, width < 600 ? 2 : 4),
      ),
    ];
  }

  AppElevation._();
}
