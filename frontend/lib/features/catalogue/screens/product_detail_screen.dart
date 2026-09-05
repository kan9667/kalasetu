import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';

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
        return AlertDialog(
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowAlignment: OverflowBarAlignment.center,
          title: Text('edit_product_title'.tr(), style: AppTextStyles.headlineMedium),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr()),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'save'.tr(),
              width: 100,
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
          ],
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowAlignment: OverflowBarAlignment.center,
          title: Text('delete_product_confirm_title'.tr(), style: AppTextStyles.headlineMedium),
          content: Text('delete_product_confirm_msg'.tr(), style: AppTextStyles.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('cancel'.tr()),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brick),
              onPressed: () async {
                await ref.read(productListProvider.notifier).deleteProduct(productId);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('product_deleted_success'.tr())),
                  );
                }
              },
              child: Text('delete'.tr(), style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
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
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'delete'.tr(),
                    onPressed: () => _showDeleteDialog(context, ref),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: AppImage(imageUrl: product.displayPhotoPath, fit: BoxFit.cover),
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
                                  child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: AppImage(imageUrl: path, fit: BoxFit.cover),
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
                                style: AppTextStyles.labelSmall.copyWith(color: statusFg),
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

                    Text(
                      '₹${product.price.toStringAsFixed(0)}',
                      style: AppTextStyles.displayMedium.copyWith(
                        color: AppColors.terracotta,
                        fontWeight: FontWeight.bold,
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