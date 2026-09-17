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

/// Screen for reviewing an existing product draft or relisting prior to publication approval.
///
/// Invariants enforced:
/// 1. Fetches authoritative product from backend on entry when online.
/// 2. Displays the exact revision and SHA-256 content hash that will be submitted.
/// 3. Never calls `addProduct`. Strictly calls `approveAndPublishProduct`.
/// 4. Detects revision mismatch between navigation snapshot and server, displaying
///    a warning and requiring fresh confirmation of the updated content.
/// 5. Offline approval queues only the exact locally reviewed revision and marks
///    the product as `pendingApprovalSync`.
class ReviewExistingProductScreen extends ConsumerStatefulWidget {
  final Product initialProduct;

  const ReviewExistingProductScreen({
    super.key,
    required this.initialProduct,
  });

  @override
  ConsumerState<ReviewExistingProductScreen> createState() =>
      _ReviewExistingProductScreenState();
}

class _ReviewExistingProductScreenState
    extends ConsumerState<ReviewExistingProductScreen> {
  late Product _currentProduct;
  late int _initialRevision;
  bool _isLoading = true;
  bool _isPublishing = false;
  bool _hasRevisionMismatch = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.initialProduct;
    _initialRevision = widget.initialProduct.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAuthoritativeProduct();
    });
  }

  Future<void> _fetchAuthoritativeProduct() async {
    setState(() {
      _isLoading = true;
      _fetchError = null;
    });

    bool isOnline;
    final currentConn = ref.read(connectivityProvider);
    if (currentConn.hasValue) {
      isOnline = currentConn.value ?? false;
    } else {
      try {
        isOnline = await ref.read(connectivityProvider.future);
      } catch (_) {
        isOnline = false;
      }
    }

    if (!isOnline) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final authoritative =
          await ref.read(apiServiceProvider).getProduct(widget.initialProduct.id);
      if (mounted) {
        setState(() {
          if (authoritative.revision != _initialRevision) {
            _hasRevisionMismatch = true;
          }
          _currentProduct = authoritative;
          _isLoading = false;
          _fetchError = null;
        });
      }
    } catch (e) {
      debugPrint(
          '[ReviewExistingProductScreen] Failed to fetch authoritative product: $e');
      if (mounted) {
        setState(() {
          _fetchError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleApproveAndPublish() async {
    setState(() => _isPublishing = true);
    try {
      final published = await ref
          .read(productListProvider.notifier)
          .approveAndPublishProduct(
            _currentProduct.id,
            revision: _currentProduct.revision,
            contentHash: _currentProduct.contentHash,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(published.status == ProductStatus.pendingApprovalSync
                ? 'approval_queued_offline'.tr()
                : 'product_published_successfully'.tr()),
            backgroundColor: AppColors.statusSuccessFg,
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Publish failed: $e'),
            backgroundColor: AppColors.terracotta,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('review_listing'.tr()),
          backgroundColor: AppColors.surface,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.terracotta),
        ),
      );
    }

    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';

    final title = isHindi && _currentProduct.titleHi.isNotEmpty
        ? _currentProduct.titleHi
        : _currentProduct.title;
    final description = isHindi && _currentProduct.descriptionHi.isNotEmpty
        ? _currentProduct.descriptionHi
        : _currentProduct.description;

    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      if (next.value == true && !_isPublishing && mounted) {
        _fetchAuthoritativeProduct();
      }
    });

    final isOnline = ref.watch(connectivityProvider).value == true;
    final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
    final hasValidContentHash = _currentProduct.contentHash != null &&
        sha256Pattern.hasMatch(_currentProduct.contentHash!.toLowerCase());
    final hasValidRevision = _currentProduct.revision > 0;

    final bool canApprove = !_isPublishing &&
        _fetchError == null &&
        (isOnline || (hasValidRevision && hasValidContentHash));

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        title: Text('review_listing'.tr()),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (_fetchError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.statusActionBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.statusActionFg),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.statusActionFg),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Unable to fetch authoritative product from server. Publication disabled for data integrity.',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.statusActionFg,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _fetchAuthoritativeProduct,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),

                  if (!isOnline && (!hasValidRevision || !hasValidContentHash))
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.statusActionBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.statusActionFg),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined,
                              color: AppColors.statusActionFg),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Offline approval requires a valid revision and 64-character SHA-256 hash. Connect online to verify product integrity before publishing.',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.statusActionFg,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_hasRevisionMismatch)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.goldLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.goldDark),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.goldDark),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Server product was updated (Rev $_initialRevision ➔ Rev ${_currentProduct.revision}). Please review updated content before confirming.',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.goldDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Image Preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: AppImage(
                        imageUrl: _currentProduct.displayPhotoPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Technical Integrity Metadata Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Authoritative Revision: ${_currentProduct.revision}',
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.parchmentDeep,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _currentProduct.status.name.toUpperCase(),
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Content Hash: ${_currentProduct.contentHash ?? "Pending calculation"}',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppColors.inkSoft,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Title & Description
                  Text(
                    title,
                    style: AppTextStyles.headlineMedium.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Pricing & Cost Floor
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Listing Price',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                            Text(
                              '₹${_currentProduct.price.toStringAsFixed(0)}',
                              style: AppTextStyles.headlineMedium.copyWith(
                                color: AppColors.terracotta,
                              ),
                            ),
                          ],
                        ),
                        if ((_currentProduct.floorPrice ?? 0) > 0) ...[
                          const Divider(height: AppSpacing.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Calculated Cost Floor',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.inkSoft,
                                ),
                              ),
                              Text(
                                '₹${_currentProduct.floorPrice!.toStringAsFixed(0)}',
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.oak,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Confirm & Publish Action Bar
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: AppButton(
                label: _isPublishing
                    ? 'Publishing...'
                    : (_fetchError != null
                        ? 'Verification Failed (Approval Disabled)'
                        : (!isOnline && (!hasValidRevision || !hasValidContentHash)
                            ? 'Offline Verification Required'
                            : 'Approve and Publish Revision ${_currentProduct.revision}')),
                isLoading: _isPublishing,
                onPressed: canApprove ? _handleApproveAndPublish : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
