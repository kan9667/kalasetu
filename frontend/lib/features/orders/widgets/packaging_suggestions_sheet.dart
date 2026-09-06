import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';

class _PackagingStep {
  final IconData icon;
  final String title;
  final String detail;
  final bool isWarning;
  const _PackagingStep({
    required this.icon,
    required this.title,
    required this.detail,
    this.isWarning = false,
  });
}

Map<String, List<_PackagingStep>> _guideForCategory(String category) {
  final cat = category.toLowerCase();
  if (cat.contains('pottery') || cat.contains('ceramic') || cat.contains('clay')) {
    return {
      'pottery': [
        const _PackagingStep(
          icon: Icons.layers_outlined,
          title: 'Wrap in tissue paper',
          detail: 'Use 2–3 layers of acid-free tissue to protect the glaze.',
        ),
        const _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'Bubble wrap (5cm)',
          detail: 'Apply at least two layers of small-cell bubble wrap secured with tape.',
        ),
        const _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'Double-box method',
          detail: 'Place in a snug inner box, then a larger outer box with 5cm foam padding on all sides.',
        ),
        const _PackagingStep(
          icon: Icons.warning_amber_rounded,
          title: 'Mark "fragile"',
          detail: 'Add fragile stickers on all six faces of the outer box.',
          isWarning: true,
        ),
      ],
    };
  } else if (cat.contains('textile') || cat.contains('fabric') || cat.contains('saree') || cat.contains('silk') || cat.contains('cloth')) {
    return {
      'textile': [
        const _PackagingStep(
          icon: Icons.layers_outlined,
          title: 'Fold along natural creases',
          detail: 'Fold garments carefully along natural drape lines to avoid permanent creases.',
        ),
        const _PackagingStep(
          icon: Icons.water_drop_outlined,
          title: 'Moisture-proof bag',
          detail: 'Seal in a zip-lock polythene bag to protect against humidity.',
        ),
        const _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'Rigid cardboard box',
          detail: 'Place in a sturdy box — avoid vacuum-sealing or over-compressing.',
        ),
        const _PackagingStep(
          icon: Icons.sticky_note_2_outlined,
          title: 'Include craft care card',
          detail: 'Add handwritten or printed artisan story and washing instructions.',
        ),
      ],
    };
  } else if (cat.contains('jewel') || cat.contains('silver') || cat.contains('gold') || cat.contains('brass')) {
    return {
      'jewelry': [
        const _PackagingStep(
          icon: Icons.diamond_outlined,
          title: 'Anti-tarnish pouch',
          detail: 'Place each piece individually in an anti-tarnish zip pouch.',
        ),
        const _PackagingStep(
          icon: Icons.padding_outlined,
          title: 'Padded insert box',
          detail: 'Nest pouches in a velvet or foam-lined jewelry gift box.',
        ),
        const _PackagingStep(
          icon: Icons.lock_outline,
          title: 'Secure tamper seal',
          detail: 'Tape the box lid securely and wrap in protective bubble wrap.',
        ),
        const _PackagingStep(
          icon: Icons.shield_outlined,
          title: 'Discreet outer package',
          detail: 'Use plain, unmarked outer courier packaging for transit security.',
          isWarning: true,
        ),
      ],
    };
  } else if (cat.contains('wood') || cat.contains('toy') || cat.contains('cane') || cat.contains('bamboo')) {
    return {
      'woodwork': [
        const _PackagingStep(
          icon: Icons.dry_cleaning_outlined,
          title: 'Ensure fully seasoned',
          detail: 'Ensure the wood is dry and oiled before packaging to prevent warps.',
        ),
        const _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'Bubble wrap carved edges',
          detail: 'Give extra cushioning around delicate corners, joints, and carvings.',
        ),
        const _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'Foam-lined outer carton',
          detail: 'Use a rigid box with 3cm edge padding on all sides.',
        ),
        const _PackagingStep(
          icon: Icons.wb_sunny_outlined,
          title: 'Keep away from moisture & heat',
          detail: 'Mark "Keep Dry & Away from Direct Heat" on the outer package.',
          isWarning: true,
        ),
      ],
    };
  } else {
    return {
      'general': [
        const _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'Wrap in bubble wrap',
          detail: 'Use at least 2 layers of bubble wrap secured with packing tape.',
        ),
        const _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'Snug-fitting outer box',
          detail: 'Choose a box slightly larger than the craft, filling gaps with paper or foam.',
        ),
        const _PackagingStep(
          icon: Icons.label_outline,
          title: 'Label clearly',
          detail: 'Affix the shipping label clearly on the largest flat surface.',
        ),
        const _PackagingStep(
          icon: Icons.local_shipping_outlined,
          title: 'Reinforce edges with tape',
          detail: 'Use heavy-duty tape along all outer box seams and corners.',
        ),
      ],
    };
  }
}

/// Shows the packaging guide sheet with the scalloped Mehrab top edge motif.
void showPackagingSuggestionsSheet(
  BuildContext context, {
  required String category,
  VoidCallback? onMarkPacked,
}) {
  showMehrabBottomSheet(
    context: context,
    builder: (ctx) => PackagingSuggestionsSheet(
      category: category,
      onMarkPacked: onMarkPacked,
    ),
  );
}

class PackagingSuggestionsSheet extends StatelessWidget {
  final String category;
  final VoidCallback? onMarkPacked;

  const PackagingSuggestionsSheet({
    super.key,
    required this.category,
    this.onMarkPacked,
  });

  @override
  Widget build(BuildContext context) {
    final steps = _guideForCategory(category).values.first;

    return Padding(
      padding: const EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 6.0,
        bottom: 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with icon, title/sub and round close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.terracottaLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.terracottaDark,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'packaging_suggestions_title'.tr(),
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.inkSoft,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: AppColors.parchmentDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Packaging steps list
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isWarning = step.isWarning;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step icon pill
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isWarning
                          ? AppColors.goldLight
                          : AppColors.terracottaLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isWarning
                          ? Icon(
                              step.icon,
                              size: 13,
                              color: AppColors.goldDark,
                            )
                          : Icon(
                              step.icon,
                              size: 13,
                              color: AppColors.terracottaDark,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: AppTextStyles.labelMedium.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.detail,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),

          // Primary action button
          AppButton(
            label: onMarkPacked != null
                ? 'Update status: packed'
                : 'Got it, ready to pack',
            onPressed: () {
              Navigator.of(context).pop();
              onMarkPacked?.call();
            },
          ),
        ],
      ),
    );
  }
}
