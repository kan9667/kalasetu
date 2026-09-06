import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../home/screens/home_shell.dart';
import '../models/tutorial_slide_model.dart';
import '../widgets/tutorial_card_widget.dart';
import '../services/tutorial_tts_service.dart';

class TutorialCarouselScreen extends ConsumerStatefulWidget {
  const TutorialCarouselScreen({super.key});

  @override
  ConsumerState<TutorialCarouselScreen> createState() => _TutorialCarouselScreenState();
}

class _TutorialCarouselScreenState extends ConsumerState<TutorialCarouselScreen> {
  final PageController _pageController = PageController();
  final TutorialTtsService _ttsService = TutorialTtsService();
  int _currentPage = 0;
  final List<TutorialSlideModel> _slides = TutorialSlidesData.slides;

  @override
  void initState() {
    super.initState();
    _ttsService.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    // Stop voice playback when user swipes to a new slide
    if (_ttsService.isPlaying) {
      _ttsService.stop();
    }
  }

  void _toggleSpeakCurrentSlide() {
    if (_ttsService.isPlaying) {
      _ttsService.stop();
    } else {
      final currentSlide = _slides[_currentPage];
      final title = currentSlide.titleKey.tr();
      final desc = currentSlide.descKey.tr();
      final fullSpeech = '$title. $desc';
      _ttsService.speak(fullSpeech, languageCode: context.locale.languageCode);
    }
  }

  void _goToNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finishTutorialAndStartListing();
    }
  }

  void _goToPrevious() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _finishTutorialAndStartListing() {
    _ttsService.stop();
    ref.read(homeTabIndexProvider.notifier).state = 0; // Switch to Add Product tab
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _skipTutorial() {
    _ttsService.stop();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSlide = _slides[_currentPage];
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // --- Top App Bar Area ---
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  // Close / Back button
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26, color: AppColors.charcoal),
                    tooltip: 'close'.tr(),
                    onPressed: _skipTutorial,
                  ),

                  // Center Step Indicator Badge
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          currentSlide.isIntro
                              ? 'overview'.tr()
                              : currentSlide.isOutro
                                  ? 'ready_to_list'.tr()
                                  : 'step_counter'.tr(
                                      namedArgs: {
                                        'current': '${currentSlide.stepIndex}',
                                        'total': '5',
                                      },
                                    ),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Voice Narration Button
                  IconButton(
                    icon: Icon(
                      _ttsService.isPlaying
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      color: _ttsService.isPlaying ? AppColors.terracotta : AppColors.charcoal,
                    ),
                    tooltip: _ttsService.isPlaying
                        ? 'stop_narration'.tr()
                        : 'listen_narration'.tr(),
                    onPressed: _toggleSpeakCurrentSlide,
                  ),

                  // Skip Button
                  if (!isLastPage)
                    TextButton(
                      onPressed: _skipTutorial,
                      child: Text(
                        'skip'.tr(),
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.charcoalSoft,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // --- Main Swipeable PageView ---
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return TutorialCardWidget(
                    slide: _slides[index],
                    isSpeaking: _ttsService.isPlaying && _currentPage == index,
                    onToggleSpeak: _toggleSpeakCurrentSlide,
                  );
                },
              ),
            ),

            // --- Bottom Navigation & Progress Pill Bar ---
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Smooth Animated Indicator Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slides.length, (index) {
                        final isSelected = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 7,
                          width: isSelected ? 26 : 7,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.terracotta
                                : AppColors.border.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Navigation Action Buttons
                    Row(
                      children: [
                        // Previous button (if not first slide)
                        if (_currentPage > 0) ...[
                          IconButton.outlined(
                            onPressed: _goToPrevious,
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.charcoal),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],

                        // Next / Start Listing Button
                        Expanded(
                          child: AppButton(
                            label: isLastPage
                                ? 'start_listing_btn'.tr()
                                : 'next'.tr(),
                            icon: isLastPage
                                ? Icons.rocket_launch_rounded
                                : Icons.arrow_forward_rounded,
                            onPressed: _goToNext,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
