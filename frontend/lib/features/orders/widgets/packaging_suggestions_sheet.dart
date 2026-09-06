import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';

class _PackagingStep {
  final IconData icon;
  final String title;
  final String detail;
  const _PackagingStep({required this.icon, required this.title, required this.detail});
}

Map<String, List<_PackagingStep>> _guideForCategory(String category) {
  final cat = category.toLowerCase();
  if (cat.contains('pottery') || cat.contains('ceramic')) {
    return {
      'pottery': [
        _PackagingStep(icon: Icons.layers, title: 'Wrap in tissue paper', detail: 'Use 2-3 layers of acid-free tissue to protect the glaze.'),
        _PackagingStep(icon: Icons.bubble_chart, title: 'Bubble wrap (5cm)', detail: 'Apply at least two layers of small-cell bubble wrap secured with tape.'),
        _PackagingStep(icon: Icons.check_box, title: 'Double-box method', detail: 'Place in a snug inner box, then a larger outer box with 5 cm foam padding on all sides.'),
        _PackagingStep(icon: Icons.warning_amber, title: 'Mark "Fragile"', detail: 'Add FRAGILE stickers on all 6 faces of the outer box.'),
      ],
    };
  } else if (cat.contains('textile') || cat.contains('fabric') || cat.contains('saree') || cat.contains('cloth')) {
    return {
      'textile': [
        _PackagingStep(icon: Icons.layers_outlined, title: 'Fold along natural creases', detail: 'Fold garments carefully along natural drape lines to avoid permanent creases.'),
        _PackagingStep(icon: Icons.water_drop, title: 'Moisture-proof bag', detail: 'Seal in a zip-lock polythene bag to protect against humidity.'),
        _PackagingStep(icon: Icons.inventory_2, title: 'Rigid box', detail: 'Place in a sturdy cardboard box — avoid vacuum-sealing or over-compressing.'),
        _PackagingStep(icon: Icons.sticky_note_2, title: 'Care card inside', detail: 'Include a handwritten or printed care instruction card.'),
      ],
    };
  } else if (cat.contains('jewel') || cat.contains('silver') || cat.contains('gold') || cat.contains('bead')) {
    return {
      'jewelry': [
        _PackagingStep(icon: Icons.diamond, title: 'Anti-tarnish pouch', detail: 'Place each piece individually in an anti-tarnish zip pouch.'),
        _PackagingStep(icon: Icons.padding, title: 'Padded insert', detail: 'Nest pouches in a velvet or foam-lined jewelry box.'),
        _PackagingStep(icon: Icons.lock, title: 'Secure the lid', detail: 'Tape the box lid and wrap in bubble wrap before final boxing.'),
        _PackagingStep(icon: Icons.local_shipping, title: 'Insurance recommended', detail: 'Declare the value and opt for shipping insurance for high-value items.'),
      ],
    };
  } else if (cat.contains('wood') || cat.contains('bamboo') || cat.contains('cane')) {
    return {
      'woodwork': [
        _PackagingStep(icon: Icons.forest, title: 'Dry completely', detail: 'Ensure the wood is fully dry and oiled before packing to prevent cracking.'),
        _PackagingStep(icon: Icons.bubble_chart, title: 'Bubble wrap joints', detail: 'Give extra wrap to joints, corners, and carvings.'),
        _PackagingStep(icon: Icons.check_box, title: 'Foam-lined box', detail: 'Use a box with 3 cm foam lining on all sides.'),
        _PackagingStep(icon: Icons.warning_amber, title: 'Keep away from heat', detail: 'Mark "Keep away from sunlight and heat" on the outer package.'),
      ],
    };
  } else if (cat.contains('paint') || cat.contains('art') || cat.contains('canvas')) {
    return {
      'paintings': [
        _PackagingStep(icon: Icons.palette, title: 'Glassine paper face', detail: 'Place glassine paper directly on the painted surface to protect it.'),
        _PackagingStep(icon: Icons.layers, title: 'Cardboard backing', detail: 'Sandwich between two rigid cardboard pieces cut to size.'),
        _PackagingStep(icon: Icons.local_shipping, title: 'Flat shipping', detail: 'Ship flat, never rolled, unless it is a canvas-only piece.'),
        _PackagingStep(icon: Icons.warning_amber, title: 'Label orientation', detail: 'Mark "THIS SIDE UP" and "Do not bend" on the package.'),
      ],
    };
  } else {
    // Generic
    return {
      'general': [
        _PackagingStep(icon: Icons.bubble_chart, title: 'Wrap in bubble wrap', detail: 'Use at least 2 layers of bubble wrap secured with tape.'),
        _PackagingStep(icon: Icons.check_box, title: 'Snug-fitting box', detail: 'Choose a box slightly larger than the item, fill gaps with packing peanuts or crumpled paper.'),
        _PackagingStep(icon: Icons.warning_amber, title: 'Label clearly', detail: 'Write order ID, buyer name, and destination clearly on the outside.'),
        _PackagingStep(icon: Icons.local_shipping, title: 'Seal all edges', detail: 'Use packing tape on all seams and edges of the outer box.'),
      ],
    };
  }
}

void showPackagingSuggestionsSheet(BuildContext context, {required String category}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PackagingSuggestionsSheet(category: category),
  );
}

class PackagingSuggestionsSheet extends StatelessWidget {
  final String category;
  const PackagingSuggestionsSheet({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final steps = _guideForCategory(category).values.first;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.bottomSheet)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.inventory_2_outlined, color: AppColors.terracotta, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('packaging_suggestions_title'.tr(), style: AppTextStyles.headlineSmall),
                          Text(
                            category,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // Steps
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    final step = steps[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step number + icon
                          Column(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.terracotta.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: AppColors.terracotta,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              if (index < steps.length - 1)
                                Container(
                                  width: 2,
                                  height: 32,
                                  color: AppColors.terracotta.withOpacity(0.2),
                                ),
                            ],
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(step.icon, size: 16, color: AppColors.terracotta),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(step.title, style: AppTextStyles.labelMedium),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  step.detail,
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
