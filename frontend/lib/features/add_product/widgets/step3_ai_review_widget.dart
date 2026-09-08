import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../../../core/widgets/speaker_affordance.dart';
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
  final AppTtsService _tts = AppTtsService();
  bool _initializedLanguageFromLocale = false;

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
    _tts.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedLanguageFromLocale) {
      _initializedLanguageFromLocale = true;
      final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
              EasyLocalization.of(context)?.locale.languageCode) ==
          'hi';
      if (isHindi) {
        _selectedLanguageIndex = 1;
        final draft = ref.read(addProductFlowProvider);
        _titleController.text = draft.titleHi;
        _descController.text = draft.descriptionHi;
      }
    }
  }

  // Reads back the title and description in whichever language is currently
  // selected. This is the app's core correctness gate: the listing text is
  // AI-generated from the artisan's voice note, and many artisans cannot
  // read it to check the AI understood them correctly — hearing it is the
  // only way they can verify it before it goes live.
  //
  // The guide comes first so the artisan knows they are allowed to correct
  // the text and which button moves them on; hearing the listing alone does
  // not tell them either.
  Future<void> _speakListing() async {
    if (_tts.isSpeaking) {
      await _tts.stop();
      return;
    }
    // The language toggle on this screen, not the app locale, decides which
    // version is on screen — so it decides what is spoken, guide included.
    final languageCode = _selectedLanguageIndex == 0 ? 'en' : 'hi';
    final guide = TtsPageGuides.aiListingReview.forLanguage(languageCode);
    final text = '$guide${_titleController.text}. ${_descController.text}';

    final result = await _tts.speak(text, languageCode: languageCode);

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
    final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    final localeCode = isHindi ? 'hi' : 'en';
    ref
        .read(addProductFlowProvider.notifier)
        .submitForAiProcessing(isOnline, languageCode: localeCode);
  }

  @override
  void dispose() {
    _customTagController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _showRetakePhotoSheet() async {
    final picker = ImagePicker();
    showMehrabBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('retake_photo_title'.tr(), style: AppTextStyles.headlineMedium),
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
                onTap: () async {
                  Navigator.pop(ctx);
                  final img = await picker.pickImage(source: ImageSource.camera);
                  if (img != null) {
                    await ref.read(addProductFlowProvider.notifier).retakePhoto(File(img.path));
                  }
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
                onTap: () async {
                  Navigator.pop(ctx);
                  final img = await picker.pickImage(source: ImageSource.gallery);
                  if (img != null) {
                    await ref.read(addProductFlowProvider.notifier).retakePhoto(File(img.path));
                  }
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

      final isHindi = (Localizations.maybeLocaleOf(context)?.languageCode ??
              EasyLocalization.of(context)?.locale.languageCode) ==
          'hi';
      final localeCode = isHindi ? 'hi' : 'en';
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
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
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
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            boxShadow: AppElevation.cardShadow,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: AppImage(
                                    imageUrl: draft.enhancedImagePath.isNotEmpty
                                        ? draft.enhancedImagePath
                                        : draft.originalImagePath,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
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
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'enhancing_image'.tr(),
                                            style: const TextStyle(
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
                        ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _showRetakePhotoSheet,
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                      color: AppColors.terracottaDark,
                    ),
                    label: Text(
                      'retake_photo_title'.tr(),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.terracottaDark,
                        fontWeight: FontWeight.w600,
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
                    color: AppColors.terracotta,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ai_review_title'.tr(),
                      style: AppTextStyles.headlineLarge,
                    ),
                  ),
                  SpeakerAffordance(
                    isSpeaking: _tts.isSpeaking,
                    onTap: _speakListing,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'ai_review_subtitle'.tr(),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 16),

              // Bilingual Toggle Tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.parchmentDeep,
                  borderRadius: BorderRadius.circular(AppRadii.button),
                  border: Border.all(color: AppColors.line),
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
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedLanguageIndex == 0
                                ? AppColors.cardSurface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadii.button),
                            boxShadow: _selectedLanguageIndex == 0
                                ? AppElevation.cardShadow
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'tab_english'.tr(),
                            style: AppTextStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _selectedLanguageIndex == 0
                                  ? AppColors.terracotta
                                  : AppColors.inkSoft,
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
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedLanguageIndex == 1
                                ? AppColors.cardSurface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadii.button),
                            boxShadow: _selectedLanguageIndex == 1
                                ? AppElevation.cardShadow
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'tab_hindi'.tr(),
                            style: AppTextStyles.labelMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _selectedLanguageIndex == 1
                                  ? AppColors.terracotta
                                  : AppColors.inkSoft,
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
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  labelText: 'product_title_label'.tr(),
                  labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.terracotta, width: 1.5),
                  ),
                  filled: true,
                  fillColor: AppColors.cardSurface,
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
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  labelText: 'product_desc_label'.tr(),
                  labelStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.inkSoft),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: const BorderSide(color: AppColors.terracotta, width: 1.5),
                  ),
                  filled: true,
                  fillColor: AppColors.cardSurface,
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
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.terracottaDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: AppColors.terracottaLight,
                    deleteIconColor: AppColors.terracottaDark,
                    side: BorderSide.none,
                    onDeleted: () =>
                        ref.read(addProductFlowProvider.notifier).removeTag(tag),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTagController,
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                      decoration: InputDecoration(
                        hintText: 'add_custom_tag_hint'.tr(),
                        hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.inkFaint),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          borderSide: const BorderSide(color: AppColors.terracotta, width: 1.5),
                        ),
                        filled: true,
                        fillColor: AppColors.cardSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: AppButton(
                      label: 'add'.tr(),
                      isCompact: true,
                      onPressed: () {
                        if (_customTagController.text.trim().isNotEmpty) {
                          ref
                              .read(addProductFlowProvider.notifier)
                              .addTag(_customTagController.text.trim());
                          _customTagController.clear();
                        }
                      },
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
                    color: AppColors.terracottaDark,
                  ),
                  label: Text(
                    're_record'.tr(),
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.terracottaDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              AppButton(
                label: 'looks_good'.tr(),
                icon: Icons.arrow_forward,
                onPressed: () =>
                    ref.read(addProductFlowProvider.notifier).submitForPricingAndAdvance(),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'regenerate_btn'.tr(),
                icon: Icons.refresh,
                type: AppButtonType.outlined,
                onPressed: () {
                  if (!isOnline) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'offline_regenerate_warning'.tr(),
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
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              color: AppColors.parchment,
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
                        color: AppColors.terracotta,
                        backgroundColor: AppColors.parchmentDeep,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'ai_regenerating_title'.tr(),
                      style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ai_regenerating_subtitle'.tr(),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.inkSoft,
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppElevation.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          color: AppColors.parchmentDeep,
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
                          color: AppColors.parchmentDeep,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.terracotta,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Loading enhanced photo...',
                                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
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
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: IgnorePointer(
                        child: _SliderLabel(
                          text: 'slider_before'.tr(),
                          dimmed: _sliderPosition < 0.15,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IgnorePointer(
                        child: _SliderLabel(
                          text: 'slider_after'.tr(),
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
                          'slider_drag_compare'.tr(),
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
