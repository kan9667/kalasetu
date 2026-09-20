import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../../data/models/product.dart';
import '../../../data/services/api_service.dart';
import '../../social_media/providers/social_media_provider.dart';
import '../../social_media/widgets/social_media_launchpad_sheet.dart';
import '../../home/screens/home_shell.dart';

import '../../../core/storage/private_media_cache.dart';

class Step5ConfirmWidget extends ConsumerStatefulWidget {
  const Step5ConfirmWidget({super.key});

  @override
  ConsumerState<Step5ConfirmWidget> createState() => _Step5ConfirmWidgetState();
}

class _Step5ConfirmWidgetState extends ConsumerState<Step5ConfirmWidget> {
  bool _isPublishing = false;
  bool _previewFailed = false;
  bool _isRenderVerified = false;
  String? _verifiedAsset;
  String? _verifiedChecksum;
  int? _verifiedSessionGen;
  int? _verifiedImageGen;
  String? _verifiedMediaId;
  Product? _publishedProduct;
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

  void _handleRenderSuccess({
    required String assetIdentity,
    required String sha256Checksum,
    int? sessionGeneration,
  }) {
    // Strictly reject missing checksums or empty asset identity
    if (sha256Checksum.isEmpty || assetIdentity.isEmpty) {
      debugPrint('[Step5Confirm] Render callback rejected: missing checksum or asset identity');
      if (mounted && _isRenderVerified) {
        setState(() {
          _isRenderVerified = false;
          _previewFailed = true;
        });
      }
      return;
    }

    final draft = ref.read(addProductFlowProvider);
    final activeSessionGen = PrivateMediaCache.instance.sessionGeneration;

    // Reject callback if private media session does not match active session
    if (sessionGeneration != null && sessionGeneration != activeSessionGen) {
      debugPrint(
        '[Step5Confirm] Render callback rejected: session mismatch ($sessionGeneration vs active $activeSessionGen)',
      );
      if (mounted && _isRenderVerified) {
        setState(() {
          _isRenderVerified = false;
          _previewFailed = true;
        });
      }
      return;
    }

    final bool isEnhancedPublish = draft.mediaId != null && draft.mediaId!.isNotEmpty;

    if (isEnhancedPublish) {
      final expectedMediaId = draft.mediaId!;
      final matchesEnhanced = assetIdentity.contains(expectedMediaId) ||
          (draft.enhancedImagePath.isNotEmpty && assetIdentity == draft.enhancedImagePath);
      if (!matchesEnhanced) {
        debugPrint(
          '[Step5Confirm] Render callback rejected: asset "$assetIdentity" does not match publish mediaId "$expectedMediaId"',
        );
        if (mounted && _isRenderVerified) {
          setState(() {
            _isRenderVerified = false;
            _previewFailed = true;
          });
        }
        return;
      }
      if (draft.sha256Checksum != null &&
          draft.sha256Checksum!.isNotEmpty &&
          sha256Checksum.isNotEmpty &&
          draft.sha256Checksum != sha256Checksum) {
        debugPrint(
          '[Step5Confirm] Render callback rejected: checksum mismatch ($sha256Checksum vs ${draft.sha256Checksum})',
        );
        if (mounted && _isRenderVerified) {
          setState(() {
            _isRenderVerified = false;
            _previewFailed = true;
          });
        }
        return;
      }
    } else {
      final expectedPath = draft.immutablePhotoSnapshotPath.isNotEmpty
          ? draft.immutablePhotoSnapshotPath
          : draft.originalImagePath;
      if (assetIdentity != expectedPath && !assetIdentity.endsWith(expectedPath)) {
        debugPrint(
          '[Step5Confirm] Render callback rejected: asset "$assetIdentity" does not match raw path "$expectedPath"',
        );
        if (mounted && _isRenderVerified) {
          setState(() {
            _isRenderVerified = false;
            _previewFailed = true;
          });
        }
        return;
      }
      if (draft.immutablePhotoSnapshotSha256 != null &&
          draft.immutablePhotoSnapshotSha256!.isNotEmpty &&
          sha256Checksum.isNotEmpty &&
          draft.immutablePhotoSnapshotSha256 != sha256Checksum) {
        debugPrint(
          '[Step5Confirm] Render callback rejected: offline snapshot checksum mismatch ($sha256Checksum vs ${draft.immutablePhotoSnapshotSha256})',
        );
        if (mounted && _isRenderVerified) {
          setState(() {
            _isRenderVerified = false;
            _previewFailed = true;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isRenderVerified = true;
        _previewFailed = false;
        _verifiedAsset = assetIdentity;
        _verifiedChecksum = sha256Checksum;
        _verifiedSessionGen = sessionGeneration;
        _verifiedImageGen = draft.imageInputGeneration;
        _verifiedMediaId = draft.mediaId;
      });
    }
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
    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final langCode = isHindi ? 'hi' : 'en';
    final title = isHindi && titleHi.isNotEmpty ? titleHi : titleEn;
    final description = isHindi && descriptionHi.isNotEmpty ? descriptionHi : descriptionEn;
    final priceStatement = isHindi
        ? 'मूल्य ${price.toStringAsFixed(0)} रुपये। '
        : 'Price: ${price.toStringAsFixed(0)} rupees. ';
    final guide = TtsPageGuides.confirmPublish.forLanguage(langCode);
    final summary = '$guide$title. $priceStatement$description';
    final result = await _tts.speak(
      summary,
      languageCode: langCode,
    );
    if (result == TtsResult.voiceUnavailable && mounted) {
      final opened = await _tts.openVoiceDownloadScreen();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('voice_download_settings_hint'.tr()),
          ),
        );
      }
    }
  }

  Future<void> _handleListProduct() async {
    final draft = ref.read(addProductFlowProvider);

    // INVARIANT: Runtime check enforcing exact media review.
    if (draft.mediaId != null && draft.boundMediaGeneration != draft.imageInputGeneration) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot publish: Media asset belongs to a previous photo. Please retake or re-verify.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final hasValidLocalPhoto = draft.originalImagePath.isNotEmpty &&
        (draft.originalImagePath.startsWith('http') ||
            (File(draft.originalImagePath).existsSync() &&
                File(draft.originalImagePath).lengthSync() > 0));

    if (draft.mediaId == null && !hasValidLocalPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot publish: A valid product photo is required.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final activeSession = PrivateMediaCache.instance.sessionGeneration;
    final bool isSessionValid = _verifiedSessionGen == null || _verifiedSessionGen == activeSession;
    final bool isGenValid = _verifiedImageGen == draft.imageInputGeneration;
    final bool isMediaValid = (draft.mediaId == null && _verifiedMediaId == null) ||
        (draft.mediaId != null && _verifiedMediaId == draft.mediaId);

    final expectedPublishPath = draft.immutablePhotoSnapshotPath.isNotEmpty
        ? draft.immutablePhotoSnapshotPath
        : draft.originalImagePath;
    final bool isAssetValid = draft.mediaId != null
        ? (_verifiedAsset?.contains(draft.mediaId!) == true ||
            (draft.enhancedImagePath.isNotEmpty && _verifiedAsset == draft.enhancedImagePath))
        : (_verifiedAsset == expectedPublishPath || _verifiedAsset?.endsWith(expectedPublishPath) == true);

    final expectedChecksum = draft.mediaId != null
        ? draft.sha256Checksum
        : draft.immutablePhotoSnapshotSha256;
    final bool isChecksumValid = _verifiedChecksum != null &&
        _verifiedChecksum!.isNotEmpty &&
        (expectedChecksum == null ||
            expectedChecksum.isEmpty ||
            _verifiedChecksum == expectedChecksum);

    if (_previewFailed ||
        !_isRenderVerified ||
        !isSessionValid ||
        !isGenValid ||
        !isMediaValid ||
        !isAssetValid ||
        !isChecksumValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot publish: Image preview could not be verified.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    final isOnline = ref.read(connectivityProvider).value ?? true;

    final fallbackCategory = ref.read(userProfileProvider).craftType.trim().isNotEmpty
        ? ref.read(userProfileProvider).craftType.trim()
        : 'craft_category_handicraft'.tr();

    final effectiveCategory = draft.category.trim().isNotEmpty
        ? draft.category.trim()
        : fallbackCategory;

    final newProduct = Product(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      title: draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted $effectiveCategory',
      titleHi: draft.titleHi,
      description: draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript,
      descriptionHi: draft.descriptionHi,
      price: draft.finalPrice,
      photoPath: expectedPublishPath,
      aiEnhancedPhotoPath: draft.isEnhanced ? draft.enhancedImagePath : '',
      additionalPhotoPaths: draft.additionalImagePaths,
      category: effectiveCategory,
      tags: draft.tags,
      status: ProductStatus.draft, // INVARIANT: initial mutation is strictly draft
      createdAt: DateTime.now(),
      floorPrice: draft.floorPrice > 0 ? draft.floorPrice : null,
      materialsCost: draft.rawMaterialCost > 0 ? draft.rawMaterialCost : null,
      laborHours: draft.laborHours > 0 ? draft.laborHours : null,
      hourlyRate: draft.hourlyRate > 0 ? draft.hourlyRate : null,
      mediaId: draft.mediaId,
      reviewedMediaChecksum: _verifiedChecksum,
    );

    Product createdProduct;
    Product? publishedProduct;
    try {
      createdProduct = await ref.read(productListProvider.notifier).addProduct(newProduct);
      // Enforce explicit artisan approval before publishing
      publishedProduct = await ref.read(productListProvider.notifier).approveAndPublishProduct(
        createdProduct.id,
        revision: createdProduct.revision,
        contentHash: createdProduct.contentHash,
        reviewedChecksum: _verifiedChecksum,
      );
    } on StaleRevisionException catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishedProduct = null;
        });
        showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: AppColors.parchment,
            title: Text('Revision Conflict', style: AppTextStyles.headlineMedium),
            content: Text(
              e.message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                  // Return artisan to Step 3 Review to inspect latest server revision
                  ref.read(addProductFlowProvider.notifier).setStep(2);
                },
                child: const Text('Review Latest Draft'),
              ),
            ],
          ),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _publishedProduct = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error publishing product: $e')),
        );
      }
      return;
    }

    if (isOnline && draft.draftId.isNotEmpty) {
      try {
        await ref.read(socialMediaServiceProvider).linkDraftsToListing(
          draftKey: draft.draftId,
          listingId: createdProduct.id,
        );
      } catch (_) {
        // Publishing should still succeed if draft linking is temporarily unavailable.
      }
    }

    if (mounted) {
      setState(() {
        _isPublishing = false;
        _publishedProduct = publishedProduct;
      });

      final finalPrice = draft.finalPrice;
      final floorCost = draft.floorPrice > 0
          ? draft.floorPrice
          : (draft.rawMaterialCost + (draft.laborHours * draft.hourlyRate));
      final profit = (finalPrice - floorCost).clamp(0.0, double.infinity);

      // INVARIANT: Never show "listing online" unless the returned server product status is published/live!
      final bool isPublishedOnServer =
          publishedProduct.status == ProductStatus.published || publishedProduct.status == ProductStatus.live;

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
                  isPublishedOnServer ? Icons.check_circle : Icons.cloud_queue,
                  color: isPublishedOnServer ? AppColors.success : AppColors.goldDark,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isPublishedOnServer
                        ? 'listing_online_success'.tr()
                        : 'saved_offline_awaiting_sync'.tr(),
                    style: AppTextStyles.headlineMedium,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isPublishedOnServer
                        ? 'listing_online_desc'.tr()
                        : 'listing_offline_desc'.tr(),
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.line),
                      boxShadow: AppElevation.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.savings_outlined, size: 18, color: AppColors.terracotta),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'profit_popup_title'.tr(),
                                style: AppTextStyles.labelMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.terracotta,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'final_selling_price_label'.tr(),
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '₹${finalPrice.toStringAsFixed(0)}',
                                  style: AppTextStyles.headlineSmall.copyWith(color: AppColors.ink),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'floor_cost_label'.tr(),
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '₹${floorCost.toStringAsFixed(0)}',
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider(color: AppColors.line, height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.trending_up, size: 16, color: AppColors.success),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'profit_earned_label'.tr(),
                                      style: AppTextStyles.labelMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '+₹${profit.toStringAsFixed(0)}',
                                  style: AppTextStyles.headlineMedium.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: AppColors.goldDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'profit_encouragement_msg'.tr(namedArgs: {'profit': profit.toStringAsFixed(0)}),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.inkSoft,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final currentStatus = _publishedProduct?.status ?? ProductStatus.draft;
    final bool isLive = currentStatus == ProductStatus.published || currentStatus == ProductStatus.live;
    final bool mediaGenerationMismatch = draft.mediaId != null &&
        draft.boundMediaGeneration != draft.imageInputGeneration;

    // Reset render verification if draft photo generation or media identity has changed
    if (_isRenderVerified &&
        (_verifiedImageGen != draft.imageInputGeneration ||
         _verifiedMediaId != draft.mediaId)) {
      _isRenderVerified = false;
    }

    final bool isEnhancedPublish = draft.mediaId != null && draft.mediaId!.isNotEmpty;

    final localEnhancedExists = draft.isEnhanced &&
        draft.enhancedImagePath.isNotEmpty &&
        (draft.enhancedImagePath.startsWith('http') ||
            (File(draft.enhancedImagePath).existsSync() && File(draft.enhancedImagePath).lengthSync() > 0));
    final localOriginalExists = draft.originalImagePath.isNotEmpty &&
        (draft.originalImagePath.startsWith('http') ||
            (File(draft.originalImagePath).existsSync() && File(draft.originalImagePath).lengthSync() > 0));

    final String displayImage;
    if (mediaGenerationMismatch) {
      displayImage = ''; // Never render mismatched media asset
    } else if (isEnhancedPublish) {
      // INVARIANT: When publishing enhanced mediaId, NEVER display raw original!
      if (localEnhancedExists) {
        displayImage = draft.enhancedImagePath;
      } else {
        displayImage = draft.mediaId!;
      }
    } else {
      // Raw/offline publish
      if (draft.immutablePhotoSnapshotPath.isNotEmpty && File(draft.immutablePhotoSnapshotPath).existsSync()) {
        displayImage = draft.immutablePhotoSnapshotPath;
      } else if (localOriginalExists) {
        displayImage = draft.originalImagePath;
      } else {
        displayImage = '';
      }
    }

    final bool missingPhoto = displayImage.isEmpty;
    final bool isPublishBlocked = mediaGenerationMismatch || missingPhoto || _previewFailed || !_isRenderVerified;

    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final defaultTitleEn =
        draft.titleEn.isNotEmpty ? draft.titleEn : 'Handcrafted ${draft.category}';
    final primaryTitle = (isHindi && draft.titleHi.trim().isNotEmpty)
        ? draft.titleHi
        : defaultTitleEn;
    final secondaryTitle = (isHindi && draft.titleHi.trim().isNotEmpty)
        ? defaultTitleEn
        : (draft.titleHi.trim().isNotEmpty ? draft.titleHi : null);

    final defaultDescEn =
        draft.descriptionEn.isNotEmpty ? draft.descriptionEn : draft.voiceTranscript;
    final displayDescription = (isHindi && draft.descriptionHi.trim().isNotEmpty)
        ? draft.descriptionHi
        : defaultDescEn;

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
                    child: AppImage(
                      imageUrl: displayImage,
                      fit: BoxFit.cover,
                      onRenderSuccess: ({
                        required String assetIdentity,
                        required String sha256Checksum,
                        int? sessionGeneration,
                      }) {
                        _handleRenderSuccess(
                          assetIdentity: assetIdentity,
                          sha256Checksum: sha256Checksum,
                          sessionGeneration: sessionGeneration,
                        );
                      },
                      onError: () {
                        if (mounted && (!_previewFailed || _isRenderVerified)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _previewFailed = true;
                                _isRenderVerified = false;
                              });
                            }
                          });
                        }
                      },
                    ),
                  ),
                ),

                if (draft.isDegraded || draft.isVoiceDegraded || draft.isListingDegraded || draft.isPricingDegraded)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusPendingBg,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.goldLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (draft.isDegraded)
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppColors.goldDark),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  draft.degradedReason != null && draft.degradedReason!.isNotEmpty
                                      ? 'Photo Enhancement Degraded: ${draft.degradedReason}'
                                      : 'AI photo enhancement degraded to original raw image',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.goldDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (draft.isVoiceDegraded) ...[
                          if (draft.isDegraded) const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppColors.goldDark),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  draft.voiceDegradedReason != null && draft.voiceDegradedReason!.isNotEmpty
                                      ? 'Voice Transcription Degraded: ${draft.voiceDegradedReason}'
                                      : 'Voice transcription unavailable (using manual description)',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.goldDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (draft.isListingDegraded) ...[
                          if (draft.isDegraded || draft.isVoiceDegraded) const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppColors.goldDark),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  draft.listingDegradedReason != null && draft.listingDegradedReason!.isNotEmpty
                                      ? 'AI Listing Degraded: ${draft.listingDegradedReason}'
                                      : 'AI listing generation degraded to raw transcription text',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.goldDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (draft.isPricingDegraded) ...[
                          if (draft.isDegraded || draft.isVoiceDegraded || draft.isListingDegraded) const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppColors.goldDark),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  draft.pricingDegradedReason != null && draft.pricingDegradedReason!.isNotEmpty
                                      ? 'AI Pricing Degraded: ${draft.pricingDegradedReason}'
                                      : 'AI pricing guidance degraded to cost-floor fallback',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.goldDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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
                          Flexible(
                            child: Container(
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isLive ? AppColors.statusSuccessBg : AppColors.statusPendingBg,
                                borderRadius: BorderRadius.circular(AppRadii.button),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isLive ? AppColors.statusSuccessFg : AppColors.statusPendingFg,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      isLive ? 'status_live'.tr() : 'status_pending_approval_sync'.tr(),
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: isLive ? AppColors.statusSuccessFg : AppColors.statusPendingFg,
                                        fontWeight: FontWeight.bold,
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
                        primaryTitle,
                        style: AppTextStyles.headlineMedium,
                      ),
                      if (secondaryTitle != null && secondaryTitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          secondaryTitle,
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
                        displayDescription,
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

                showSocialMediaLaunchpadSheet(
                  context,
                  SocialMediaArgs(
                    draftKey: draft.draftId,
                    source: 'add_flow',
                    allImages: images,
                    title: draft.titleEn,
                    category: draft.category.trim().isNotEmpty
                        ? draft.category.trim()
                        : (ref.read(userProfileProvider).craftType.trim().isNotEmpty
                            ? ref.read(userProfileProvider).craftType.trim()
                            : 'craft_category_handicraft'.tr()),
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

          if (isPublishBlocked)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.statusActionBg,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verification Required Before Publishing',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mediaGenerationMismatch
                              ? 'The processed media asset belongs to an earlier photo. Retake or re-enhance the photo before publishing.'
                              : (missingPhoto
                                  ? 'A valid product photo is required. Placeholders cannot be published.'
                                  : 'The photo preview could not be loaded or verified. Please verify the image.'),
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          AppButton(
            label: 'list_product_btn'.tr(),
            icon: Icons.cloud_upload_outlined,
            isLoading: _isPublishing,
            onPressed: (_isPublishing || isPublishBlocked) ? null : _handleListProduct,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}