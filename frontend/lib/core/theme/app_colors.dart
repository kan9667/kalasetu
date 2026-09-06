import 'package:flutter/material.dart';

/// Kalasetu v3 design-token palette.
///
/// Role hierarchy:
///   terracotta  → every primary action button
///   gold        → every secondary/alternate-path button
///   berry       → accent only (at most one hero card per screen — Analytics only)
///   blueAccent  → accent only (comparison bars, text-link icons — never a button fill)
///   success     → dispatched / delivered / confirmed
class AppColors {
  // ---------------------------------------------------------------------------
  // Core palette — exact matches to kalasetu-redesign-v3.html CSS variables
  // ---------------------------------------------------------------------------

  /// Primary action (terracotta)
  static const terracotta     = Color(0xFFB84A29); // --terracotta
  static const terracottaDark = Color(0xFF8C371A); // --terracotta-press
  static const terracottaLight= Color(0xFFF3DBCC); // --terracotta-tint

  /// Secondary action (gold) — drives every secondary / alternate-path button
  static const gold           = Color(0xFFE59A2C); // --gold
  static const goldDark       = Color(0xFFB87A1E); // --gold-press
  static const goldLight      = Color(0xFFFBEACB); // --gold-tint

  /// Accent 1 (berry) — at most one hero-metric card per screen; never a button
  static const berry          = Color(0xFF924C6C); // --berry
  static const berryDark      = Color(0xFF743A54); // --berry-press
  static const berryLight     = Color(0xFFF0DEE6); // --berry-tint

  /// Accent 2 (blue) — comparison bars, text-link icons; never a button fill
  static const blueAccent     = Color(0xFF265067); // --blue
  static const blueAccentDark = Color(0xFF1B3A4C); // --blue-press
  static const blueAccentLight= Color(0xFFDCE6EB); // --blue-tint

  /// Success / dispatched / delivered / payment confirmed
  static const success        = Color(0xFF3B5E3C); // --success
  static const successLight   = Color(0xFFDEE8DA); // --success-tint

  // ---------------------------------------------------------------------------
  // Ink — warm near-black text instead of pure black
  // ---------------------------------------------------------------------------
  static const ink            = Color(0xFF201A18); // --ink
  static const inkSoft        = Color(0xFF6E645F); // --ink-soft
  static const inkFaint       = Color(0xFFA79C93); // --ink-faint

  // ---------------------------------------------------------------------------
  // Surfaces
  // ---------------------------------------------------------------------------
  static const parchment      = Color(0xFFF8F5F0); // --parchment (page bg)
  static const parchmentDeep  = Color(0xFFEFE6D8); // --parchment-deep (track/segmented)
  static const cardSurface    = Color(0xFFFFFDF9); // --card

  // ---------------------------------------------------------------------------
  // Structural
  // ---------------------------------------------------------------------------
  static const dottedBorder   = Color(0xFFD6CCC2); // --dotted
  /// rgba(32,26,24,0.14) — used for borders, field outlines, card outlines
  static const line           = Color(0x24201A18);
  /// resting card shadow rgba(32,26,24,0.08)
  static const shadow         = Color(0x14201A18);
  /// lifted / sheet shadow rgba(32,26,24,0.28)
  static const shadowLifted   = Color(0x47201A18);
  static const overlay        = Color(0x6B1C1613); // rgba(28,22,19,0.42)

  // ---------------------------------------------------------------------------
  // Semantic convenience aliases
  // ---------------------------------------------------------------------------
  static const textPrimary    = ink;
  static const textSecondary  = inkSoft;
  static const textTertiary   = inkFaint;
  static const textOnPrimary  = Color(0xFFFFFFFF);

  static const background     = parchment;
  static const surface        = cardSurface;
  static const surfaceVariant = parchmentDeep;

  static const error          = terracotta;   // use sparingly; terracotta IS the error primary
  static const warning        = gold;
  static const border         = dottedBorder;
  static const divider        = line;

  // ---------------------------------------------------------------------------
  // Status badge roles (order cards + filter chips)
  // ---------------------------------------------------------------------------
  static const statusActionBg   = terracottaLight;  // "New" / action required
  static const statusActionFg   = terracottaDark;
  static const statusPendingBg  = goldLight;        // "Packed" / processing
  static const statusPendingFg  = goldDark;
  static const statusSuccessBg  = successLight;     // Dispatched / delivered
  static const statusSuccessFg  = success;

  // ---------------------------------------------------------------------------
  // Legacy aliases — kept so un-migrated screens still compile.
  // Updated to point to new v3 token values.
  // ---------------------------------------------------------------------------
  static const plaster         = parchment;
  static const plasterDark     = parchmentDeep;
  static const charcoal        = ink;
  static const charcoalSoft    = inkSoft;
  static const cream           = cardSurface;
  static const oak             = dottedBorder;
  static const mustard         = gold;
  static const brick           = terracottaDark;
  static const aboveRange      = berry;

  static const online          = success;
  static const syncing         = gold;
  static const offline         = inkSoft;

  static const statusLive      = success;
  static const statusPending   = gold;
  static const statusDraft     = inkSoft;
  static const statusSold      = gold;

  static const indigo          = terracottaDark;
  static const indigoLight     = terracotta;
  static const indigoDark      = ink;
  static const turmeric        = gold;
  static const turmericLight   = goldLight;
  static const turmericDark    = goldDark;
  static const forestGreen     = success;
  static const forestGreenLight= successLight;
  static const forestGreenDark = Color(0xFF2B4A2C);

  // Keep old terracottaLight alias pointing to new tint
  // (some screens still reference it via the old name)
  static const info            = blueAccent;

  AppColors._();
}