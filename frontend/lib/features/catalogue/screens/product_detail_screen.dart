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
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';
import '../../social_media/providers/social_media_provider.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  void _showEditDialog(BuildContext context, WidgetRef ref, Product product) {
    final titleCtrl = TextEditingController(text: product.title);
    final descCtrl = TextEditingController(text: product.description);
    final priceCtrl = TextEditingController(text: product.price.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.dialog)),
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: AppSpacing.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'edit_product_title'.tr(),
                    style: AppTextStyles.headlineMedium.copyWith(fontSize: 19),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(labelText: 'product_title_label'.tr()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₹)', prefixText: '₹ '),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'product_desc_label'.tr()),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Stacked full-width primary Save button
                  AppButton(
                    label: 'save'.tr(),
                    onPressed: () async {
                      final updated = product.copyWith(
                        title: titleCtrl.text.trim(),
                        description: descCtrl.text.trim(),
                        price: double.tryParse(priceCtrl.text) ?? product.price,
                      );
                      await ref.read(productListProvider.notifier).updateProduct(updated);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('product_updated_success'.tr())),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Centered Cancel button matching width
                  SizedBox(
                    width: double.infinity,
                    height: AppSpacing.minTouchTarget,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'cancel'.tr(),
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showAppConfirmationDialog(
      context: context,
      title: 'delete_product_confirm_title'.tr(),
      message: 'delete_product_confirm_msg'.tr(),
      icon: Icons.delete_outline_rounded,
      confirmLabel: 'delete'.tr(),
      isDestructive: true,
      onConfirm: () async {
        await ref.read(productListProvider.notifier).deleteProduct(productId);
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('product_deleted_success'.tr())),
          );
        }
      },
    );
  }

  void _showSoldOutDialog(BuildContext context, WidgetRef ref, Product product) {
    showAppConfirmationDialog(
      context: context,
      title: 'Mark as Sold Out',
      message: 'Mark this item as sold out on ONDC. It remains saved in your catalogue and can be relisted anytime once restocked.',
      icon: Icons.pause_circle_outline_rounded,
      confirmLabel: 'Mark Sold Out',
      confirmColor: AppColors.brick,
      onConfirm: () async {
        final updated = product.copyWith(
          status: ProductStatus.soldOut,
          statusUpdatedAt: DateTime.now(),
        );
        await ref.read(productListProvider.notifier).updateProduct(updated);
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product marked as Sold Out.'),
              backgroundColor: AppColors.terracotta,
            ),
          );
        }
      },
    );
  }

  void _showRemoveListingDialog(BuildContext context, WidgetRef ref, Product product) {
    showAppConfirmationDialog(
      context: context,
      title: 'Remove Listing from ONDC',
      icon: Icons.visibility_off_outlined,
      confirmLabel: 'Remove from ONDC',
      confirmColor: AppColors.mustard,
      contentWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'This will pull the item from the public ONDC store immediately.',
            style: TextStyle(fontSize: 14, color: AppColors.charcoal),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Text(
              '• It remains saved in your private catalogue.\n• You can relist it back to Live status anytime.\n• This is NOT permanent deletion.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
      onConfirm: () async {
        final updated = product.copyWith(
          status: ProductStatus.listingRemoved,
          statusUpdatedAt: DateTime.now(),
        );
        await ref.read(productListProvider.notifier).updateProduct(updated);
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing removed from ONDC. Saved in your catalogue.'),
              backgroundColor: AppColors.charcoal,
            ),
          );
        }
      },
    );
  }

  Future<void> _relistProduct(BuildContext context, WidgetRef ref, Product product) async {
    final updated = product.copyWith(
      status: ProductStatus.live,
      statusUpdatedAt: DateTime.now(),
    );
    await ref.read(productListProvider.notifier).updateProduct(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product relisted and now Live on ONDC!'),
          backgroundColor: AppColors.forestGreenDark,
        ),
      );
    }
  }

  void _showLegendDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.dialog)),
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: AppSpacing.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Listing Management Guide', style: AppTextStyles.headlineMedium.copyWith(fontSize: 19), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              const Text('• Mark as Sold Out:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Keeps item visible on ONDC & catalogue but purchase is disabled. Relist anytime once restocked.\n'),
              const Text('• Remove Listing:', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('Pulls the item from public ONDC search. Remains safely in your private catalogue for future relisting.\n'),
              const Text('• Delete Product:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error)),
              const Text('Permanently deletes the product from your catalogue. Cannot be undone.'),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Understood',
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, Color, String) _statusVisual(ProductStatus status) {
    switch (status) {
      case ProductStatus.live:
        return (Icons.check_circle, AppColors.forestGreenLight.withValues(alpha: 0.2), AppColors.forestGreenDark, 'status_live');
      case ProductStatus.pendingSync:
        return (Icons.cloud_queue, AppColors.turmericLight.withValues(alpha: 0.3), AppColors.turmericDark, 'status_pending_sync');
      case ProductStatus.draft:
        return (Icons.edit_note, AppColors.surfaceVariant, AppColors.textSecondary, 'status_draft');
      case ProductStatus.sold:
        return (Icons.sell, AppColors.mustard.withValues(alpha: 0.25), AppColors.terracottaDark, 'status_sold');
      case ProductStatus.soldOut:
        return (Icons.remove_shopping_cart_outlined, AppColors.error.withValues(alpha: 0.15), AppColors.error, 'status_sold_out');
      case ProductStatus.listingRemoved:
        return (Icons.visibility_off_outlined, AppColors.mustard.withValues(alpha: 0.25), AppColors.terracottaDark, 'status_listing_removed');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);

    return AppScaffold(
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (products) {
          final product = products.firstWhere(
            (p) => p.id == productId,
            orElse: () => Product(
              id: productId,
              title: 'Craft Product',
              description: 'No product details found',
              price: 0,
              photoPath: '',
              category: 'General',
            ),
          );

          final (statusIcon, statusBg, statusFg, statusLabelKey) = _statusVisual(product.status);
          final isNonLive = product.isNonLive;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 340,
                pinned: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'edit'.tr(),
                    onPressed: () => _showEditDialog(context, ref, product),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'Listing Actions',
                    onSelected: (val) {
                      switch (val) {
                        case 'sold_out':
                          _showSoldOutDialog(context, ref, product);
                          break;
                        case 'remove_listing':
                          _showRemoveListingDialog(context, ref, product);
                          break;
                        case 'relist':
                          _relistProduct(context, ref, product);
                          break;
                        case 'delete':
                          _showDeleteDialog(context, ref);
                          break;
                        case 'legend':
                          _showLegendDialog(context);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (isNonLive)
                        const PopupMenuItem(
                          value: 'relist',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, color: AppColors.forestGreenDark, size: 18),
                              SizedBox(width: 8),
                              Text('Relist Item (Make Live)'),
                            ],
                          ),
                        )
                      else ...[
                        const PopupMenuItem(
                          value: 'sold_out',
                          child: Row(
                            children: [
                              Icon(Icons.remove_shopping_cart_outlined, color: AppColors.brick, size: 18),
                              SizedBox(width: 8),
                              Text('Mark as Sold Out'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'remove_listing',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off_outlined, color: AppColors.mustard, size: 18),
                              SizedBox(width: 8),
                              Text('Remove Listing from ONDC'),
                            ],
                          ),
                        ),
                      ],
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'legend',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('Remove vs Delete Info'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                            const SizedBox(width: 8),
                            Text('delete'.tr(), style: const TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: ColorFiltered(
                    colorFilter: isNonLive
                        ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                        : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                    child: Opacity(
                      opacity: isNonLive ? 0.72 : 1.0,
                      child: AppImage(imageUrl: product.displayPhotoPath, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (product.allPhotoPaths.length > 1) ...[
                      SizedBox(
                        height: 64,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final path in product.allPhotoPaths)
                              Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.xs),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadii.sm),
                                  child: ColorFiltered(
                                    colorFilter: isNonLive
                                        ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                                        : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                                    child: SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: AppImage(imageUrl: path, fit: BoxFit.cover),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Chip(
                          label: Text(product.category),
                          backgroundColor: AppColors.terracottaLight.withValues(alpha: 0.3),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(AppRadii.chip),
                          ),
                          child: Row(
                            children: [
                              Icon(statusIcon, size: 14, color: statusFg),
                              const SizedBox(width: 4),
                              Text(
                                statusLabelKey.tr(),
                                style: AppTextStyles.labelSmall.copyWith(color: statusFg, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.sm),

                    Text(product.title, style: AppTextStyles.displaySmall),
                    if (product.titleHi.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.titleHi,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.md),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${product.price.toStringAsFixed(0)}',
                          style: AppTextStyles.displayMedium.copyWith(
                            color: isNonLive ? AppColors.textSecondary : AppColors.terracotta,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Promote on Social Media Action Button
                    AppButton(
                      label: 'social_media_helper'.tr(),
                      icon: Icons.share_rounded,
                      onPressed: () => context.pushNamed(
                        AppRouteConstants.socialMediaHelper,
                        extra: SocialMediaArgs(
                          listingId: product.id,
                          source: 'catalogue',
                          allImages: product.allPhotoPaths,
                          title: product.title,
                          category: product.category,
                          description: product.description,
                          materials: product.tags,
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Listing Management Actions Box
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: isNonLive
                            ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'LISTING STATUS',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textTertiary,
                                  letterSpacing: 1,
                                ),
                              ),
                              if (product.statusUpdatedAt != null)
                                Text(
                                  'Updated ${product.statusUpdatedAt!.day}/${product.statusUpdatedAt!.month}/${product.statusUpdatedAt!.year}',
                                  style: AppTextStyles.caption,
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (isNonLive) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _relistProduct(context, ref, product),
                                    icon: const Icon(Icons.refresh, color: AppColors.forestGreenDark),
                                    label: const Text(
                                      'Relist Item (Make Live)',
                                      style: TextStyle(
                                        color: AppColors.forestGreenDark,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.forestGreenDark, width: 1.5),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showSoldOutDialog(context, ref, product),
                                    icon: const Icon(Icons.remove_shopping_cart_outlined, size: 16),
                                    label: const Text('Sold Out', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      side: const BorderSide(color: AppColors.border),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showRemoveListingDialog(context, ref, product),
                                    icon: const Icon(Icons.visibility_off_outlined, size: 16),
                                    label: const Text('Remove Listing', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      side: const BorderSide(color: AppColors.border),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 14, color: AppColors.textTertiary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '"Remove Listing" keeps item in your private catalogue, while "Delete" removes it permanently.',
                                  style: AppTextStyles.caption.copyWith(color: AppColors.textTertiary, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),

                    Text('product_desc_label'.tr(), style: AppTextStyles.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(product.description, style: AppTextStyles.bodyLarge),
                    if (product.descriptionHi.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        product.descriptionHi,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),

                    if (product.tags.isNotEmpty) ...[
                      Text('tags_label'.tr(), style: AppTextStyles.headlineSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: product.tags.map((tag) {
                          return Chip(
                            label: Text('#$tag'),
                            backgroundColor: AppColors.surfaceVariant,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    Text(
                      '${'created_on'.tr()}: ${product.createdAt.day}/${product.createdAt.month}/${product.createdAt.year}',
                      style: AppTextStyles.caption,
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}