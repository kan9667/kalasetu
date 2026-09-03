import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/offline_sync/models/queue_item.dart';

class Step1CaptureWidget extends ConsumerStatefulWidget {
  const Step1CaptureWidget({super.key});

  @override
  ConsumerState<Step1CaptureWidget> createState() => _Step1CaptureWidgetState();
}

class _Step1CaptureWidgetState extends ConsumerState<Step1CaptureWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
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
    }
  }

  Future<void> _addAdditionalImage() async {
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
    }
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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3F342B),
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasImage ? 'review_photo_subtitle'.tr() : 'capture_subtitle'.tr(),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7A6E63),
            ),
          ),
          const SizedBox(height: 16),

          if (!hasImage) ...[
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFF3EDE2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDFD5C6), width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE5DAC8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 36, color: Color(0xFF8C533E)),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'capture_instructions'.tr(),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6F6358)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
              label: Text('take_photo'.tr(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC86D51),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library, color: Color(0xFF4A3E35), size: 20),
              label: Text('upload_gallery'.tr(), style: const TextStyle(color: Color(0xFF4A3E35), fontSize: 16, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD6C7B2)),
                backgroundColor: const Color(0xFFF7F2EA),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 230,
                width: double.infinity,
                child: AppImage(
                  imageUrl: displayImagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'additional_angles_title'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF3F342B)),
            ),
            const SizedBox(height: 2),
            Text(
              'additional_angles_subtitle'.tr(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF7A6E63)),
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
                            borderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3EDE2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFDFD5C6)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined, size: 20, color: Color(0xFF8C533E)),
                            const SizedBox(height: 2),
                            Text(
                              'add_another_angle'.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF6F6358), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: () => ref.read(addProductFlowProvider.notifier).confirmPhoto(),
              icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              label: Text('accept_photo'.tr(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC86D51),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.refresh, color: Color(0xFF4A3E35), size: 20),
              label: Text('redo_photo'.tr(), style: const TextStyle(color: Color(0xFF4A3E35), fontSize: 16, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD6C7B2)),
                backgroundColor: const Color(0xFFF7F2EA),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}