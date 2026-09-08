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
              // --- Visual Hero Graphic with Animated Glowing Aura ---
              _AnimatedGlowHero(
                accentColor: slide.accentColor,
                icon: slide.icon,
                isSpeaking: isSpeaking,
                onToggleSpeak: onToggleSpeak,
              ),

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
                      style: AppTextStyles.labelSmall.copyWith(
                        color: slide.accentColor,
                        letterSpacing: 0.4,
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
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // --- Explanatory Subtitle (Manrope Body) ---
              Text(
                slide.descKey.tr(),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual hero icon surrounded by an animated breathing glow aura and pulsing shadows.
class _AnimatedGlowHero extends StatefulWidget {
  final Color accentColor;
  final IconData icon;
  final bool isSpeaking;
  final VoidCallback onToggleSpeak;

  const _AnimatedGlowHero({
    required this.accentColor,
    required this.icon,
    required this.isSpeaking,
    required this.onToggleSpeak,
  });

  @override
  State<_AnimatedGlowHero> createState() => _AnimatedGlowHeroState();
}

class _AnimatedGlowHeroState extends State<_AnimatedGlowHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _glowAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      width: 170,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          final t = _glowAnimation.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Radial gradient continuous breathing aura (replaces static rings)
              Container(
                width: 140 + 26 * t,
                height: 140 + 26 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.accentColor.withValues(alpha: 0.28 * t + 0.12),
                      widget.accentColor.withValues(alpha: 0.10 * t + 0.04),
                      widget.accentColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // Inner core surface with pulsing glowing shadows
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cardSurface,
                  boxShadow: [
                    // Blooming radiant glow
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.25 + 0.25 * t),
                      blurRadius: 20.0 + 16.0 * t,
                      spreadRadius: 2.0 + 6.0 * t,
                    ),
                    // Inner luminous warmth
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.15 + 0.15 * t),
                      blurRadius: 8.0 + 6.0 * t,
                      spreadRadius: 0,
                    ),
                    // Grounding subtle shadow
                    const BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.35 + 0.20 * t),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 48,
                    color: widget.accentColor,
                  ),
                ),
              ),

              // Audio Speaker Narration button overlay
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onToggleSpeak,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.isSpeaking ? AppColors.terracotta : AppColors.cardSurface,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: widget.isSpeaking
                              ? AppColors.terracottaDark
                              : AppColors.border,
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        widget.isSpeaking
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        size: 18,
                        color: widget.isSpeaking
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
