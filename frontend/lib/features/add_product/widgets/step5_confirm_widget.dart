import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/speaker_affordance.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../data/models/product.dart';
import '../../../data/services/social_media_service.dart';
import '../../social_media/providers/social_media_provider.dart';
import '../../home/screens/home_shell.dart';

class Step5ConfirmWidget extends ConsumerStatefulWidget {
  const Step5ConfirmWidget({super.key});

  @override
  ConsumerState<Step5ConfirmWidget> createState() => _Step5ConfirmWidgetState();
}

class _Step5ConfirmWidgetState extends ConsumerState<Step5ConfirmWidget> {
  bool _isPublishing = false;
  final AppTtsService _tts = AppTtsService();

  @override
  void initState() {
    super.initState();
    _tts.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  // This is the last checkpoint before the listing goes live. Reading the
  // full title, description, and price back as one summary is the final
  // version of the same correctness gate as step 3 — the artisan confirms
  // what is actually about to publish, not just what was drafted earlier.
  //
  // Title and description are picked by the current app language, not
  // hardcoded to English — speaking English text through a Hindi voice
  // renders it as mispronounced phonetic gibberish, the same code-mixing
  // failure the voice pipeline's transcription stage exists to avoid.
  Future<void> _speakSummary({
    required String titleEn,
    required String titleHi,
    required String descriptionEn,
    required String descriptionHi,
    required double price,
  }) async {
    if (_tts.isSpeaking) {
      await _tts.stop();
      return;
    }
    final isHindi = context.locale.languageCode == 'hi';
    final title = isHindi && titleHi.isNotEmpty ? titleHi : titleEn;
    final description = isHindi && descriptionHi.isNotEmpty ? descriptionHi : descriptionEn;
    final priceStatement = isHindi
        ? 'मूल्य ${price.toStringAsFixed(0)} रुपये। '
        : 'Price: ${price.toStringAsFixed(0)} rupees. ';
    final guide =
        TtsPageGuides.confirmPublish.forLanguage(context.locale.languageCode);
    final summary = '$guide$title. $priceStatement$description';
    final result = await _tts.speak(
      summary,
      languageCode: context.locale.languageCode,
    );
    if (result == TtsResult.voiceUnavailable && mounted) {
      final opened = await _tts.openVoiceDownloadScreen();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please download the voice from phone settings'),
          ),
        );
      }
    }
  }

  Future<void> _handleListProduct() async {
    setState(() => _isPublishing = true);

    final draft = ref.read(addProductFlowProvider);
    final isOnline = ref.read(connectivityProvider).value ?? true;

    const fallbackPhoto =
        'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=600&q=80';

    final newProduct = Product(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted ${draft.category}',
      titleHi: draft.titleHi,
      description: draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript,
      descriptionHi: draft.descriptionHi,
      price: draft.finalPrice,
      photoPath: draft.originalImagePath.isNotEmpty ? draft.originalImagePath : fallbackPhoto,
      aiEnhancedPhotoPath: draft.isEnhanced ? draft.enhancedImagePath : '',
      additionalPhotoPaths: draft.additionalImagePaths,
      category: draft.category,
      tags: draft.tags,
      status: isOnline ? ProductStatus.live : ProductStatus.pendingSync,
      createdAt: DateTime.now(),
    );

    final createdProduct = await ref.read(productListProvider.notifier).addProduct(newProduct);

    if (isOnline && draft.draftId.isNotEmpty) {
      try {
        await HttpSocialMediaService().linkDraftsToListing(
          draftKey: draft.draftId,
          listingId: createdProduct.id,
        );
      } catch (_) {
        // Publishing should still succeed if draft linking is temporarily unavailable.
      }
    }

    if (mounted) {
      setState(() => _isPublishing = false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return AlertDialog(
            backgroundColor: AppColors.parchment,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
            title: Row(
              children: [
                Icon(
                  isOnline ? Icons.check_circle : Icons.cloud_queue,
                  color: isOnline ? AppColors.success : AppColors.goldDark,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.sm),
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
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
            ),
            actions: [
              AppButton(
                label: 'done'.tr(),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ref.read(addProductFlowProvider.notifier).reset();
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
    final displayImage = draft.isEnhanced ? draft.enhancedImagePath : draft.originalImagePath;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.terracotta, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('confirm_title'.tr(), style: AppTextStyles.headlineLarge),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'confirm_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),

          // Product Summary Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.line),
              boxShadow: AppElevation.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Image
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    color: AppColors.parchmentDeep,
                    child: AppImage(imageUrl: displayImage, fit: BoxFit.cover),
                  ),
                ),

                if (draft.additionalImagePaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final path in draft.additionalImagePaths)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: AppImage(imageUrl: path, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.parchmentDeep,
                              borderRadius: BorderRadius.circular(AppRadii.button),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Text(
                              draft.category,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnline ? AppColors.statusSuccessBg : AppColors.statusPendingBg,
                              borderRadius: BorderRadius.circular(AppRadii.button),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isOnline ? AppColors.statusSuccessFg : AppColors.statusPendingFg,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isOnline ? 'status_live'.tr() : 'status_pending_sync'.tr(),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: isOnline ? AppColors.statusSuccessFg : AppColors.statusPendingFg,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.centerRight,
                        child: SpeakerAffordance(
                          isSpeaking: _tts.isSpeaking,
                          onTap: () => _speakSummary(
                            titleEn: draft.titleEn.isNotEmpty
                                ? draft.titleEn
                                : 'Handcrafted ${draft.category}',
                            titleHi: draft.titleHi,
                            descriptionEn: draft.descriptionEn.isNotEmpty
                                ? draft.descriptionEn
                                : draft.voiceTranscript,
                            descriptionHi: draft.descriptionHi,
                            price: draft.finalPrice,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted ${draft.category}',
                        style: AppTextStyles.headlineMedium,
                      ),
                      if (draft.titleHi.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          draft.titleHi,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
                        ),
                      ],

                      const SizedBox(height: 12),

                      Text(
                        '₹${draft.finalPrice.toStringAsFixed(0)}',
                        style: AppTextStyles.displaySmall.copyWith(
                          color: AppColors.terracottaDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.inkSoft,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 14),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified, color: AppColors.success, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'floor_price_guarantee'.tr(),
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
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

          const SizedBox(height: 20),

          if (draft.originalImagePath.isNotEmpty || draft.additionalImagePaths.isNotEmpty) ...[
            AppButton(
              label: 'social_media_helper'.tr(),
              icon: Icons.share,
              type: AppButtonType.secondary,
              onPressed: () {
                final images = [
                  if (draft.isEnhanced && draft.enhancedImagePath.isNotEmpty)
                    draft.enhancedImagePath
                  else
                    draft.originalImagePath,
                  ...draft.additionalImagePaths,
                ].where((path) => path.isNotEmpty).toList();

                context.pushNamed(
                  AppRouteConstants.socialMediaHelper,
                  extra: SocialMediaArgs(
                    draftKey: draft.draftId,
                    source: 'add_flow',
                    allImages: images,
                    title: draft.titleEn,
                    category: draft.category,
                    description: draft.descriptionEn.isNotEmpty
                        ? draft.descriptionEn
                        : draft.voiceTranscript,
                    materials: draft.tags,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],

          AppButton(
            label: 'list_product_btn'.tr(),
            icon: Icons.cloud_upload_outlined,
            isLoading: _isPublishing,
            onPressed: _handleListProduct,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}