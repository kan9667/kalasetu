import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_text_styles.dart';
import '../widgets/step_progress_bar.dart';
import '../widgets/step1_capture_widget.dart';
import '../widgets/step2_describe_widget.dart';
import '../widgets/step3_ai_review_widget.dart';
import '../widgets/step4_pricing_widget.dart';
import '../widgets/step5_confirm_widget.dart';

class AddProductFlowScreen extends ConsumerWidget {
  const AddProductFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(addProductFlowProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;
    final currentStep = draft.currentStep;

    // ── Full-screen: Pricing loading/offline (Step 3 → 4) ───────────────────
    // These replace the whole tree because submitForPricingAndAdvance() awaits
    // internally — Step3 does not need to stay mounted during pricing.
    if (draft.isPricingProcessing && isOnline) {
      return _FullScreenAiLoading(
        title: 'Calculating your fair price',
        subtitle:
            'AI is analysing material costs, labour time, and market data to suggest the best price for your product.',
        icon: Icons.monetization_on_outlined,
        onCancel: () =>
            ref.read(addProductFlowProvider.notifier).cancelPricingProcessing(),
      );
    }
    if (draft.isPricingProcessing && !isOnline) {
      return const _FullScreenOfflinePricing();
    }

    // ── Full-screen: AI loading / offline waiting (Step 2 → 3) ───────────────
    // Same pattern as pricing above: a genuine full-screen replacement, not a
    // Stack overlay on top of Step2/Step3 — those widgets do not need to stay
    // mounted for this transition. (The old Stack-overlay approach let
    // Step2DescribeWidget's own local loader show instead, which looked like
    // a popup rather than a full screen.)
    //
    // IMPORTANT: check offline *before* isAiProcessing, and only show the AI
    // loader when isOnline. isAiProcessing can still be true for a moment
    // after connectivity actually drops (e.g. a request was already in
    // flight when the network went away) — without the isOnline guard here,
    // that stale flag wins the race and this shows "Enhancing image..."
    // forever instead of falling through to the offline screen, exactly
    // like the pricing screens below already guard against.
    if (currentStep == 2 &&
        !isOnline &&
        draft.titleEn.isEmpty &&
        draft.originalImagePath.isNotEmpty) {
      return const _FullScreenOfflineWaiting();
    }
    if (currentStep == 2 &&
        isOnline &&
        draft.isAiProcessing &&
        !draft.isRegenerating) {
      return _FullScreenAiLoading(
        title: 'Enhancing image and creating listing',
        subtitle:
            'AI is enhancing your product photo and generating your catalog listing. This usually takes a few seconds.',
        icon: Icons.auto_awesome,
        onCancel: () =>
            ref.read(addProductFlowProvider.notifier).cancelAiProcessing(),
      );
    }

    final steps = const [
      Step1CaptureWidget(),
      Step2DescribeWidget(),
      Step3AiReviewWidget(),
      Step4PricingWidget(),
      Step5ConfirmWidget(),
    ];

    return AppScaffold(
      title: 'tab_add_product'.tr(),
      automaticallyImplyLeading: false,
      leading: currentStep > 0
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                ref.read(addProductFlowProvider.notifier).previousStep();
              },
            )
          : null,
      body: Column(
        children: [
          StepProgressBar(
            currentStep: currentStep,
            onStepTapped: (step) {
              if (step <= currentStep) {
                ref.read(addProductFlowProvider.notifier).setStep(step);
              }
            },
          ),
          Expanded(
            child: IndexedStack(
              index: currentStep,
              children: steps,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen loading widget (AI processing & pricing calculation)
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenAiLoading extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onCancel;

  const _FullScreenAiLoading({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onCancel,
  });

  @override
  State<_FullScreenAiLoading> createState() => _FullScreenAiLoadingState();
}

class _FullScreenAiLoadingState extends State<_FullScreenAiLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  bool _showCancel = false;
  Timer? _cancelTimer;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    // Safety net: if this is still showing after 15s (e.g. an unreachable
    // backend on a request that lacks its own timeout), offer a way out
    // instead of trapping the user on a full screen with no back button.
    _cancelTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _showCancel = true);
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _cancelTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F2),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _glowAnim,
                  builder: (context, _) {
                    return Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF5EFE6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFC86D51).withValues(
                              alpha: 0.18 + 0.22 * _glowAnim.value,
                            ),
                            blurRadius: 20 + 14 * _glowAnim.value,
                            spreadRadius: 4 + 6 * _glowAnim.value,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 38,
                        color: Color.lerp(
                          const Color(0xFFC86D51),
                          const Color(0xFFE8956A),
                          _glowAnim.value,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFFC86D51),
                    backgroundColor: Color(0xFFEBE3D5),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.title,
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.subtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFF7A6E63),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                _AnimatedDots(),
                if (_showCancel && widget.onCancel != null) ...[
                  const SizedBox(height: 36),
                  Text(
                    'Taking longer than expected?',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: const Color(0xFF9E8F80),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: Color(0xFF8C533E),
                    ),
                    label: const Text(
                      'Go back',
                      style: TextStyle(
                        color: Color(0xFF8C533E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD6C7B2)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed-height box so the bouncing dots never change the Row's layout
    // size. Previously the Row's height tracked whichever dot was tallest
    // at that instant (8–14px, shifting every frame), which changed the
    // height of the whole mainAxisSize.min Column above it — since that
    // Column is centered on screen, the entire loading screen content
    // visibly jittered up and down in sync with the dot animation. Sizing
    // the box to the max dot height and bottom-aligning the dots inside it
    // keeps the Row's footprint constant while still letting the dots
    // bounce freely within it.
    return SizedBox(
      height: 14,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final progress = (_ctrl.value - delay).clamp(0.0, 1.0);
              final bounce = (progress < 0.5 ? progress : 1.0 - progress) * 2.0;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 8,
                height: 8.0 + 6.0 * bounce,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFD6C7B2),
                    const Color(0xFFC86D51),
                    bounce,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen offline waiting widget
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenOfflineWaiting extends ConsumerStatefulWidget {
  const _FullScreenOfflineWaiting();

  @override
  ConsumerState<_FullScreenOfflineWaiting> createState() =>
      _FullScreenOfflineWaitingState();
}

class _FullScreenOfflineWaitingState
    extends ConsumerState<_FullScreenOfflineWaiting>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F2),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0EBE3),
                    border: Border.all(
                      color: const Color(0xFFD6C7B2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: Color(0xFF9E8F80),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'You\'re offline',
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your photo has been saved. Once you\'re back online, we\'ll enhance your image and generate your listing automatically.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFF7A6E63),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: Color.lerp(
                            const Color(0xFFD6C7B2),
                            const Color(0xFF9E8F80),
                            _pulseCtrl.value,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Waiting for connection...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color.lerp(
                              const Color(0xFFB3A99A),
                              const Color(0xFF7A6E63),
                              _pulseCtrl.value,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(addProductFlowProvider.notifier).previousStep();
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: Color(0xFF8C533E),
                  ),
                  label: const Text(
                    'Go back & edit',
                    style: TextStyle(
                      color: Color(0xFF8C533E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD6C7B2)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline pricing screen (shown when "Looks Good!" is tapped while offline)
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenOfflinePricing extends ConsumerWidget {
  const _FullScreenOfflinePricing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF8F2),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0EBE3),
                    border: Border.all(
                      color: const Color(0xFFD6C7B2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: Color(0xFF9E8F80),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'You\'re offline',
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'AI pricing needs an internet connection. We\'ll use an estimated price for now — you can update it once you\'re back online.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFF7A6E63),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Continue with estimated pricing
                ElevatedButton.icon(
                  onPressed: () {
                    ref
                        .read(addProductFlowProvider.notifier)
                        .submitForPricingAndAdvance();
                  },
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Continue with estimate',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC86D51),
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(addProductFlowProvider.notifier).previousStep();
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: Color(0xFF8C533E),
                  ),
                  label: const Text(
                    'Go back',
                    style: TextStyle(
                      color: Color(0xFF8C533E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD6C7B2)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}