import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';

enum AnalyticsPeriod { thisMonth, last3Months, allTime }
enum PopularSort { byViews, bySales }

class MyStatsScreen extends ConsumerStatefulWidget {
  const MyStatsScreen({super.key});

  @override
  ConsumerState<MyStatsScreen> createState() => _MyStatsScreenState();
}

class _MyStatsScreenState extends ConsumerState<MyStatsScreen> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.thisMonth;
  PopularSort _popularSort = PopularSort.bySales;

  String? _topCategory(List<Product> products) {
    if (products.isEmpty) return null;
    final counts = <String, int>{};
    for (final p in products) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final productsAsync = ref.watch(productListProvider);
    final allOrders = ref.watch(ordersProvider);
    final pendingCount = ref.read(productRepositoryProvider).getPendingCount();

    final products = productsAsync.value ?? const <Product>[];
    final totalListings = products.length;
    final topCategory = _topCategory(products) ?? (profile.craftType.isNotEmpty ? profile.craftType : 'Terracotta Pottery');

    // Filter orders by selected period
    final now = DateTime.now();
    final List<Order> filteredOrders;
    switch (_selectedPeriod) {
      case AnalyticsPeriod.thisMonth:
        filteredOrders = allOrders.where((o) => o.placedAt.isAfter(now.subtract(const Duration(days: 30)))).toList();
        break;
      case AnalyticsPeriod.last3Months:
        filteredOrders = allOrders.where((o) => o.placedAt.isAfter(now.subtract(const Duration(days: 90)))).toList();
        break;
      case AnalyticsPeriod.allTime:
        filteredOrders = allOrders;
        break;
    }

    // Revenue calculations
    final activeOrders = filteredOrders.where((o) => o.status != OrderStatus.cancelled).toList();
    final double calculatedSales = activeOrders.fold<double>(
      0.0,
      (sum, o) => sum + (o.amount * o.quantity),
    );
    // Baseline if orders list is small in mock
    final totalSalesRevenue = calculatedSales > 0 ? calculatedSales : 11730.0;

    // Average Order Value (AOV)
    final aov = activeOrders.isNotEmpty ? (totalSalesRevenue / activeOrders.length) : totalSalesRevenue;

    // Order Fulfillment metrics
    final deliveredCount = filteredOrders.where((o) => o.status == OrderStatus.delivered).length;
    final inProgressCount = filteredOrders.where((o) =>
        o.status == OrderStatus.newOrder ||
        o.status == OrderStatus.packed ||
        o.status == OrderStatus.shipped).length;
    final cancelledCount = filteredOrders.where((o) => o.status == OrderStatus.cancelled).length;
    final totalOrdersCount = deliveredCount + inProgressCount + cancelledCount;
    final fulfillmentRate = totalOrdersCount > 0
        ? (((deliveredCount + inProgressCount) / totalOrdersCount) * 100).toStringAsFixed(0)
        : '92';

    // Repeat buyers
    final buyerMap = <String, int>{};
    for (final o in filteredOrders) {
      buyerMap[o.buyerName] = (buyerMap[o.buyerName] ?? 0) + 1;
    }
    final repeatBuyers = buyerMap.values.where((c) => c > 1).length;

    // Fair Wage Premium calculation (vs ~38% typical middleman payout)
    final middlemanPayout = totalSalesRevenue * 0.38;
    final fairWagePremium = totalSalesRevenue - middlemanPayout;
    final premiumPercentage = ((fairWagePremium / middlemanPayout) * 100).toStringAsFixed(0);

    // Popular crafts data mapping
    final popularCrafts = _generateCraftMetrics(products, allOrders);
    popularCrafts.sort((a, b) {
      if (_popularSort == PopularSort.byViews) {
        return b.views.compareTo(a.views);
      } else {
        return b.unitsSold.compareTo(a.unitsSold);
      }
    });

    return AppScaffold(
      title: 'my_stats_title'.tr(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period selector tabs
            _buildPeriodSelector(),

            const SizedBox(height: AppSpacing.md),

            // Hero Stat Card: Total Sales Revenue & AOV
            _buildHeroRevenueCard(
              totalRevenue: totalSalesRevenue,
              ordersCount: activeOrders.length,
              aov: aov,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Fair Wage Premium vs Middleman Rate comparison card
            _buildFairWageComparisonCard(
              totalEarned: totalSalesRevenue,
              middlemanRate: middlemanPayout,
              premiumAmount: fairWagePremium,
              premiumPercent: premiumPercentage,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Sales Trend trajectory sparkline
            _buildSalesTrendSection(),

            const SizedBox(height: AppSpacing.lg),

            // Order Reliability & Fulfillment Breakdown
            _buildFulfillmentBreakdownCard(
              rate: fulfillmentRate,
              delivered: deliveredCount,
              inProgress: inProgressCount,
              cancelled: cancelledCount,
              repeatBuyers: repeatBuyers,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Most Popular Crafts & Views
            _buildPopularCraftsSection(popularCrafts),

            const SizedBox(height: AppSpacing.lg),

            // Retained listings & cluster context cards
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
                    value: profile.craftType.isNotEmpty ? profile.craftType : 'Pottery',
                    icon: Icons.palette,
                    iconColor: AppColors.charcoal,
                    isSmallValue: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    title: 'location_cluster'.tr(),
                    value: profile.locationCluster.isNotEmpty ? profile.locationCluster : 'Cluster Hub',
                    icon: Icons.location_on,
                    iconColor: AppColors.forestGreen,
                    isSmallValue: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // Top category insight (dynamic and localized)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: AppColors.terracotta, size: 28),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'stats_top_category_insight'.tr(namedArgs: {'category': topCategory}),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Floor Price Guarantee card
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.forestGreen.withValues(alpha: 0.4)),
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
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.forestGreenDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'All listings respect your material cost + fair labor floor price.',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        children: [
          _buildPeriodTab(AnalyticsPeriod.thisMonth, 'period_this_month'.tr()),
          _buildPeriodTab(AnalyticsPeriod.last3Months, 'period_last_3_months'.tr()),
          _buildPeriodTab(AnalyticsPeriod.allTime, 'period_all_time'.tr()),
        ],
      ),
    );
  }

  Widget _buildPeriodTab(AnalyticsPeriod period, String label) {
    final isSelected = _selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPeriod = period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.cream : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.chip),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: isSelected ? AppColors.charcoal : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroRevenueCard({
    required double totalRevenue,
    required int ordersCount,
    required double aov,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.terracotta, AppColors.terracottaDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28C97B5A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.monetization_on, color: AppColors.mustard, size: 22),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'total_sales_revenue'.tr(),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(
                  '$ordersCount orders',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '₹${totalRevenue.toStringAsFixed(0)}',
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.textOnPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 34,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'estimated_earnings'.tr(),
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.cream.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'average_order_value'.tr(),
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.cream),
                ),
                Text(
                  '₹${aov.toStringAsFixed(0)}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.mustard,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFairWageComparisonCard({
    required double totalEarned,
    required double middlemanRate,
    required double premiumAmount,
    required String premiumPercent,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2A2420),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.mustard.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handshake_outlined, color: AppColors.charcoal, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'fair_wage_premium_title'.tr(),
                  style: AppTextStyles.headlineSmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'fair_wage_premium_desc'.tr(namedArgs: {
              'premiumAmount': '₹${premiumAmount.toStringAsFixed(0)}',
              'premiumPercent': premiumPercent,
            }),
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'middleman_rate_label'.tr(),
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${middlemanRate.toStringAsFixed(0)}',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.charcoalSoft,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: AppColors.border),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'kalasetu_earned_label'.tr(),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.online,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${totalEarned.toStringAsFixed(0)}',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.online,
                          fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildSalesTrendSection() {
    final bars = [
      ('Apr', 4200.0),
      ('May', 6500.0),
      ('Jun', 8100.0),
      ('Jul', 7400.0),
      ('Aug', 9800.0),
      ('Sep', 11730.0),
    ];
    final maxAmount = 12000.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.oak.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppColors.terracotta, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'sales_trend_title'.tr(),
                style: AppTextStyles.labelMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: bars.map((bar) {
                final ratio = (bar.$2 / maxAmount).clamp(0.15, 1.0);
                final isPeak = bar == bars.last;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isPeak)
                      Text(
                        '₹11.7k',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.terracottaDark,
                        ),
                      ),
                    const SizedBox(height: 2),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 28,
                      height: 80 * ratio,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPeak
                              ? [AppColors.terracotta, AppColors.terracottaDark]
                              : [AppColors.terracottaLight, AppColors.terracotta],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.$1,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: isPeak ? FontWeight.bold : FontWeight.w500,
                        color: isPeak ? AppColors.charcoal : AppColors.textSecondary,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFulfillmentBreakdownCard({
    required String rate,
    required int delivered,
    required int inProgress,
    required int cancelled,
    required int repeatBuyers,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.oak.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'order_fulfillment_title'.tr(),
                style: AppTextStyles.labelMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.online.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(
                  '$rate% Reliability',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.online,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildFulfillmentPill('delivered_label'.tr(), '$delivered', AppColors.online),
              const SizedBox(width: AppSpacing.xs),
              _buildFulfillmentPill('in_progress_label'.tr(), '$inProgress', AppColors.syncing),
              const SizedBox(width: AppSpacing.xs),
              _buildFulfillmentPill('cancelled_label'.tr(), '$cancelled', AppColors.brick),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: AppColors.border.withValues(alpha: 0.3)),
          Row(
            children: [
              const Icon(Icons.repeat, size: 16, color: AppColors.terracotta),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'repeat_buyers'.tr(),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '$repeatBuyers repeat customers',
                style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFulfillmentPill(String label, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: AppTextStyles.labelLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularCraftsSection(List<_CraftMetric> crafts) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'popular_crafts_title'.tr(),
                  style: AppTextStyles.labelMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
              // Sort toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Row(
                  children: [
                    _buildSortOption(PopularSort.bySales, 'sort_by_sales'.tr()),
                    _buildSortOption(PopularSort.byViews, 'sort_by_views'.tr()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: crafts.length,
            separatorBuilder: (_, _) => Divider(
              color: AppColors.border.withValues(alpha: 0.3),
              height: 16,
            ),
            itemBuilder: (context, index) {
              final craft = crafts[index];
              return Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index < 3 ? AppColors.terracotta : AppColors.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: index < 3 ? Colors.white : AppColors.charcoal,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.brush, color: AppColors.terracotta, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          craft.title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          craft.category,
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${craft.views} views',
                        style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${craft.unitsSold} sold',
                            style: AppTextStyles.caption.copyWith(color: AppColors.online, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${craft.conversionRate}%)',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSortOption(PopularSort sort, String label) {
    final isSelected = _popularSort == sort;
    return GestureDetector(
      onTap: () => setState(() => _popularSort = sort),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.terracotta : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  List<_CraftMetric> _generateCraftMetrics(List<Product> products, List<Order> orders) {
    if (products.isNotEmpty) {
      return products.map((p) {
        final units = orders.where((o) => o.productTitle.toLowerCase().contains(p.title.toLowerCase()) || p.title.toLowerCase().contains(o.productTitle.toLowerCase())).length;
        final views = (p.price * 0.32 + 85).round();
        final conv = views > 0 ? ((units / views) * 100).toStringAsFixed(1) : '0.0';
        return _CraftMetric(
          title: p.title,
          category: p.category,
          views: views,
          unitsSold: units > 0 ? units : 3,
          conversionRate: conv,
        );
      }).toList();
    }

    // Default craft showcase metrics
    return [
      _CraftMetric(
        title: 'Terracotta Water Pot (Matka)',
        category: 'Pottery',
        views: 248,
        unitsSold: 18,
        conversionRate: '7.3',
      ),
      _CraftMetric(
        title: 'Block-Print Kota Saree',
        category: 'Textiles',
        views: 194,
        unitsSold: 12,
        conversionRate: '6.2',
      ),
      _CraftMetric(
        title: 'Dhokra Brass Elephant',
        category: 'Metalwork',
        views: 165,
        unitsSold: 9,
        conversionRate: '5.5',
      ),
      _CraftMetric(
        title: 'Warli Tribal Painting',
        category: 'Paintings',
        views: 132,
        unitsSold: 8,
        conversionRate: '6.1',
      ),
      _CraftMetric(
        title: 'Channapatna Wooden Toy Set',
        category: 'Woodwork',
        views: 110,
        unitsSold: 6,
        conversionRate: '5.4',
      ),
    ];
  }
}

class _CraftMetric {
  final String title;
  final String category;
  final int views;
  final int unitsSold;
  final String conversionRate;

  _CraftMetric({
    required this.title,
    required this.category,
    required this.views,
    required this.unitsSold,
    required this.conversionRate,
  });
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
        border: Border.all(color: AppColors.oak.withValues(alpha: 0.5), width: 0.8),
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