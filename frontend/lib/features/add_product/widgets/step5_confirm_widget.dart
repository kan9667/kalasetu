import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/product.dart';
import '../../home/screens/home_shell.dart';

class Step5ConfirmWidget extends ConsumerStatefulWidget {
  const Step5ConfirmWidget({super.key});

  @override
  ConsumerState<Step5ConfirmWidget> createState() => _Step5ConfirmWidgetState();
}

class _Step5ConfirmWidgetState extends ConsumerState<Step5ConfirmWidget> {
  bool _isPublishing = false;

  Future<void> _handleListProduct() async {
    setState(() => _isPublishing = true);

    final draft = ref.read(addProductFlowProvider);
    final isOnline = ref.read(connectivityProvider).value ?? true;

    final newProduct = Product(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted ${draft.category}',
      titleHi: draft.titleHi,
      description: draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript,
      descriptionHi: draft.descriptionHi,
      price: draft.finalPrice,
      imageUrl: draft.enhancedImagePath.isNotEmpty
          ? draft.enhancedImagePath
          : 'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=600&q=80',
      category: draft.category,
      tags: draft.tags,
      status: isOnline ? ProductStatus.live : ProductStatus.pendingSync,
      createdAt: DateTime.now(),
    );

    // Save product via Riverpod productListProvider
    await ref.read(productListProvider.notifier).addProduct(newProduct);

    if (mounted) {
      setState(() => _isPublishing = false);

      // Show success modal feedback
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isOnline ? Icons.check_circle : Icons.cloud_queue,
                  color: isOnline ? AppColors.forestGreen : AppColors.turmericDark,
                  size: 32,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    isOnline ? 'listing_online_success'.tr() : 'queued_offline_success'.tr(),
                    style: AppTextStyles.headlineMedium,
                  ),
                ),
              ],
            ),
            content: Text(
              isOnline
                  ? 'Your craft listing is live and visible to buyers.'
                  : 'Product saved locally. KalaSetu will automatically upload it when internet returns.',
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              AppButton(
                label: 'done'.tr(),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  // Reset Add Product flow draft
                  ref.read(addProductFlowProvider.notifier).reset();
                  // Switch tab to Catalogue (index 1)
                  ref.read(homeTabIndexProvider.notifier).state = 1;
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check, color: AppColors.terracotta),
              const SizedBox(width: AppSpacing.xs),
              Text('confirm_title'.tr(), style: AppTextStyles.headlineLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'confirm_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Product Summary Card
          Card(
            elevation: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
                  ),
                  child: AppImage(imageUrl: draft.enhancedImagePath, fit: BoxFit.cover),
                ),

                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge & Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            label: Text(draft.category),
                            backgroundColor: AppColors.terracottaLight.withValues(alpha: 0.3),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? AppColors.forestGreenLight.withValues(alpha: 0.2)
                                  : AppColors.turmericLight.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(AppRadii.chip),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isOnline ? Icons.circle : Icons.cloud_queue,
                                  size: 10,
                                  color: isOnline ? AppColors.forestGreen : AppColors.turmericDark,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isOnline ? 'status_live'.tr() : 'status_pending_sync'.tr(),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: isOnline ? AppColors.forestGreenDark : AppColors.turmericDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      Text(
                        draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted ${draft.category}',
                        style: AppTextStyles.headlineMedium,
                      ),
                      if (draft.titleHi.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          draft.titleHi,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.md),

                      Text(
                        '₹${draft.finalPrice.toStringAsFixed(0)}',
                        style: AppTextStyles.headlineLarge.copyWith(
                          color: AppColors.terracotta,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: AppSpacing.sm),

                      Text(
                        draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript,
                        style: AppTextStyles.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Ethical Floor Guarantee Badge
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.forestGreenLight.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified, color: AppColors.forestGreen, size: 18),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                'floor_price_guarantee'.tr(),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.forestGreenDark,
                                ),
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
          ),

          const SizedBox(height: AppSpacing.xl),

          AppButton(
            label: 'list_product_btn'.tr(),
            icon: Icons.cloud_upload,
            isLoading: _isPublishing,
            onPressed: _handleListProduct,
          ),
        ],
      ),
    );
  }
}
