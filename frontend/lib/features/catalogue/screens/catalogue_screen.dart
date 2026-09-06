import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';
import '../../social_media/providers/social_media_provider.dart';
import '../../home/screens/home_shell.dart';
import '../providers/catalogue_filter_provider.dart';

class CatalogueScreen extends ConsumerStatefulWidget {
  const CatalogueScreen({super.key});

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
  String _selectedCategory = 'filter_all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<String> categories = [
    'filter_all',
    'filter_pottery',
    'filter_textiles',
    'filter_jewelry',
    'filter_woodwork',
    'filter_paintings',
  ];

  @override
  void initState() {
    super.initState();
    final filter = ref.read(catalogueFilterProvider);
    _searchQuery = filter.searchQuery;
    _selectedCategory = filter.selectedCategory;
    if (filter.searchQuery.isNotEmpty) {
      _searchController.text = filter.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filterProducts(List<Product> products) {
    return products.where((p) {
      if (_selectedCategory != 'filter_all') {
        final catName = _selectedCategory.replaceAll('filter_', '').toLowerCase();
        if (!p.category.toLowerCase().contains(catName)) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = p.title.toLowerCase().contains(q) || p.titleHi.toLowerCase().contains(q);
        final matchCat = p.category.toLowerCase().contains(q);
        final matchTag = p.tags.any((t) => t.toLowerCase().contains(q));
        return matchTitle || matchCat || matchTag;
      }
      return true;
    }).toList();
  }

  Widget _buildStatusBadge(ProductStatus status) {
    Color bg;
    Color fg;
    String labelKey;
    IconData icon;

    switch (status) {
      case ProductStatus.live:
        bg = AppColors.forestGreenLight.withValues(alpha: 0.2);
        fg = AppColors.forestGreenDark;
        labelKey = 'status_live';
        icon = Icons.check_circle;
        break;
      case ProductStatus.pendingSync:
        bg = AppColors.turmericLight.withValues(alpha: 0.3);
        fg = AppColors.turmericDark;
        labelKey = 'status_pending_sync';
        icon = Icons.cloud_queue;
        break;
      case ProductStatus.draft:
        bg = AppColors.surfaceVariant;
        fg = AppColors.textSecondary;
        labelKey = 'status_draft';
        icon = Icons.edit_note;
        break;
      case ProductStatus.sold:
        bg = AppColors.mustard.withValues(alpha: 0.25);
        fg = AppColors.terracottaDark;
        labelKey = 'status_sold';
        icon = Icons.sell;
        break;
      case ProductStatus.soldOut:
        bg = AppColors.error.withValues(alpha: 0.15);
        fg = AppColors.error;
        labelKey = 'status_sold_out';
        icon = Icons.remove_shopping_cart_outlined;
        break;
      case ProductStatus.listingRemoved:
        bg = AppColors.mustard.withValues(alpha: 0.25);
        fg = AppColors.terracottaDark;
        labelKey = 'status_listing_removed';
        icon = Icons.visibility_off_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            labelKey.tr(),
            style: AppTextStyles.labelSmall.copyWith(color: fg, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);

    ref.listen<CatalogueFilterState>(catalogueFilterProvider, (prev, next) {
      if (next.searchQuery != _searchController.text) {
        _searchController.text = next.searchQuery;
      }
      if (next.searchQuery != _searchQuery || next.selectedCategory != _selectedCategory) {
        setState(() {
          _searchQuery = next.searchQuery;
          _selectedCategory = next.selectedCategory;
        });
      }
    });

    return AppScaffold(
      title: 'my_catalogue_title'.tr(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'search_products_hint'.tr(),
                prefixIcon: const Icon(Icons.search, color: AppColors.terracotta),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          ref.read(catalogueFilterProvider.notifier).setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim());
                ref.read(catalogueFilterProvider.notifier).setSearchQuery(val.trim());
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final catKey = categories[index];
                final isSelected = _selectedCategory == catKey;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: FilterChip(
                    label: Text(catKey.tr()),
                    selected: isSelected,
                    selectedColor: AppColors.terracottaLight,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = catKey);
                      ref.read(catalogueFilterProvider.notifier).setSelectedCategory(catKey);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: AppSpacing.md),
                      Text('Error loading catalogue', style: AppTextStyles.headlineMedium),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'retry'.tr(),
                        width: 140,
                        onPressed: () {
                          ref.read(productListProvider.notifier).loadProducts(forceRefresh: true);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              data: (products) {
                final filtered = _filterProducts(products);
                final hasActiveFilter = _searchQuery.isNotEmpty || _selectedCategory != 'filter_all';

                if (products.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              size: 56,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text('no_products_title'.tr(), style: AppTextStyles.headlineMedium),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'no_products_desc'.tr(),
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton(
                            label: 'add_first_product'.tr(),
                            icon: Icons.add,
                            width: 220,
                            onPressed: () {
                              ref.read(homeTabIndexProvider.notifier).state = 0;
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.search_off,
                              size: 56,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Text(
                            'No products match your search',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF3F342B)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Try a different keyword or category filter.',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          if (hasActiveFilter) ...[
                            const SizedBox(height: AppSpacing.xl),
                            AppButton(
                              label: 'Clear search & filters',
                              icon: Icons.clear,
                              width: 220,
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _selectedCategory = 'filter_all';
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppColors.terracotta,
                  onRefresh: () => ref
                      .read(productListProvider.notifier)
                      .loadProducts(forceRefresh: true),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _GridProductCard(
                        product: item,
                        statusBadge: _buildStatusBadge(item.status),
                        onTap: () {
                          context.pushNamed(
                            AppRouteConstants.productDetail,
                            pathParameters: {'id': item.id},
                          );
                        },
                        onSocialTap: item.allPhotoPaths.isEmpty
                            ? null
                            : () => context.pushNamed(
                                  AppRouteConstants.socialMediaHelper,
                                  extra: SocialMediaArgs(
                                    listingId: item.id,
                                    source: 'catalogue',
                                    allImages: item.allPhotoPaths,
                                    title: item.title,
                                    category: item.category,
                                    description: item.description,
                                    materials: item.tags,
                                  ),
                                ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GridProductCard extends StatelessWidget {
  final Product product;
  final Widget statusBadge;
  final VoidCallback onTap;
  final VoidCallback? onSocialTap;

  const _GridProductCard({required this.product, required this.statusBadge, required this.onTap, this.onSocialTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColorFiltered(
                        colorFilter: product.isNonLive
                            ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                        child: Opacity(
                          opacity: product.isNonLive ? 0.72 : 1.0,
                          child: AppImage(imageUrl: product.displayPhotoPath, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    Positioned(top: 8, left: 8, child: statusBadge),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: AppTextStyles.labelMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${product.price.toStringAsFixed(0)}',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.terracotta,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (onSocialTap != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onSocialTap,
                        icon: const Icon(Icons.share, size: 16),
                        label: Text('social_media_helper'.tr()),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
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

