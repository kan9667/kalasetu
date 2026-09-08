import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/cycling_guidance_cue.dart';
import '../../../core/widgets/motifs/dotted_border_box.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../../../core/providers/app_providers.dart';

class Step1CaptureWidget extends ConsumerStatefulWidget {
  const Step1CaptureWidget({super.key});

  @override
  ConsumerState<Step1CaptureWidget> createState() => _Step1CaptureWidgetState();
}

class _Step1CaptureWidgetState extends ConsumerState<Step1CaptureWidget> {
  final ImagePicker _picker = ImagePicker();
  bool _isPickingImage = false;

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isPickingImage = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked != null) {
        debugPrint('[Step1Capture] Image selected: ${picked.path}');
        await ref.read(addProductFlowProvider.notifier).queueImage(File(picked.path));
      }
    } catch (e, st) {
      debugPrint('[Step1Capture] Image picker error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _addAdditionalImage() async {
    setState(() => _isPickingImage = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (picked != null) {
        debugPrint('[Step1Capture] Additional image selected: ${picked.path}');
        await ref.read(addProductFlowProvider.notifier).addAdditionalImage(picked.path);
      }
    } catch (e, st) {
      debugPrint('[Step1Capture] Additional image error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  List<GuidanceCue> get _captureCues => [
    GuidanceCue(
      text: 'capture_cue_1'.tr(),
      icon: Icons.touch_app_outlined,
    ),
    GuidanceCue(
      text: 'capture_cue_2'.tr(),
      icon: Icons.crop_free_rounded,
    ),
    GuidanceCue(
      text: 'capture_cue_3'.tr(),
      icon: Icons.zoom_in_rounded,
    ),
    GuidanceCue(
      text: 'capture_cue_4'.tr(),
      icon: Icons.wb_sunny_outlined,
    ),
    GuidanceCue(
      text: 'capture_cue_5'.tr(),
      icon: Icons.straighten_rounded,
    ),
  ];

  Widget _buildGuidanceCues() {
    return CyclingGuidanceCue(
      headerTitle: 'photo_tips_title'.tr().toUpperCase(),
      headerIcon: Icons.tips_and_updates_outlined,
      spokenIntro: 'step1_tts_intro'.tr(),
      cues: _captureCues,
      isPaused: _isPickingImage,
      onCueChanged: (cue) {
        // TTS playback hook
      },
    );
  }

  void _showPhotoSourceSheet() {
    showMehrabBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'choose_photo_source'.tr(),
                style: AppTextStyles.headlineMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.parchmentDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: AppColors.terracotta),
                ),
                title: Text('take_photo'.tr(), style: AppTextStyles.headlineSmall),
                subtitle: Text('capture_new_photo_sub'.tr(), style: AppTextStyles.bodySmall),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const Divider(color: AppColors.line),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.parchmentDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library, color: AppColors.ink),
                ),
                title: Text('upload_gallery'.tr(), style: AppTextStyles.headlineSmall),
                subtitle: Text('choose_gallery_sub'.tr(), style: AppTextStyles.bodySmall),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    final hasImage = draft.originalImagePath.isNotEmpty;
    final displayImagePath = draft.isEnhanced && draft.enhancedImagePath.isNotEmpty
        ? draft.enhancedImagePath
        : draft.originalImagePath;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step Title & Subtitle
          Text(
            hasImage ? 'review_photo_title'.tr() : 'capture_title'.tr(),
            style: AppTextStyles.headlineLarge,
          ),
          const SizedBox(height: 4),
          Text(
            hasImage ? 'review_photo_subtitle'.tr() : 'capture_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 14),

          // Cycling guidance cues with fade transitions
          _buildGuidanceCues(),
          const SizedBox(height: 16),

          if (!hasImage) ...[
            // Photo capture placeholder with dotted border motif
            DottedBorderBox(
              width: double.infinity,
              height: 200,
              backgroundColor: AppColors.parchmentDeep,
              radius: AppRadii.card,
              borderColor: AppColors.dottedBorder,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: AppColors.cardSurface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x0C000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 36, color: AppColors.terracotta),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'capture_instructions'.tr(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'take_photo'.tr(),
              icon: Icons.camera_alt,
              isLoading: _isPickingImage,
              onPressed: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'upload_gallery'.tr(),
              icon: Icons.photo_library,
              type: AppButtonType.outlined,
              isLoading: _isPickingImage,
              onPressed: () => _pickImage(ImageSource.gallery),
            ),
          ] else ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppElevation.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: AppImage(
                    imageUrl: displayImagePath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'additional_angles_title'.tr(),
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'additional_angles_subtitle'.tr(),
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 72,
              child: Row(
                children: [
                  ...draft.additionalImagePaths.map((path) {
                    return Stack(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(color: AppColors.line),
                            image: DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 10,
                          child: GestureDetector(
                            onTap: () => ref.read(addProductFlowProvider.notifier).removeAdditionalImage(path),
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  if (draft.additionalImagePaths.length < 2)
                    InkWell(
                      onTap: _addAdditionalImage,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.parchmentDeep,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.terracotta),
                            const SizedBox(height: 2),
                            Text(
                              'add_another_angle'.tr(),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.inkSoft,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            AppButton(
              label: 'accept_photo'.tr(),
              icon: Icons.check_circle_outline,
              onPressed: () => ref.read(addProductFlowProvider.notifier).confirmPhoto(),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'redo_photo'.tr(),
              icon: Icons.refresh,
              type: AppButtonType.outlined,
              onPressed: _showPhotoSourceSheet,
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}