import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

/// Data model representing a guidance cue for artisan onboarding,
/// photography tips, and description suggestions.
class GuidanceCue {
  /// User-facing text to display.
  final String text;

  /// Optional icon representing the action or tip.
  final IconData? icon;

  /// Optional text to insert into text field on tap (e.g. for Step 2).
  final String? insertText;

  /// Placeholder key for packaged audio asset for future TTS.
  final String? audioAssetKey;

  /// Placeholder key for remote/cloud TTS synthesis.
  final String? ttsKey;

  const GuidanceCue({
    required this.text,
    this.icon,
    this.insertText,
    this.audioAssetKey,
    this.ttsKey,
  });
}

/// An auto-cycling, fade-transition guidance cue component designed for
/// low-literacy users with TTS readiness, manual navigation, and progress dots.
class CyclingGuidanceCue extends StatefulWidget {
  /// The list of guidance cues to cycle through.
  final List<GuidanceCue> cues;

  /// Optional section header title (e.g. "PHOTO TIPS").
  final String? headerTitle;

  /// Optional section header icon.
  final IconData? headerIcon;

  /// Callback fired whenever the active cue changes (auto or manual).
  /// Ready to trigger Text-to-Speech playback.
  final ValueChanged<GuidanceCue>? onCueChanged;

  /// Callback fired when the user taps the cue content.
  final ValueChanged<GuidanceCue>? onCueTap;

  /// Whether auto-cycling is currently paused (e.g. while user is typing,
  /// recording voice, or picking a photo).
  final bool isPaused;

  /// Cycle interval between automatic advances. Defaults to 3.8 seconds.
  final Duration interval;

  const CyclingGuidanceCue({
    super.key,
    required this.cues,
    this.headerTitle,
    this.headerIcon,
    this.onCueChanged,
    this.onCueTap,
    this.isPaused = false,
    this.interval = const Duration(milliseconds: 3800),
  });

  @override
  State<CyclingGuidanceCue> createState() => _CyclingGuidanceCueState();
}

class _CyclingGuidanceCueState extends State<CyclingGuidanceCue> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.isPaused && widget.cues.length > 1) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant CyclingGuidanceCue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _stopTimer();
      } else {
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _startTimer() {
    _stopTimer();
    if (widget.cues.length <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || widget.isPaused) return;
      _nextCue(autoAdvance: true);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _resetTimer() {
    if (!widget.isPaused && widget.cues.length > 1) {
      _startTimer();
    }
  }

  void _nextCue({bool autoAdvance = false}) {
    if (widget.cues.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.cues.length;
    });
    final cue = widget.cues[_currentIndex];
    // TODO: hook TTS playback here via onCueChanged
    widget.onCueChanged?.call(cue);
    if (!autoAdvance) {
      _resetTimer();
    }
  }

  void _previousCue() {
    if (widget.cues.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + widget.cues.length) % widget.cues.length;
    });
    final cue = widget.cues[_currentIndex];
    // TODO: hook TTS playback here via onCueChanged
    widget.onCueChanged?.call(cue);
    _resetTimer();
  }

  void _onHearAffordanceTap(GuidanceCue currentCue) {
    // TODO: hook TTS playback here via onCueChanged
    widget.onCueChanged?.call(currentCue);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔊 Reading aloud: "${currentCue.text}" (TTS Audio Coming Soon)'),
        backgroundColor: AppColors.terracottaDark,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cues.isEmpty) return const SizedBox.shrink();

    final currentCue = widget.cues[_currentIndex];
    final hasMultiple = widget.cues.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: AppColors.terracotta.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.line,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with title & persistent audio affordance
          if (widget.headerTitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Row(
                children: [
                  if (widget.headerIcon != null) ...[
                    Icon(
                      widget.headerIcon,
                      size: 14,
                      color: AppColors.terracottaDark,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      widget.headerTitle!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.terracottaDark,
                      ),
                    ),
                  ),
                  // Persistent "Tap to hear" affordance for TTS readiness
                  InkWell(
                    onTap: () => _onHearAffordanceTap(currentCue),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadii.chip),
                        border: Border.all(
                          color: AppColors.terracotta.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.volume_up_rounded,
                            size: 13,
                            color: AppColors.terracottaDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to hear',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.terracottaDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main Cue display with manual chevrons and swipe gesture
          GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null || !hasMultiple) return;
              if (details.primaryVelocity! < -100) {
                _nextCue();
              } else if (details.primaryVelocity! > 100) {
                _previousCue();
              }
            },
            child: Row(
              children: [
                // Left chevron button
                if (hasMultiple)
                  Semantics(
                    button: true,
                    label: 'Previous tip',
                    child: InkWell(
                      onTap: _previousCue,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 24,
                          color: AppColors.terracottaDark,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 36),

                // Center crossfade content
                Expanded(
                  child: InkWell(
                    onTap: widget.onCueTap != null
                        ? () => widget.onCueTap!(currentCue)
                        : () => _onHearAffordanceTap(currentCue),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: Row(
                          key: ValueKey<int>(_currentIndex),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (currentCue.icon != null) ...[
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.terracotta.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  currentCue.icon,
                                  size: 18,
                                  color: AppColors.terracottaDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                currentCue.text,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            if (widget.onCueTap != null) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.add_circle_outline_rounded,
                                size: 16,
                                color: AppColors.terracotta,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Right chevron button
                if (hasMultiple)
                  Semantics(
                    button: true,
                    label: 'Next tip',
                    child: InkWell(
                      onTap: () => _nextCue(),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 24,
                          color: AppColors.terracottaDark,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 36),
              ],
            ),
          ),

          // Progress indicator dots
          if (hasMultiple) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.cues.length, (index) {
                final isCurrent = index == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: isCurrent ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.terracotta
                        : AppColors.oak.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
