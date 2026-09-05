import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/providers/app_providers.dart';

class Step3AiReviewWidget extends ConsumerStatefulWidget {
  const Step3AiReviewWidget({super.key});

  @override
  ConsumerState<Step3AiReviewWidget> createState() =>
      _Step3AiReviewWidgetState();
}

class _Step3AiReviewWidgetState extends ConsumerState<Step3AiReviewWidget> {
  final TextEditingController _customTagController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  int _selectedLanguageIndex = 0; // 0 for EN, 1 for HI
  String? _processingDraftId;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(addProductFlowProvider);
    _titleController.text =
        _selectedLanguageIndex == 0 ? draft.titleEn : draft.titleHi;
    _descController.text =
        _selectedLanguageIndex == 0 ? draft.descriptionEn : draft.descriptionHi;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initiateProcessing();
    });
  }

  void _initiateProcessing() {
    if (!mounted) return;
    final draft = ref.read(addProductFlowProvider);
    if (draft.originalImagePath.isEmpty || draft.currentStep != 2) return;
    // If already enhanced and voice note transcribed, do not trigger processing again
    if (draft.isEnhanced && (draft.voiceTranscript.isNotEmpty || draft.recordedAudioPath.isEmpty)) {
      return;
    }
    if (_processingDraftId == draft.draftId) return;
    _processingDraftId = draft.draftId;
    final isOnline = ref.read(connectivityProvider).value ?? true;
    String localeCode = 'hi';
    try {
      localeCode = context.locale.languageCode;
    } catch (_) {}
    ref
        .read(addProductFlowProvider.notifier)
        .submitForAiProcessing(isOnline, languageCode: localeCode);
  }

  @override
  void dispose() {
    _customTagController.dispose();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _showRetakePhotoSheet() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFBF8F2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Retake Photo', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFC86D51)),
                title: const Text('Take New Photo (Camera)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final img = await picker.pickImage(source: ImageSource.camera);
                  if (img != null) {
                    await ref.read(addProductFlowProvider.notifier).retakePhoto(File(img.path));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF4A3E35)),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final img = await picker.pickImage(source: ImageSource.gallery);
                  if (img != null) {
                    await ref.read(addProductFlowProvider.notifier).retakePhoto(File(img.path));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    final isOnline = ref.watch(connectivityProvider).value ?? true;

    if (draft.currentStep == 2 &&
        draft.originalImagePath.isNotEmpty &&
        !draft.isEnhanced &&
        _processingDraftId != draft.draftId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initiateProcessing();
      });
    }

    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final nowOnline = next.value == true;
      if (!wasOffline || !nowOnline) return;

      String localeCode = 'en';
      try {
        localeCode = context.locale.languageCode;
      } catch (_) {}
      ref
          .read(addProductFlowProvider.notifier)
          .submitForAiProcessing(true, languageCode: localeCode);
    });

    ref.listen<AddProductDraft>(addProductFlowProvider, (previous, next) {
      final currentExpectedTitle =
          _selectedLanguageIndex == 0 ? next.titleEn : next.titleHi;
      if (_titleController.text != currentExpectedTitle &&
          (previous == null ||
              (_selectedLanguageIndex == 0
                      ? previous.titleEn
                      : previous.titleHi) !=
                  currentExpectedTitle)) {
        _titleController.text = currentExpectedTitle;
      }
      final currentExpectedDesc =
          _selectedLanguageIndex == 0 ? next.descriptionEn : next.descriptionHi;
      if (_descController.text != currentExpectedDesc &&
          (previous == null ||
              (_selectedLanguageIndex == 0
                      ? previous.descriptionEn
                      : previous.descriptionHi) !=
                  currentExpectedDesc)) {
        _descController.text = currentExpectedDesc;
      }
    });

    final hasEnhancedImage =
        draft.isEnhanced &&
        draft.enhancedImagePath.isNotEmpty &&
        draft.enhancedImagePath != draft.originalImagePath;

    return Stack(
      children: [
        SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draft.originalImagePath.isNotEmpty) ...[
            SizedBox(
              height: 240,
              child: hasEnhancedImage
                  ? _BeforeAfterSlider(
                      beforePath: draft.originalImagePath,
                      afterPath: draft.enhancedImagePath,
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AppImage(
                              imageUrl: draft.enhancedImagePath.isNotEmpty
                                  ? draft.enhancedImagePath
                                  : draft.originalImagePath,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        if (draft.isAiProcessing && !draft.isEnhanced)
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Enhancing image and creating listing...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _showRetakePhotoSheet,
                icon: const Icon(
                  Icons.camera_alt_outlined,
                  size: 18,
                  color: Color(0xFF8C533E),
                ),
                label: const Text(
                  'Retake Photo',
                  style: TextStyle(
                    color: Color(0xFF8C533E),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFFC86D51),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ai_review_title'.tr(),
                  style: AppTextStyles.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ai_review_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: const Color(0xFF7A6E63),
            ),
          ),
          const SizedBox(height: 16),

          // Bilingual Toggle Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEBE3D5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLanguageIndex = 0;
                        _titleController.text = draft.titleEn;
                        _descController.text = draft.descriptionEn;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedLanguageIndex == 0
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedLanguageIndex == 0
                            ? [
                                const BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'tab_english'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedLanguageIndex == 0
                              ? const Color(0xFFC86D51)
                              : const Color(0xFF7A6E63),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLanguageIndex = 1;
                        _titleController.text = draft.titleHi;
                        _descController.text = draft.descriptionHi;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedLanguageIndex == 1
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _selectedLanguageIndex == 1
                            ? [
                                const BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'tab_hindi'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedLanguageIndex == 1
                              ? const Color(0xFFC86D51)
                              : const Color(0xFF7A6E63),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'product_title_label'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: const Color(0xFFFAF7F2),
            ),
            onChanged: (val) {
              if (_selectedLanguageIndex == 0) {
                ref
                    .read(addProductFlowProvider.notifier)
                    .updateListingDetails(titleEn: val);
              } else {
                ref
                    .read(addProductFlowProvider.notifier)
                    .updateListingDetails(titleHi: val);
              }
            },
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _descController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'product_desc_label'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: const Color(0xFFFAF7F2),
            ),
            onChanged: (val) {
              if (_selectedLanguageIndex == 0) {
                ref
                    .read(addProductFlowProvider.notifier)
                    .updateListingDetails(descriptionEn: val);
              } else {
                ref
                    .read(addProductFlowProvider.notifier)
                    .updateListingDetails(descriptionHi: val);
              }
            },
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: draft.tags.map((tag) {
              return Chip(
                label: Text(
                  '#$tag',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4A3E35),
                  ),
                ),
                backgroundColor: const Color(0xFFEBE3D5),
                deleteIconColor: const Color(0xFF7A6E63),
                onDeleted: () =>
                    ref.read(addProductFlowProvider.notifier).removeTag(tag),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTagController,
                  decoration: InputDecoration(
                    hintText: 'add_custom_tag_hint'.tr(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFFAF7F2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_customTagController.text.trim().isNotEmpty) {
                    ref
                        .read(addProductFlowProvider.notifier)
                        .addTag(_customTagController.text.trim());
                    _customTagController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC86D51),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  minimumSize: Size.zero,
                ),
                child: Text(
                  'add'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Center(
            child: TextButton.icon(
              onPressed: () {
                ref.read(addProductFlowProvider.notifier).setStep(1);
              },
              icon: const Icon(
                Icons.mic_none_outlined,
                size: 18,
                color: Color(0xFF8C533E),
              ),
              label: Text(
                're_record'.tr(),
                style: const TextStyle(
                  color: Color(0xFF8C533E),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                flex: 6,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ref.read(addProductFlowProvider.notifier).submitForPricingAndAdvance(),
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'looks_good'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC86D51),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (!isOnline) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "You're offline — reconnect to regenerate the listing.",
                          ),
                        ),
                      );
                      return;
                    }
                    final lang = _selectedLanguageIndex == 0 ? 'en' : 'hi';
                    ref
                        .read(addProductFlowProvider.notifier)
                        .regenerateAll(languageCode: lang);
                  },
                  icon: Icon(
                    Icons.refresh,
                    color: isOnline
                        ? const Color(0xFF4A3E35)
                        : const Color(0xFFB3A99A),
                    size: 18,
                  ),
                  label: Text(
                    'regenerate_btn'.tr(),
                    style: TextStyle(
                      color: isOnline
                          ? const Color(0xFF4A3E35)
                          : const Color(0xFFB3A99A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isOnline
                          ? const Color(0xFFD6C7B2)
                          : const Color(0xFFE8E0D3),
                    ),
                    backgroundColor: const Color(0xFFF7F2EA),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
    // Overlay card — shown only when Regenerate is in progress
    if (draft.isRegenerating)
      Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: const Color(0xFFFBF8F2),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFFC86D51),
                    backgroundColor: Color(0xFFEBE3D5),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Enhancing image and creating listing',
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'AI is enhancing your product photo and regenerating your catalog listing.',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: const Color(0xFF7A6E63),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      ],
    );
  }
}


/// Draggable before/after image comparison. Drag or tap anywhere across the
/// widget to move the divider; the left side shows [beforePath], the right
/// side shows [afterPath].
class _BeforeAfterSlider extends StatefulWidget {
  final String beforePath;
  final String afterPath;

  const _BeforeAfterSlider({required this.beforePath, required this.afterPath});

  @override
  State<_BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<_BeforeAfterSlider> {
  double _sliderPosition = 0.5;

  void _updatePosition(Offset localPosition, double width) {
    setState(() {
      _sliderPosition = (localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFFF3EDE2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final handleX = _sliderPosition * width;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  _updatePosition(details.localPosition, width),
              onTapDown: (details) =>
                  _updatePosition(details.localPosition, width),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AppImage(
                      imageUrl: widget.afterPath,
                      fit: BoxFit.cover,
                      fallbackWidget: Container(
                        color: const Color(0xFFF3EDE2),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFFC86D51),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Loading enhanced photo...',
                                style: TextStyle(fontSize: 12, color: Color(0xFF7A6E63)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _LeftEdgeClipper(width: handleX),
                      child: AppImage(
                        imageUrl: widget.beforePath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    left: handleX - 1,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(width: 2, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: handleX - 18,
                    top: height / 2 - 18,
                    child: IgnorePointer(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: Color(0xFF3F342B),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IgnorePointer(
                      child: _SliderLabel(
                        text: 'Before',
                        dimmed: _sliderPosition < 0.15,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: _SliderLabel(
                        text: 'After',
                        dimmed: _sliderPosition > 0.85,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Text(
                        '← Drag to compare →',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeftEdgeClipper extends CustomClipper<Rect> {
  final double width;
  _LeftEdgeClipper({required this.width});

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(covariant _LeftEdgeClipper oldClipper) =>
      oldClipper.width != width;
}

class _SliderLabel extends StatelessWidget {
  final String text;
  final bool dimmed;

  const _SliderLabel({required this.text, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0.4 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
