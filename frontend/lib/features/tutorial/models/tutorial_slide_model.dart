import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class TutorialSlideModel {
  final int stepIndex; // 0 for intro, 1..5 for steps, 6 for ready/outro
  final String badgeKey;
  final String titleKey;
  final String descKey;
  final String tipKey;
  final IconData icon;
  final Color accentColor;
  final List<String> highlights;

  const TutorialSlideModel({
    required this.stepIndex,
    required this.badgeKey,
    required this.titleKey,
    required this.descKey,
    required this.tipKey,
    required this.icon,
    required this.accentColor,
    required this.highlights,
  });

  bool get isIntro => stepIndex == 0;
  bool get isOutro => stepIndex == 6;
  bool get isStep => stepIndex >= 1 && stepIndex <= 5;
}

class TutorialSlidesData {
  static const List<TutorialSlideModel> slides = [
    TutorialSlideModel(
      stepIndex: 0,
      badgeKey: 'slide1_badge',
      titleKey: 'slide1_title',
      descKey: 'slide1_desc',
      tipKey: 'slide1_tip',
      icon: Icons.storefront_rounded,
      accentColor: AppColors.terracotta,
      highlights: [
        'AI Studio Photography',
        'Voice Storytelling',
        'Fair Market Pricing',
        'Works 100% Offline',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 1,
      badgeKey: 'slide2_badge',
      titleKey: 'slide2_title',
      descKey: 'slide2_desc',
      tipKey: 'slide2_tip',
      icon: Icons.camera_alt_rounded,
      accentColor: AppColors.mustard,
      highlights: [
        'Natural Daylight',
        'Plain Background',
        'Add 2-3 Angles',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 2,
      badgeKey: 'slide3_badge',
      titleKey: 'slide3_title',
      descKey: 'slide3_desc',
      tipKey: 'slide3_tip',
      icon: Icons.mic_rounded,
      accentColor: AppColors.terracottaDark,
      highlights: [
        'Tap to Record',
        'Mother Tongue Support',
        'Share Craft Legacy',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 3,
      badgeKey: 'slide4_badge',
      titleKey: 'slide4_title',
      descKey: 'slide4_desc',
      tipKey: 'slide4_tip',
      icon: Icons.auto_fix_high_rounded,
      accentColor: AppColors.forestGreen,
      highlights: [
        'Lighting Enhancement',
        'Auto Craft Story',
        'Smart Tags & Category',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 4,
      badgeKey: 'slide5_badge',
      titleKey: 'slide5_title',
      descKey: 'slide5_desc',
      tipKey: 'slide5_tip',
      icon: Icons.currency_rupee_rounded,
      accentColor: AppColors.mustard,
      highlights: [
        'Material Cost + Labor',
        'Recommended Price Band',
        'Guaranteed Profit Margin',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 5,
      badgeKey: 'slide6_badge',
      titleKey: 'slide6_title',
      descKey: 'slide6_desc',
      tipKey: 'slide6_tip',
      icon: Icons.cloud_sync_rounded,
      accentColor: AppColors.forestGreen,
      highlights: [
        'Zero Data Worry',
        'Drafts Kept Safe',
        'Auto Cloud Sync',
      ],
    ),
    TutorialSlideModel(
      stepIndex: 6,
      badgeKey: 'slide7_badge',
      titleKey: 'slide7_title',
      descKey: 'slide7_desc',
      tipKey: 'slide7_tip',
      icon: Icons.celebration_rounded,
      accentColor: AppColors.terracotta,
      highlights: [
        'Direct Buyer Linkage',
        'Verified Artisan Profile',
        'Zero Middleman Fees',
      ],
    ),
  ];
}
