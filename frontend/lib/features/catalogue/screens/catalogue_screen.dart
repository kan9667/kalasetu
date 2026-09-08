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
import '../../../core/widgets/motifs/craft_category_badge.dart';
import '../../../core/widgets/motifs/empty_craft_state.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';
import '../../social_media/providers/social_media_provider.dart';
import '../../social_media/widgets/social_media_launchpad_sheet.dart';
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

  void _onCategorySelected(String catKey) {
    setState(() => _selectedCategory = catKey);
    ref.read(catalogueFilterProvider.notifier).setSelectedCategory(catKey);
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

  Widget _buildStatusBadge(ProductStatus status, BuildContext context) {
    if (status == ProductStatus.live) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xEBFFFDF9), // rgba(255,253,249,0.92)
          borderRadius: BorderRadius.circular(AppRadii.chip),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14201A18),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'status_live'.tr(),
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.success,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Color bg;
    Color fg;
    String labelKey;
    IconData icon;

    switch (status) {
      case ProductStatus.pendingSync:
        bg = AppColors.statusPendingBg;
        fg = AppColors.statusPendingFg;
        labelKey = 'status_pending_sync';
        icon = Icons.cloud_queue;
        break;
      case ProductStatus.draft:
        bg = AppColors.parchmentDeep;
        fg = AppColors.inkSoft;
        labelKey = 'status_draft';
        icon = Icons.edit_note;
        break;
      case ProductStatus.sold:
        bg = AppColors.goldLight;
        fg = AppColors.goldDark;
        labelKey = 'status_sold';
        icon = Icons.sell;
        break;
      case ProductStatus.soldOut:
        bg = AppColors.terracottaLight;
        fg = AppColors.terracottaDark;
        labelKey = 'status_sold_out';
        icon = Icons.remove_shopping_cart_outlined;
        break;
      case ProductStatus.listingRemoved:
        bg = AppColors.parchmentDeep;
        fg = AppColors.inkFaint;
        labelKey = 'status_listing_removed';
        icon = Icons.visibility_off_outlined;
        break;
      case ProductStatus.live:
        bg = AppColors.statusSuccessBg;
        fg = AppColors.statusSuccessFg;
        labelKey = 'status_live';
        icon = Icons.check_circle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            labelKey.tr(),
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(String catKey, BuildContext context) {
    final isSelected = _selectedCategory == catKey;
    final label = catKey.tr();

    if (catKey == 'filter_all') {
      return CraftCategoryBadge.all(
        label: label,
        isActive: isSelected,
        onTap: () => _onCategorySelected(catKey),
      );
    }
    if (catKey == 'filter_pottery') {
      return CraftCategoryBadge(
        label: label,
        icon: CraftCategoryIcons.pottery(),
        isActive: isSelected,
        showPetalRing: false,
        onTap: () => _onCategorySelected(catKey),
      );
    }
    if (catKey == 'filter_textiles') {
      return CraftCategoryBadge(
        label: label,
        icon: CraftCategoryIcons.textile(),
        isActive: isSelected,
        showPetalRing: false,
        onTap: () => _onCategorySelected(catKey),
      );
    }
    if (catKey == 'filter_jewelry') {
      return CraftCategoryBadge(
        label: label,
        icon: CraftCategoryIcons.jewelry(),
        isActive: isSelected,
        showPetalRing: false,
        onTap: () => _onCategorySelected(catKey),
      );
    }
    if (catKey == 'filter_woodwork') {
      return CraftCategoryBadge(
        label: label,
        icon: CraftCategoryIcons.woodwork(),
        isActive: isSelected,
        showPetalRing: false,
        onTap: () => _onCategorySelected(catKey),
      );
    }
    // Fallback for paintings or other
    return CraftCategoryBadge(
      label: label,
      icon: CraftCategoryIcons.pottery(),
      isActive: isSelected,
      showPetalRing: false,
      onTap: () => _onCategorySelected(catKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = Localizations.maybeLocaleOf(context);
    final _ = ref.watch(userProfileProvider).preferredLanguage;
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
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              ref.read(homeTabIndexProvider.notifier).state = 0;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.terracotta,
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'add_product_btn'.tr(),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      body: Column(
        children: [
          // Search Bar matching kalasetu-redesign-v3.html
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchController,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
              decoration: InputDecoration(
                hintText: 'search_products_hint'.tr(),
                hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.inkFaint),
                prefixIcon: const Icon(Icons.search, color: AppColors.inkFaint, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppColors.inkSoft),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          ref.read(catalogueFilterProvider.notifier).setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                  borderSide: const BorderSide(color: AppColors.line, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                  borderSide: const BorderSide(color: AppColors.line, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                  borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
                ),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.trim());
                ref.read(catalogueFilterProvider.notifier).setSearchQuery(val.trim());
              },
            ),
          ),

          const SizedBox(height: 10),

          // Craft Category Badges with Petal Ring
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _buildCategoryBadge(categories[index], context),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Product Grid or Empty State
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.terracotta),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.terracottaDark),
                      const SizedBox(height: AppSpacing.md),
                      Text('error_loading_catalogue'.tr(), style: AppTextStyles.headlineMedium),
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
                if (filtered.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EmptyCraftState(
                            title: 'no_products_title'.tr(),
                            subtitle: 'no_products_desc'.tr(),
                          ),
                          const SizedBox(height: 16),
                          AppButton(
                            label: 'add_product_btn'.tr(),
                            icon: Icons.add_photo_alternate_rounded,
                            type: AppButtonType.primary,
                            width: 240,
                            onPressed: () {
                              ref.read(homeTabIndexProvider.notifier).state = 0;
                            },
                          ),
                          const SizedBox(height: 10),
                          AppButton(
                            label: 'how_to_list_btn'.tr(),
                            icon: Icons.play_circle_outline_rounded,
                            type: AppButtonType.outlined,
                            width: 240,
                            onPressed: () {
                              context.pushNamed(AppRouteConstants.listingTutorial);
                            },
                          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                      vertical: AppSpacing.xs,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.60,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _GridProductCard(
                        product: item,
                        statusBadge: _buildStatusBadge(item.status, context),
                        onTap: () {
                          context.pushNamed(
                            AppRouteConstants.productDetail,
                            pathParameters: {'id': item.id},
                          );
                        },
                        onSocialTap: item.allPhotoPaths.isEmpty
                            ? null
                            : () => showSocialMediaLaunchpadSheet(
                                  context,
                                  SocialMediaArgs(
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

  const _GridProductCard({
    required this.product,
    required this.statusBadge,
    required this.onTap,
    this.onSocialTap,
  });

  @override
  Widget build(BuildContext context) {
    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final displayTitle = (isHindi && product.titleHi.trim().isNotEmpty)
        ? product.titleHi
        : product.title;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.line, width: 1.0),
        boxShadow: AppElevation.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image thumbnail with live/status tag
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColorFiltered(
                        colorFilter: product.isNonLive
                            ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                            : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                        child: Opacity(
                          opacity: product.isNonLive ? 0.72 : 1.0,
                          child: product.displayPhotoPath.isNotEmpty
                              ? AppImage(
                                  imageUrl: product.displayPhotoPath,
                                  fit: BoxFit.cover,
                                )
                              : _buildFallbackImage(product.category),
                        ),
                      ),
                    ),
                    Positioned(top: 8, left: 8, child: statusBadge),
                  ],
                ),
              ),

              // Card details body
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayTitle,
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${product.price.toStringAsFixed(0)}',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.terracottaDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    if (onSocialTap != null) ...[
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: onSocialTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.share_outlined,
                                size: 13,
                                color: AppColors.terracotta,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'social_media_helper'.tr(),
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.terracotta,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(String category) {
    final cat = category.toLowerCase();
    CustomPainter painter;
    if (cat.contains('pot') || cat.contains('clay') || cat.contains('ceramic')) {
      painter = CraftCategoryIcons.pottery(color: AppColors.terracottaDark);
    } else if (cat.contains('silk') || cat.contains('textile') || cat.contains('saree')) {
      painter = CraftCategoryIcons.textile(color: AppColors.terracottaDark);
    } else if (cat.contains('wood') || cat.contains('toy')) {
      painter = CraftCategoryIcons.woodwork(color: AppColors.terracottaDark);
    } else if (cat.contains('jewel') || cat.contains('gold') || cat.contains('silver')) {
      painter = CraftCategoryIcons.jewelry(color: AppColors.terracottaDark);
    } else {
      painter = CraftCategoryIcons.pottery(color: AppColors.terracottaDark);
    }

    return Container(
      color: AppColors.parchmentDeep,
      child: Center(
        child: CustomPaint(
          size: const Size(40, 40),
          painter: painter,
        ),
      ),
    );
  }
}