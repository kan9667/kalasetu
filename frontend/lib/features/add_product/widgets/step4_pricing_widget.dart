import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/providers/app_providers.dart';

class Step4PricingWidget extends ConsumerStatefulWidget {
  const Step4PricingWidget({super.key});

  @override
  ConsumerState<Step4PricingWidget> createState() => _Step4PricingWidgetState();
}

class _Step4PricingWidgetState extends ConsumerState<Step4PricingWidget> {
  final TextEditingController _materialCostCtrl = TextEditingController();
  final TextEditingController _laborHoursCtrl = TextEditingController();
  final TextEditingController _hourlyRateCtrl = TextEditingController();
  bool _showCostBreakdown = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(addProductFlowProvider);
    _materialCostCtrl.text = draft.rawMaterialCost.toStringAsFixed(0);
    _laborHoursCtrl.text = draft.laborHours.toStringAsFixed(1);
    _hourlyRateCtrl.text = draft.hourlyRate.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _materialCostCtrl.dispose();
    _laborHoursCtrl.dispose();
    _hourlyRateCtrl.dispose();
    super.dispose();
  }

  void _onCostChanged() {
    final mat = double.tryParse(_materialCostCtrl.text) ?? 0.0;
    final hours = double.tryParse(_laborHoursCtrl.text) ?? 0.0;
    final rate = double.tryParse(_hourlyRateCtrl.text) ?? 0.0;

    ref.read(addProductFlowProvider.notifier).updateCostParameters(
          materialCost: mat,
          laborHours: hours,
          hourlyRate: rate,
        );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    bool isHindi = false;
    try {
      isHindi = context.locale.languageCode == 'hi';
    } catch (_) {}

    // Slider bounds: min price cannot drop below ethical floorPrice!
    final sliderMin = draft.floorPrice;
    final sliderMax = draft.maxPrice > sliderMin ? draft.maxPrice : (sliderMin + 1000.0);
    final sliderValue = draft.finalPrice.clamp(sliderMin, sliderMax);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on, color: AppColors.terracotta),
              const SizedBox(width: AppSpacing.xs),
              Text('pricing_title'.tr(), style: AppTextStyles.headlineLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'pricing_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Price Display Hero Box
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.indigo, AppColors.indigoDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'price_slider_label'.tr(),
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.surfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '₹${draft.finalPrice.toStringAsFixed(0)}',
                  style: AppTextStyles.displayLarge.copyWith(
                    color: AppColors.turmeric,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.stars, color: AppColors.turmericLight, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${'suggested_price'.tr()}: ₹${draft.suggestedPrice.toStringAsFixed(0)}',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.textOnPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Interactive Price Slider (Ethical Hard Floor Guarded)
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.terracotta,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.terracotta,
                  overlayColor: AppColors.terracottaLight.withValues(alpha: 0.2),
                  valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                  valueIndicatorColor: AppColors.terracotta,
                  valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                ),
                child: Slider(
                  value: sliderValue,
                  min: sliderMin,
                  max: sliderMax,
                  divisions: 50,
                  label: '₹${sliderValue.toStringAsFixed(0)}',
                  onChanged: (val) {
                    ref.read(addProductFlowProvider.notifier).setFinalPrice(val);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${'calculated_floor_price'.tr()}: ₹${draft.floorPrice.toStringAsFixed(0)}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.error),
                  ),
                  Text(
                    'Max: ₹${sliderMax.toStringAsFixed(0)}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // AI Reasoning Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology, color: AppColors.indigo, size: 22),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'ai_reasoning'.tr(),
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  isHindi ? draft.pricingReasoningHi : draft.pricingReasoning,
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Expandable Cost Breakdown & Ethical Floor Calculator
          ExpansionTile(
            title: Text(
              'cost_breakdown_toggle'.tr(),
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.forestGreen),
            ),
            leading: const Icon(Icons.shield, color: AppColors.forestGreen),
            initiallyExpanded: _showCostBreakdown,
            onExpansionChanged: (val) => setState(() => _showCostBreakdown = val),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  children: [
                    TextField(
                      controller: _materialCostCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'raw_materials_cost'.tr(),
                        prefixText: '₹ ',
                      ),
                      onChanged: (val) => _onCostChanged(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _laborHoursCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'labour_hours'.tr(),
                              suffixText: 'hrs',
                            ),
                            onChanged: (val) => _onCostChanged(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            controller: _hourlyRateCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'hourly_rate'.tr(),
                              prefixText: '₹ ',
                            ),
                            onChanged: (val) => _onCostChanged(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.forestGreenLight.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified, color: AppColors.forestGreen, size: 20),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              '${'calculated_floor_price'.tr()}: ₹${draft.floorPrice.toStringAsFixed(0)} (Price slider cannot be dragged below this lower bound)',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.forestGreenDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          AppButton(
            label: 'next'.tr(),
            icon: Icons.arrow_forward,
            onPressed: () {
              ref.read(addProductFlowProvider.notifier).nextStep();
            },
          ),
        ],
      ),
    );
  }
}
