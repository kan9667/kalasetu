import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../../../core/providers/app_providers.dart';
import '../models/order.dart';
import '../services/label_maker_service.dart';

/// Bottom sheet allowing the artisan to preview the packaging label,
/// optionally edit the bilingual craft story (EN & HI), and print / share.
void showLabelPreviewSheet(BuildContext context, {required Order order}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.overlay,
    builder: (ctx) => _LabelPreviewSheet(order: order),
  );
}

class _LabelPreviewSheet extends ConsumerStatefulWidget {
  final Order order;
  const _LabelPreviewSheet({required this.order});

  @override
  ConsumerState<_LabelPreviewSheet> createState() => _LabelPreviewSheetState();
}

class _LabelPreviewSheetState extends ConsumerState<_LabelPreviewSheet> {
  late final TextEditingController _storyEnCtrl;
  late final TextEditingController _storyHiCtrl;
  bool _isEditingStory = false;
  bool _isGenerating = false;
  bool _hasCustomizedStory = false;

  @override
  void initState() {
    super.initState();
    final (defEn, defHi) = LabelMakerService.defaultCraftStoryFor(widget.order.productCategory);
    _storyEnCtrl = TextEditingController(text: defEn);
    _storyHiCtrl = TextEditingController(text: defHi);
  }

  @override
  void dispose() {
    _storyEnCtrl.dispose();
    _storyHiCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePrint() async {
    setState(() => _isGenerating = true);
    final profile = ref.read(userProfileProvider);

    final success = await LabelMakerService.generateAndShare(
      context: context,
      order: widget.order,
      artisanName: profile.name,
      artisanId: profile.id,
      artisanCluster: profile.locationCluster,
      craftType: profile.craftType,
      customStoryEn: _hasCustomizedStory ? _storyEnCtrl.text.trim() : null,
      customStoryHi: _hasCustomizedStory ? _storyHiCtrl.text.trim() : null,
      forceRegenerate: _hasCustomizedStory,
    );

    if (mounted) {
      setState(() => _isGenerating = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('label_generated_success'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('label_generation_failed'.tr()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final (washEn, washHi) = LabelMakerService.defaultWashCareFor(widget.order.productCategory);

    final effectiveId = profile.id.isNotEmpty ? profile.id : 'artisan_01';
    final ondcProfileStub = 'https://kalasetu.ondc.org/artisan/$effectiveId';

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => ClipPath(
        clipper: const MehrabClipper(),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            boxShadow: AppElevation.cardShadowLifted,
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artisan Story & Label',
                          style: AppTextStyles.headlineSmall.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Preview for Order ${widget.order.id}',
                          style: AppTextStyles.caption.copyWith(color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: AppColors.parchmentDeep,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),

            // Preview Scrollable Body
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  // Label Card Preview
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    decoration: BoxDecoration(
                      color: AppColors.parchment,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: AppColors.line, width: 1.5),
                      boxShadow: AppElevation.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Bar Preview
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.terracotta,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'KalaSetu',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'ARTISAN PACKAGING & STORY LABEL',
                                    style: TextStyle(color: Colors.white70, fontSize: 8, letterSpacing: 0.8),
                                  ),
                                ],
                              ),
                              Text(
                                widget.order.id,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Artisan block
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.terracotta,
                              radius: 18,
                              child: Text(
                                profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'A',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(profile.name, style: AppTextStyles.labelMedium),
                                  Text(
                                    '${profile.craftType} • ${profile.locationCluster}',
                                    style: AppTextStyles.caption.copyWith(color: AppColors.inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.statusSuccessBg,
                                borderRadius: BorderRadius.circular(AppRadii.chip),
                              ),
                              child: Text(
                                'ONDC Verified',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.statusSuccessFg,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Bilingual Craft Story Box
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'CRAFT STORY',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.terracottaDark,
                                      letterSpacing: 0.8,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(50, 24),
                                      foregroundColor: AppColors.terracotta,
                                    ),
                                    onPressed: () {
                                      setState(() => _isEditingStory = !_isEditingStory);
                                    },
                                    icon: Icon(_isEditingStory ? Icons.check : Icons.edit, size: 14),
                                    label: Text(
                                      _isEditingStory ? 'Done' : 'Edit',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              if (!_isEditingStory) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _storyEnCtrl.text,
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _storyHiCtrl.text,
                                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                                ),
                              ] else ...[
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _storyEnCtrl,
                                  maxLines: 2,
                                  style: AppTextStyles.bodySmall,
                                  decoration: const InputDecoration(
                                    labelText: 'English Story',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => _hasCustomizedStory = true,
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _storyHiCtrl,
                                  maxLines: 2,
                                  style: AppTextStyles.bodySmall,
                                  decoration: const InputDecoration(
                                    labelText: 'Hindi Story',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => _hasCustomizedStory = true,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Care & QR row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: AppColors.cardSurface,
                                  borderRadius: BorderRadius.circular(AppRadii.sm),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'CARE & HANDLING',
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.terracottaDark,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(washEn, style: AppTextStyles.caption.copyWith(color: AppColors.ink)),
                                    const SizedBox(height: 3),
                                    Text(washHi, style: AppTextStyles.caption.copyWith(color: AppColors.inkSoft)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.cardSurface,
                                  borderRadius: BorderRadius.circular(AppRadii.sm),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 58,
                                      height: 58,
                                      child: QrImageView(
                                        data: ondcProfileStub,
                                        version: QrVersions.auto,
                                        size: 58.0,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Scan for ONDC',
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: 9,
                                        color: AppColors.terracottaDark,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Order info summary
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.order.productTitle,
                                style: AppTextStyles.labelSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${widget.order.amount.toStringAsFixed(0)}',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.terracottaDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Deliver to: ${widget.order.buyerName}, ${widget.order.buyerLocation}',
                          style: AppTextStyles.caption.copyWith(color: AppColors.inkSoft),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),

            // Print / Share Action Bar
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: AppButton(
                label: 'Print / Share Packaging Label',
                icon: Icons.print_outlined,
                isLoading: _isGenerating,
                onPressed: _handlePrint,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}
