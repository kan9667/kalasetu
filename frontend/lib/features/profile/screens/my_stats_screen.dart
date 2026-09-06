import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';

class MyStatsScreen extends ConsumerStatefulWidget {
  const MyStatsScreen({super.key});

  @override
  ConsumerState<MyStatsScreen> createState() => _MyStatsScreenState();
}

class _MyStatsScreenState extends ConsumerState<MyStatsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;
  int _selectedSegment = 0; // 0: This month, 1: Last 3 months, 2: All time

  final List<String> _segments = const ['This month', 'Last 3 months', 'All time'];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onSegmentSelected(int index) {
    if (_selectedSegment == index) return;
    setState(() {
      _selectedSegment = index;
    });
    _animController.reset();
    _animController.forward();
  }

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
    final productsAsync = ref.watch(productListProvider);
    final pendingCount = ref.read(productRepositoryProvider).getPendingCount();

    final products = productsAsync.value ?? const <Product>[];
    final totalListings = products.length;
    final liveRevenue = products
        .where((p) => p.status == ProductStatus.sold)
        .fold<double>(0, (sum, p) => sum + p.price);
    final topCategory = _topCategory(products);

    // Dynamic stats based on selected time period
    final double targetRevenue;
    final String ordersText;
    final String avgOrderText;
    final int middlemanWage;
    final int kalasetuWage;
    final int diffWage;
    final List<({String month, String val, double h, bool isHighlight})> chartBars;

    if (_selectedSegment == 0) {
      targetRevenue = liveRevenue > 0 ? liveRevenue : 12840;
      ordersText = '6 orders';
      avgOrderText = '₹2,140';
      middlemanWage = 4879;
      kalasetuWage = 12840;
      diffWage = 7961;
      chartBars = const [
        (month: 'Apr', val: '₹6.1k', h: 38.0, isHighlight: false),
        (month: 'May', val: '₹6.8k', h: 45.0, isHighlight: false),
        (month: 'Jun', val: '₹7.5k', h: 52.0, isHighlight: false),
        (month: 'Jul', val: '₹7.9k', h: 56.0, isHighlight: false),
        (month: 'Aug', val: '₹9.2k', h: 68.0, isHighlight: false),
        (month: 'Sep', val: '₹11.7k', h: 90.0, isHighlight: true),
      ];
    } else if (_selectedSegment == 1) {
      targetRevenue = 32450;
      ordersText = '17 orders';
      avgOrderText = '₹1,908';
      middlemanWage = 12330;
      kalasetuWage = 32450;
      diffWage = 20120;
      chartBars = const [
        (month: 'Apr', val: '₹6.1k', h: 32.0, isHighlight: false),
        (month: 'May', val: '₹6.8k', h: 40.0, isHighlight: false),
        (month: 'Jun', val: '₹7.5k', h: 48.0, isHighlight: false),
        (month: 'Jul', val: '₹9.5k', h: 62.0, isHighlight: false),
        (month: 'Aug', val: '₹11.2k', h: 76.0, isHighlight: false),
        (month: 'Sep', val: '₹14.8k', h: 90.0, isHighlight: true),
      ];
    } else {
      targetRevenue = 78200;
      ordersText = '41 orders';
      avgOrderText = '₹1,907';
      middlemanWage = 29716;
      kalasetuWage = 78200;
      diffWage = 48484;
      chartBars = const [
        (month: 'Apr', val: '₹6.1k', h: 25.0, isHighlight: false),
        (month: 'May', val: '₹10.5k', h: 42.0, isHighlight: false),
        (month: 'Jun', val: '₹14.2k', h: 54.0, isHighlight: false),
        (month: 'Jul', val: '₹18.6k', h: 68.0, isHighlight: false),
        (month: 'Aug', val: '₹22.1k', h: 80.0, isHighlight: false),
        (month: 'Sep', val: '₹28.4k', h: 90.0, isHighlight: true),
      ];
    }

    return AppScaffold(
      title: 'Performance',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Segmented Capsule Track
            Container(
              decoration: BoxDecoration(
                color: AppColors.parchmentDeep,
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: List.generate(_segments.length, (index) {
                  final isActive = _selectedSegment == index;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onSegmentSelected(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.cardSurface : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: isActive
                              ? const [
                                  BoxShadow(
                                    color: Color(0x1A201A18),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          _segments[index],
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isActive ? AppColors.ink : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Hero Metric Card (Berry background with count-up animation)
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                final currentRev = (targetRevenue * _animation.value).round();
                final formattedRev = NumberFormat('#,##,###').format(currentRev);

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.berry,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ink.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.trending_up_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Total sales revenue',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ordersText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹$formattedRev',
                        style: AppTextStyles.displayMedium.copyWith(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimated additional earnings',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.25),
                        margin: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Avg. order value',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.90),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            avgOrderText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.md),

            // Fair Wage vs Middleman Rate Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
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
                      const Icon(
                        Icons.shield_outlined,
                        color: AppColors.goldDark,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fair wage vs middleman rate',
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You earned ₹${NumberFormat('#,##,###').format(diffWage)} more than typical middleman rates — 163% extra kept for your household.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.inkSoft,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Column(
                        children: [
                          // Middleman row
                          Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  'Middleman',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.parchmentDeep,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: (0.38 * _animation.value).clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.inkFaint,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '₹${NumberFormat('#,##,###').format(middlemanWage)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Kalasetu row
                          Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  'Kalasetu',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.parchmentDeep,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: (1.0 * _animation.value).clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.blueAccent,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '₹${NumberFormat('#,##,###').format(kalasetuWage)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Dotted Rule motif divider
            const DottedBorderBox.divider(
              borderColor: AppColors.dottedBorder,
              borderWidth: 1.5,
              dashLength: 5.0,
              dashGap: 4.0,
            ),

            const SizedBox(height: AppSpacing.md),

            // Bar Chart Card (Recent revenue trajectory)
            Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
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
                      const Icon(
                        Icons.trending_up_rounded,
                        color: AppColors.terracotta,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent revenue trajectory',
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return SizedBox(
                        height: 140,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: chartBars.map((bar) {
                            final currentH = (bar.h * _animation.value).clamp(0.0, 90.0);
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Opacity(
                                  opacity: _animation.value,
                                  child: Text(
                                    bar.val,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: bar.isHighlight
                                          ? AppColors.goldDark
                                          : AppColors.terracottaDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  width: 26,
                                  height: currentH,
                                  decoration: BoxDecoration(
                                    color: bar.isHighlight ? AppColors.gold : AppColors.terracottaLight,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                      bottomLeft: Radius.circular(3),
                                      bottomRight: Radius.circular(3),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  bar.month,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkFaint,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Additional Artisan listings / cluster info
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppElevation.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 24, color: AppColors.terracotta),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$totalListings',
                          style: AppTextStyles.headlineLarge.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'total_listings'.tr(),
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppElevation.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.sync_rounded, size: 24, color: AppColors.goldDark),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$pendingCount',
                          style: AppTextStyles.headlineLarge.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'pending_sync_count'.tr(),
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (topCategory != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppElevation.cardShadow,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insights_rounded, color: AppColors.terracotta, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Top craft category: $topCategory',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Fair Labor & Floor Price Guarantee Card
            Container(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.line),
                boxShadow: AppElevation.cardShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.statusSuccessBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, color: AppColors.statusSuccessFg, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'floor_price_guarantee'.tr(),
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.statusSuccessFg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'All listings respect your material cost + fair labor floor price.',
                          style: AppTextStyles.caption.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}