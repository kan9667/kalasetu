import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';

class MyStatsScreen extends ConsumerWidget {
  const MyStatsScreen({super.key});

  String? _topCategory(List<Product> products) {
    if (products.isEmpty) return null;
    final counts = <String, int>{};
    for (final p in products) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final productsAsync = ref.watch(productListProvider);
    final pendingCount = ref.read(productRepositoryProvider).getPendingCount();

    final products = productsAsync.value ?? const <Product>[];
    final totalListings = products.length;
    final soldRevenue = products
        .where((p) => p.status == ProductStatus.sold)
        .fold<double>(0, (sum, p) => sum + p.price);
    final topCategory = _topCategory(products);

    return AppScaffold(
      title: 'my_stats_title'.tr(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.terracotta, AppColors.terracottaDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, color: AppColors.mustard, size: 24),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'KalaSetu Artisan Impact',
                        style: AppTextStyles.labelMedium.copyWith(color: AppColors.textOnPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '₹${soldRevenue.toStringAsFixed(0)}',
                    style: AppTextStyles.displayLarge.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'estimated_earnings'.tr(),
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.surfaceVariant),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'total_listings'.tr(),
                    value: '$totalListings',
                    icon: Icons.inventory_2,
                    iconColor: AppColors.terracotta,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    title: 'pending_sync_count'.tr(),
                    value: '$pendingCount',
                    icon: Icons.sync,
                    iconColor: AppColors.turmericDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'craft_type'.tr(),
                    value: profile.craftType,
                    icon: Icons.palette,
                    iconColor: AppColors.charcoal,
                    isSmallValue: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    title: 'location_cluster'.tr(),
                    value: profile.locationCluster,
                    icon: Icons.location_on,
                    iconColor: AppColors.forestGreen,
                    isSmallValue: true,
                  ),
                ),
              ],
            ),

            if (topCategory != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insights, color: AppColors.terracotta),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'stats_top_category_insight'.tr(namedArgs: {'category': topCategory}),
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: AppColors.forestGreen, size: 36),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'floor_price_guarantee'.tr(),
                          style: AppTextStyles.labelMedium.copyWith(color: AppColors.forestGreenDark),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'All listings respect your material cost + fair labor floor price.',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool isSmallValue;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.isSmallValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.oak, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: iconColor),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: isSmallValue ? AppTextStyles.headlineSmall : AppTextStyles.headlineLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}