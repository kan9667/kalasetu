import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/providers/app_providers.dart';

class Step4PricingWidget extends ConsumerStatefulWidget {
  const Step4PricingWidget({super.key});

  @override
  ConsumerState<Step4PricingWidget> createState() => _Step4PricingWidgetState();
}

class _Step4PricingWidgetState extends ConsumerState<Step4PricingWidget> {
  bool _showCostBreakdown = false;

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
                    Text(
                      'ai_reasoning'.tr(),
                      style: AppTextStyles.headlineSmall.copyWith(color: AppColors.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  draft.pricingReasoning,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.ink,
                    height: 1.4,
                  ),
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
                  const Icon(Icons.shield_outlined, size: 20, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'cost_breakdown_toggle'.tr(),
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  Icon(
                    _showCostBreakdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.success,
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