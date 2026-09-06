import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/providers/app_providers.dart';

class Step4PricingWidget extends ConsumerStatefulWidget {
  const Step4PricingWidget({super.key});

  @override
  ConsumerState<Step4PricingWidget> createState() => _Step4PricingWidgetState();
}

class _Step4PricingWidgetState extends ConsumerState<Step4PricingWidget> {
  bool _showCostBreakdown = false;
  bool _showMarketBenchmarks = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);

    final minBound = (draft.floorPrice * 0.5).clamp(100.0, 5000.0);
    final maxBound = (draft.suggestedPrice * 1.8).clamp(minBound + 200.0, 15000.0);
    final currentPrice = draft.finalPrice.clamp(minBound, maxBound);

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on_outlined, color: Color(0xFFC86D51), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('pricing_title'.tr(), style: AppTextStyles.headlineMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'pricing_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF7A6E63)),
          ),
          const SizedBox(height: 20),

          // Simple, clean price container without gradient
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5EFE6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDFD5C6), width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  'price_slider_label'.tr(),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF7A6E63), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  '₹${currentPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3F342B),
                    fontFamily: 'serif',
                  ),
                ),
                const SizedBox(height: 6),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC86D51).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFC86D51)),
                          const SizedBox(width: 4),
                          Text(
                            '${'suggested_price'.tr()}: ₹${draft.suggestedPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC86D51),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF437A57).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_outlined, size: 14, color: Color(0xFF437A57)),
                          const SizedBox(width: 4),
                          Text(
                            '${(draft.confidenceScore * 100).toStringAsFixed(0)}% Match',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF437A57),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5E3C).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        draft.marketPosition.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: Color(0xFF8B5E3C),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Muted Gradient Slider: Red -> Green -> Yellow
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
                      Color(0xFFD47A6A), // Muted red (below fair floor)
                      Color(0xFF6F9D7C), // Muted green (fair pricing sweet spot)
                      Color(0xFFE2B866), // Muted yellow/gold (premium margin)
                    ],
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 0,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: const Color(0xFF3F342B),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  overlayColor: const Color(0xFF3F342B).withValues(alpha: 0.12),
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
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${'calculated_floor_price'.tr()}: ₹${draft.floorPrice.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: currentPrice < draft.floorPrice ? const Color(0xFFB34A38) : const Color(0xFF7A6E63),
                  ),
                ),
                Text(
                  'Max: ₹${maxBound.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7A6E63)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Pricing Reasoning
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF7F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8DFD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_outlined, size: 18, color: Color(0xFF5A4D41)),
                    const SizedBox(width: 6),
                    Text(
                      'ai_reasoning'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5A4D41), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  draft.pricingReasoning,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6F6358), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Cost Breakdown Accordion
          InkWell(
            onTap: () => setState(() => _showCostBreakdown = !_showCostBreakdown),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF7F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8DFD3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 20, color: Color(0xFF437A57)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'cost_breakdown_toggle'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF437A57),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _showCostBreakdown ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF437A57),
                  ),
                ],
              ),
            ),
          ),

          if (_showCostBreakdown) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3EDE2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _CostItem(
                    label: 'raw_materials_cost'.tr(),
                    value: '₹${draft.rawMaterialCost.toStringAsFixed(0)}',
                  ),
                  const Divider(height: 16),
                  _CostItem(
                    label: 'labour_hours'.tr(),
                    value: '${draft.laborHours} hrs',
                  ),
                  const Divider(height: 16),
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
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF7F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8DFD3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 20, color: Color(0xFF8B5E3C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      draft.comparableProducts.isNotEmpty
                          ? 'Market Benchmarks (${draft.comparableProducts.length} similar crafts)'
                          : 'Market Benchmarks (AI RAG)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B5E3C),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _showMarketBenchmarks ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF8B5E3C),
                  ),
                ],
              ),
            ),
          ),

          if (_showMarketBenchmarks) ...[
            const SizedBox(height: 10),
            if (draft.comparableProducts.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EDE2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Cost-floor safety active. Connect to online backend to retrieve live e-commerce benchmarks across Amazon Karigar, FabIndia, and Okhai.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7A6E63)),
                ),
              )
            else
              ...draft.comparableProducts.map(
                (comp) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF9F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8DFD3)),
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
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3F342B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEDE4D8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    comp.sourcePlatform,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF5A4D41)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(comp.similarityScore * 100).toStringAsFixed(0)}% match',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF437A57),
                                    fontWeight: FontWeight.w500,
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC86D51),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.read(addProductFlowProvider.notifier).nextStep(),
            icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            label: Text('next'.tr(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC86D51),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
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
        Text(label, style: const TextStyle(color: Color(0xFF6F6358), fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3F342B), fontSize: 13)),
      ],
    );
  }
}