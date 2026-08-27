import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/responsive_widgets.dart';
import '../../../core/providers/app_providers.dart';

class Step1CaptureWidget extends ConsumerStatefulWidget {
  const Step1CaptureWidget({super.key});

  @override
  ConsumerState<Step1CaptureWidget> createState() => _Step1CaptureWidgetState();
}

class _Step1CaptureWidgetState extends ConsumerState<Step1CaptureWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (photo != null) {
        ref.read(addProductFlowProvider.notifier).setImage(photo.path);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      _useSampleImage(0);
    }
  }

  void _useSampleImage(int index) {
    final samples = ref.read(imageEnhancerServiceProvider).getSampleCraftImages();
    final sampleUrl = samples[index % samples.length];
    ref.read(addProductFlowProvider.notifier).setImage(sampleUrl);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    final samples = ref.read(imageEnhancerServiceProvider).getSampleCraftImages();
    final screenPadding = AppSpacing.getScreenPadding(context);
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 480;

    if (draft.isAiProcessing) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.terracotta),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'enhancing_image'.tr(),
                style: AppTextStyles.headlineMedium.copyWith(color: AppColors.terracotta),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'image_enhancement_description'.tr(),
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // View enhanced before/after mode when image has been selected and enhanced
    if (draft.enhancedImagePath.isNotEmpty && draft.isEnhanced) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high, color: AppColors.terracotta, size: AppSpacing.iconSize),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'enhancement_complete'.tr(),
                    style: AppTextStyles.headlineMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'before_after_hint'.tr(),
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),

            // Before / After Comparison Slider Container
            Container(
              height: isCompact ? 240 : 320,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.getCardRadius(context)),
                border: Border.all(color: AppColors.border),
                color: AppColors.surfaceVariant,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.getCardRadius(context)),
                child: Stack(
                  children: [
                    // Enhanced Background Image
                    Positioned.fill(
                      child: AppImage(imageUrl: draft.enhancedImagePath, fit: BoxFit.cover),
                    ),

                    // Label - Enhanced Studio Shot
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.forestGreen.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stars, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'AI Studio',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: isCompact ? 11 : 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Label - Original Shot
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Text(
                          'Original',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: Colors.white,
                            fontSize: isCompact ? 11 : 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Action Buttons - Stack on small screens
            ResponsiveButtonRow(
              stackOnSmallScreens: true,
              buttons: [
                AppButton(
                  label: 'accept_photo'.tr(),
                  icon: Icons.check_circle,
                  onPressed: () {
                    ref.read(addProductFlowProvider.notifier).nextStep();
                  },
                  isCompact: isCompact,
                ),
                AppButton(
                  label: 'redo_photo'.tr(),
                  type: AppButtonType.outlined,
                  icon: Icons.refresh,
                  onPressed: () {
                    ref.read(addProductFlowProvider.notifier).setImage('');
                  },
                  isCompact: isCompact,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default Capture Screen
    return SingleChildScrollView(
      padding: EdgeInsets.all(screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('capture_title'.tr(), style: AppTextStyles.headlineLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'capture_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Camera Preview Mock Container
          Container(
            height: isCompact ? 200 : 240,
            decoration: BoxDecoration(
              color: AppColors.indigoDark,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppElevation.getCardShadow(context),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        size: isCompact ? 48 : 64,
                        color: AppColors.turmericLight,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: Text(
                          'capture_instructions'.tr(),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.surfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (kIsWeb)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            'web_camera_note'.tr(),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.turmericLight,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
                // On-screen framing guide corner lines
                Positioned(
                  top: 20,
                  left: 20,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.turmeric, width: 3),
                        left: BorderSide(color: AppColors.turmeric, width: 3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.turmeric, width: 3),
                        right: BorderSide(color: AppColors.turmeric, width: 3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.turmeric, width: 3),
                        left: BorderSide(color: AppColors.turmeric, width: 3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.turmeric, width: 3),
                        right: BorderSide(color: AppColors.turmeric, width: 3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Camera and Gallery Buttons - Stack on small screens
          ResponsiveButtonRow(
            stackOnSmallScreens: true,
            buttons: [
              AppButton(
                label: 'take_photo'.tr(),
                icon: Icons.camera_alt,
                onPressed: () => _pickImage(ImageSource.camera),
                isCompact: isCompact,
              ),
              AppButton(
                label: 'upload_gallery'.tr(),
                type: AppButtonType.secondary,
                icon: Icons.photo_library,
                onPressed: () => _pickImage(ImageSource.gallery),
                isCompact: isCompact,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // Sample Craft Quick Select
          Text(
            'sample_craft_title'.tr(),
            style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: isCompact ? 80 : 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: samples.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _useSampleImage(index),
                  child: Container(
                    width: isCompact ? 80 : 90,
                    margin: const EdgeInsets.only(right: AppSpacing.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: AppImage(imageUrl: samples[index], fit: BoxFit.cover),
                    ),
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
