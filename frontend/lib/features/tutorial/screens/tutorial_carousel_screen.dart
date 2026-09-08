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
      final ttsText = currentSlide.ttsKey.tr();
      _ttsService.speak(ttsText, languageCode: context.locale.languageCode);
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
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.sm,
              ),
              child: SizedBox(
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Center Step Indicator Badge
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                          border: Border.all(
                            color: AppColors.border.withValues(alpha: 0.6),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          currentSlide.isIntro
                              ? 'overview'.tr()
                              : currentSlide.isOutro
                                  ? 'ready_to_list'.tr()
                                  : 'step_counter'.tr(
                                      namedArgs: {
                                        'current': '${currentSlide.stepIndex}',
                                        'total': '6',
                                      },
                                    ),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Skip Action Button
                    if (!isLastPage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _skipTutorial,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'skip'.tr(),
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
                            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
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
