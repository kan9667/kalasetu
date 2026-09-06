import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/tutorial_slide_model.dart';

class TutorialCardWidget extends StatelessWidget {
  final TutorialSlideModel slide;
  final bool isSpeaking;
  final VoidCallback onToggleSpeak;

  const TutorialCardWidget({
    super.key,
    required this.slide,
    required this.isSpeaking,
    required this.onToggleSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Visual Hero Graphic ---
              _buildVisualHero(context),

              const SizedBox(height: AppSpacing.lg),

              // --- Badge / Category Pill ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: slide.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  border: Border.all(
                    color: slide.accentColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      slide.icon,
                      size: 16,
                      color: slide.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      slide.badgeKey.tr(),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: slide.accentColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // --- Main Headline (Fraunces Display) ---
              Text(
                slide.titleKey.tr(),
                textAlign: TextAlign.center,
                style: AppTextStyles.displaySmall.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // --- Explanatory Subtitle (Inter) ---
              Text(
                slide.descKey.tr(),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.charcoalSoft,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualHero(BuildContext context) {
    return SizedBox(
      height: 160,
      width: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer subtle decorative pulse ring
          Container(
            width: 154,
            height: 154,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.accentColor.withValues(alpha: 0.08),
            ),
          ),
          // Middle soft glow ring
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.accentColor.withValues(alpha: 0.16),
            ),
          ),
          // Inner core surface
          Container(
            width: 98,
            height: 98,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: slide.accentColor.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: slide.accentColor.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                slide.icon,
                size: 48,
                color: slide.accentColor,
              ),
            ),
          ),
          // Audio Speaker Narration button overlay
          Positioned(
            right: 4,
            bottom: 4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggleSpeak,
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSpeaking ? AppColors.terracotta : AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: isSpeaking ? AppColors.terracottaDark : AppColors.border,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    isSpeaking ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    size: 18,
                    color: isSpeaking ? AppColors.textOnPrimary : AppColors.charcoal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
