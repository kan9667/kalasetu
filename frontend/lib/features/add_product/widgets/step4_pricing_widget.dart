import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/widgets/speaker_affordance.dart';
import '../../../core/providers/app_providers.dart';

class Step4PricingWidget extends ConsumerStatefulWidget {
  const Step4PricingWidget({super.key});

  @override
  ConsumerState<Step4PricingWidget> createState() => _Step4PricingWidgetState();
}

class _Step4PricingWidgetState extends ConsumerState<Step4PricingWidget> {
  bool _showCostBreakdown = false;
  bool _showMarketBenchmarks = false;
  final AppTtsService _tts = AppTtsService();

  @override
  void initState() {
    super.initState();
    _tts.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  // The suggested price comes with an AI-written justification — the
  // artisan should be able to verify why this price was suggested without
  // needing to read it. The price itself is stated first and explicitly,
  // since the reasoning text does not reliably repeat the number in a
  // form that reads naturally aloud, and the ₹ figure on screen is not
  // something a non-reading artisan can otherwise access.
  Future<void> _speakReasoning(double price, String reasoningEn, String reasoningHi) async {
    if (_tts.isSpeaking) {
      await _tts.stop();
      return;
    }
    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final langCode = isHindi ? 'hi' : 'en';
    final reasoning = isHindi && reasoningHi.isNotEmpty ? reasoningHi : reasoningEn;
    final guide = TtsPageGuides.pricing.forLanguage(langCode);
    final priceStatement = isHindi
        ? 'सुझाया गया मूल्य ${price.toStringAsFixed(0)} रुपये है। '
        : 'The suggested price is ${price.toStringAsFixed(0)} rupees. ';
    final result = await _tts.speak(
      guide + priceStatement + reasoning,
      languageCode: langCode,
    );
    if (result == TtsResult.voiceUnavailable && mounted) {
      final opened = await _tts.openVoiceDownloadScreen();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('voice_download_settings_hint'.tr()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);

    final minBound = (draft.floorPrice * 0.5).clamp(100.0, 5000.0);
    final maxBound = (draft.suggestedPrice * 1.8).clamp(minBound + 200.0, 15000.0);
    final currentPrice = draft.finalPrice.clamp(minBound, maxBound);

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sell_outlined, color: AppColors.terracotta, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('pricing_title'.tr(), style: AppTextStyles.headlineLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'pricing_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),

          // Price hero container with card styling
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.line),
              boxShadow: AppElevation.cardShadow,
            ),
            child: Column(
              children: [
                Text(
                  'price_slider_label'.tr().toUpperCase(),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${currentPrice.toStringAsFixed(0)}',
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.terracottaDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.goldLight,
                        borderRadius: BorderRadius.circular(AppRadii.button),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 14, color: AppColors.goldDark),
                          const SizedBox(width: 6),
                          Text(
                            '${'suggested_price'.tr()}: ₹${draft.suggestedPrice.toStringAsFixed(0)}',
                            style: AppTextStyles.labelSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.goldDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadii.button),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_outlined, size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(
                            'score_match'.tr(namedArgs: {
                              'score': (draft.confidenceScore * 100).toStringAsFixed(0),
                            }),
                            style: AppTextStyles.labelSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadii.button),
                      ),
                      child: Text(
                        draft.marketPosition.toUpperCase(),
                        style: AppTextStyles.labelSmall.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: AppColors.terracottaDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Muted Gradient Slider: Red -> Green -> Gold
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.terracottaLight, // Below fair floor
                      AppColors.success,         // Fair pricing sweet spot
                      AppColors.gold,            // Premium margin
                    ],
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 0,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: AppColors.ink,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  overlayColor: AppColors.ink.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: currentPrice,
                  min: minBound,
                  max: maxBound,
                  divisions: 50,
                  onChanged: (val) {
                    ref.read(addProductFlowProvider.notifier).setFinalPrice(val);
                  },
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${'calculated_floor_price'.tr()}: ₹${draft.floorPrice.toStringAsFixed(0)}',
                  style: AppTextStyles.labelSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: currentPrice < draft.floorPrice ? AppColors.error : AppColors.inkSoft,
                  ),
                ),
                Text(
                  'Max: ₹${maxBound.toStringAsFixed(0)}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Pricing Reasoning Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.line),
              boxShadow: AppElevation.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_outlined, size: 18, color: AppColors.terracotta),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ai_reasoning'.tr(),
                        style: AppTextStyles.headlineSmall.copyWith(color: AppColors.ink),
                      ),
                    ),
                    SpeakerAffordance(
                      isSpeaking: _tts.isSpeaking,
                      onTap: () => _speakReasoning(
                        currentPrice,
                        draft.pricingReasoning,
                        draft.pricingReasoningHi,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
                            EasyLocalization.of(context)?.locale.languageCode) ==
                        'hi';
                    return Text(
                      isHindi && draft.pricingReasoningHi.isNotEmpty
                          ? draft.pricingReasoningHi
                          : draft.pricingReasoning,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.ink,
                        height: 1.4,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Cost Breakdown Accordion
          InkWell(
            onTap: () => setState(() => _showCostBreakdown = !_showCostBreakdown),
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
                boxShadow: AppElevation.cardShadow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 18, color: AppColors.terracotta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'cost_breakdown_floor_title'.tr(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showCostBreakdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.inkSoft,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          if (_showCostBreakdown) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.parchmentDeep,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  _CostItem(
                    label: 'raw_materials_cost'.tr(),
                    value: '₹${draft.rawMaterialCost.toStringAsFixed(0)}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: DottedBorderBox.divider(),
                  ),
                  _CostItem(
                    label: 'labour_hours'.tr(),
                    value: '${draft.laborHours} hrs',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: DottedBorderBox.divider(),
                  ),
                  _CostItem(
                    label: 'hourly_rate'.tr(),
                    value: '₹${draft.hourlyRate.toStringAsFixed(0)}/hr',
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Market Benchmarks Accordion
          InkWell(
            onTap: () => setState(() => _showMarketBenchmarks = !_showMarketBenchmarks),
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
                boxShadow: AppElevation.cardShadow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 18, color: AppColors.terracotta),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      draft.comparableProducts.isNotEmpty
                          ? 'market_benchmarks_with_count'.tr(namedArgs: {
                              'count': '${draft.comparableProducts.length}',
                            })
                          : 'market_benchmarks_title'.tr(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showMarketBenchmarks ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.inkSoft,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          if (_showMarketBenchmarks) ...[
            const SizedBox(height: 10),
            if (draft.comparableProducts.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.parchmentDeep,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  'offline_benchmarks_notice'.tr(),
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
                ),
              )
            else
              ...draft.comparableProducts.map(
                (comp) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: AppColors.line),
                    boxShadow: AppElevation.cardShadow,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comp.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.goldLight,
                                    borderRadius: BorderRadius.circular(AppRadii.button),
                                  ),
                                  child: Text(
                                    comp.sourcePlatform,
                                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.goldDark),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'score_match'.tr(namedArgs: {
                                    'score': (comp.similarityScore * 100).toStringAsFixed(0),
                                  }),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '₹${comp.sellingPrice.toStringAsFixed(0)}',
                        style: AppTextStyles.headlineMedium.copyWith(
                          color: AppColors.terracottaDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 24),
          AppButton(
            label: 'next'.tr(),
            icon: Icons.arrow_forward,
            onPressed: () => ref.read(addProductFlowProvider.notifier).nextStep(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _CostItem extends StatelessWidget {
  final String label;
  final String value;
  const _CostItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft)),
        Text(value, style: AppTextStyles.headlineSmall.copyWith(color: AppColors.ink)),
      ],
    );
  }
}