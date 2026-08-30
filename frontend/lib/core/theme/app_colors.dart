import 'package:flutter/material.dart';


class AppColors {
  // --- Core palette (per design spec) ---
  static const plaster = Color(0xFFF3ECDF);        // background
  static const plasterDark = Color(0xFFE7DCC7);    // secondary surface
  static const charcoal = Color(0xFF2A2420);        // primary text / frame
  static const charcoalSoft = Color(0xFF655A4E);    // secondary text
  static const terracotta = Color(0xFFC97B5A);      // primary actions
  static const terracottaDark = Color(0xFFAD5F3F);  // pressed / emphasis
  static const terracottaLight = Color(0xFFE3A688);
  static const brick = Color(0xFF96392C);           // alerts / underpriced
  static const mustard = Color(0xFFD9A441);         // positive / fair price
  static const oak = Color(0xFFA9835F);             // borders / secondary
  static const cream = Color(0xFFFBF7EF);           // card surfaces

  static const aboveRange = Color(0xFF6E5A78);

  // --- Connectivity / sync status ---
  static const online = Color(0xFF4A7C59);
  static const syncing = Color(0xFFB8863A);
  static const offline = charcoalSoft;

  // --- Semantic text roles ---
  static const textPrimary = charcoal;
  static const textSecondary = charcoalSoft;
  static const textTertiary = Color(0xFF8F7E68);
  static const textOnPrimary = cream;

  // --- Semantic surface roles ---
  static const background = plaster;
  static const surface = cream;
  static const surfaceVariant = plasterDark;

  // --- Semantic state roles ---
  static const error = brick;
  static const warning = mustard;
  static const success = online;
  static const info = terracottaDark;

  // --- Listing status badges ---
  static const statusLive = online;
  static const statusPending = syncing;
  static const statusDraft = charcoalSoft;
  static const statusSold = mustard;

  // --- Structure ---
  static const border = oak;
  static const divider = Color(0x66A9835F); // oak @ ~40% alpha
  static const overlay = Color(0x40000000);
  static const shadow = Color(0x1A2A2420);  // soft charcoal — never harsh

  // --- Legacy aliases ---
  // Kept temporarily so screens I haven't migrated yet still compile.
  // Send me those screens and I'll remove the alias once they're updated.
  static const indigo = terracottaDark;
  static const indigoLight = terracotta;
  static const indigoDark = charcoal;
  static const turmeric = mustard;
  static const turmericLight = Color(0xFFE6BC6E);
  static const turmericDark = Color(0xFFB8863A);
  static const forestGreen = online;
  static const forestGreenLight = Color(0xFF6FA37E);
  static const forestGreenDark = Color(0xFF35603F);

  AppColors._();
}