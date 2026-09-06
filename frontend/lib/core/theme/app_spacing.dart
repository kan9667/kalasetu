import 'package:flutter/material.dart';

/// Responsive spacing system — 8pt grid
class AppSpacing {
  // Base spacing units
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;
  static const double xxxl = 64.0;

  // Semantic spacing
  static const double screenPadding  = 20.0;
  static const double cardPadding    = 16.0;
  static const double sectionSpacing = 24.0;
  static const double itemSpacing    = 12.0;

  // Touch targets — 48dp minimum per WCAG / Material
  static const double minTouchTarget        = 48.0;
  static const double minTouchTargetCompact = 40.0;

  // Icon sizes
  static const double iconSize       = 24.0;
  static const double iconSizeLarge  = 32.0;
  static const double iconSizeSmall  = 20.0;
  static const double iconSizeXLarge = 48.0;

  // Responsive screen padding
  static double getScreenPadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 12.0;
    if (w < 480) return 16.0;
    if (w < 600) return 20.0;
    if (w < 900) return 28.0;
    return 40.0;
  }

  // Responsive font-size scale
  static double getResponsiveFontScale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 0.85;
    if (w < 480) return 0.92;
    if (w < 600) return 1.0;
    if (w < 900) return 1.08;
    return 1.15;
  }

  // Responsive button height
  static double getButtonHeight(BuildContext context, {bool compact = false}) {
    final w = MediaQuery.of(context).size.width;
    if (compact) return w < 480 ? 36.0 : minTouchTargetCompact;
    return w < 480 ? 44.0 : minTouchTarget;
  }

  // Responsive list gap
  static double getListGap(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 480) return 8.0;
    if (w < 600) return 12.0;
    if (w < 900) return 16.0;
    return 20.0;
  }

  AppSpacing._();
}

/// Soft rounded corners for warm, approachable feel
class AppRadii {
  static const double xs         = 4.0;
  static const double sm         = 8.0;
  static const double md         = 12.0;
  static const double lg         = 16.0;
  static const double xl         = 20.0;
  static const double xxl        = 24.0;
  static const double full       = 999.0;

  // Semantic radii — v3 spec
  static const double button     = 999.0; // fully rounded pill buttons
  static const double card       = 16.0;
  static const double chip       = 999.0; // pill chips
  static const double bottomSheet = 24.0;
  static const double dialog     = 20.0;
  static const double inputField = 12.0;

  // Responsive card radius
  static double getCardRadius(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 12.0;
    if (w < 600) return 16.0;
    return 20.0;
  }

  AppRadii._();
}

/// Elevation and shadow definitions — v3 warm-toned shadows
class AppElevation {
  static const double none    = 0;
  static const double subtle  = 2;
  static const double low     = 4;
  static const double medium  = 8;
  static const double high    = 12;
  static const double highest = 16;

  /// Resting card shadow — rgba(32,26,24,0.08) shallow and tactile
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x14201A18), // 0.08 opacity
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x0F201A18), // 0.06 opacity
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Lifted shadow — for open bottom sheets / hovered cards
  /// rgba(32,26,24,0.28) deeper
  static const List<BoxShadow> cardShadowLifted = [
    BoxShadow(
      color: Color(0x47201A18), // 0.28 opacity
      blurRadius: 30,
      spreadRadius: -14,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x14201A18),
      blurRadius: 8,
      offset: Offset(0, 3),
    ),
  ];

  /// Responsive version (kept for backward compat; returns cardShadow always)
  static List<BoxShadow> getCardShadow(BuildContext context) => cardShadow;

  AppElevation._();
}