import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class TutorialSlideModel {
  final int stepIndex; // 0 for intro, 1..6 for steps, 7 for ready/outro
  final String badgeKey;
  final String titleKey;
  final String descKey;
  final String ttsKey; // short crisp narration text key
  final IconData icon;
  final Color accentColor;
  final List<String> highlights;

  const TutorialSlideModel({
    required this.stepIndex,
    required this.badgeKey,
    required this.titleKey,
    required this.descKey,
    required this.ttsKey,
    required this.icon,
    required this.accentColor,
    required this.highlights,
  });

  bool get isIntro => stepIndex == 0;
  bool get isOutro => stepIndex == 7;
  bool get isStep => stepIndex >= 1 && stepIndex <= 6;
}

class TutorialSlidesData {
  static const List<TutorialSlideModel> slides = [
    // ── Slide 1: Overview ────────────────────────────────────────────────
    TutorialSlideModel(
      stepIndex: 0,
      badgeKey: 'slide1_badge',
      titleKey: 'slide1_title',
      descKey: 'slide1_desc',
      ttsKey: 'slide1_tts',
      icon: Icons.storefront_rounded,
      accentColor: AppColors.terracotta,
      highlights: [
        'List Crafts',
        'Market on WhatsApp',
        'AI Assistant',
        'Track Orders',
      ],
    ),
    // ── Slide 2: Step 1 — Photography ───────────────────────────────────
    TutorialSlideModel(
      stepIndex: 1,
      badgeKey: 'slide2_badge',
      titleKey: 'slide2_title',
      descKey: 'slide2_desc',
      ttsKey: 'slide2_tts',
      icon: Icons.camera_alt_rounded,
      accentColor: AppColors.mustard,
      highlights: [
        'Morning Daylight',
        'Clean Background',
        '2–3 Angles',
      ],
    ),
    // ── Slide 3: Step 2 — Voice Story ───────────────────────────────────
    TutorialSlideModel(
      stepIndex: 2,
      badgeKey: 'slide3_badge',
      titleKey: 'slide3_title',
      descKey: 'slide3_desc',
      ttsKey: 'slide3_tts',
      icon: Icons.mic_rounded,
      accentColor: AppColors.terracottaDark,
      highlights: [
        'Hindi, Tamil, Bengali',
        'Say Materials Used',
        'Share Craft Legacy',
      ],
    ),
    // ── Slide 4: Step 3 — AI Review & Fair Price ────────────────────────
    TutorialSlideModel(
      stepIndex: 3,
      badgeKey: 'slide4_badge',
      titleKey: 'slide4_title',
      descKey: 'slide4_desc',
      ttsKey: 'slide4_tts',
      icon: Icons.auto_fix_high_rounded,
      accentColor: AppColors.forestGreen,
      highlights: [
        'AI-Enhanced Photo',
        'Auto Craft Story',
        'Dignity Fair Price',
      ],
    ),
    // ── Slide 5: Step 4 — Social Media Helper (NEW) ─────────────────────
    TutorialSlideModel(
      stepIndex: 4,
      badgeKey: 'slide5_badge',
      titleKey: 'slide5_title',
      descKey: 'slide5_desc',
      ttsKey: 'slide5_tts',
      icon: Icons.share_rounded,
      accentColor: AppColors.mustard,
      highlights: [
        'WhatsApp & Instagram',
        'Ready-Made Captions',
        '1-Tap Copy & Share',
      ],
    ),
    // ── Slide 6: Step 5 — KalaMitra AI Assistant (NEW) ──────────────────
    TutorialSlideModel(
      stepIndex: 5,
      badgeKey: 'slide6_badge',
      titleKey: 'slide6_title',
      descKey: 'slide6_desc',
      ttsKey: 'slide6_tts',
      icon: Icons.record_voice_over_rounded,
      accentColor: AppColors.gold,
      highlights: [
        'Ask in Your Language',
        'Pricing Advice',
        'Pehchan ID Help',
      ],
    ),
    // ── Slide 7: Step 6 — Orders & Analytics (NEW) ──────────────────────
    TutorialSlideModel(
      stepIndex: 6,
      badgeKey: 'slide7_badge',
      titleKey: 'slide7_title',
      descKey: 'slide7_desc',
      ttsKey: 'slide7_tts',
      icon: Icons.bar_chart_rounded,
      accentColor: AppColors.forestGreen,
      highlights: [
        'Pack & Ship Orders',
        'Fair Wage Earnings',
        'Sales Analytics',
      ],
    ),
    // ── Slide 8: Ready / Outro ───────────────────────────────────────────
    TutorialSlideModel(
      stepIndex: 7,
      badgeKey: 'slide8_badge',
      titleKey: 'slide8_title',
      descKey: 'slide8_desc',
      ttsKey: 'slide8_tts',
      icon: Icons.celebration_rounded,
      accentColor: AppColors.terracotta,
      highlights: [
        'Open Studio Camera',
        'List Your First Craft',
        'Start Earning Today',
      ],
    ),
  ];
}
