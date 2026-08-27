import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/providers/app_providers.dart';

class Step3AiReviewWidget extends ConsumerStatefulWidget {
  const Step3AiReviewWidget({super.key});

  @override
  ConsumerState<Step3AiReviewWidget> createState() => _Step3AiReviewWidgetState();
}

class _Step3AiReviewWidgetState extends ConsumerState<Step3AiReviewWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _titleEnCtrl = TextEditingController();
  final TextEditingController _titleHiCtrl = TextEditingController();
  final TextEditingController _descEnCtrl = TextEditingController();
  final TextEditingController _descHiCtrl = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  static const List<String> categories = [
    'Pottery',
    'Textiles',
    'Woodwork',
    'Jewelry',
    'Paintings',
    'Metalcraft',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initTts();
  }

  void _initTts() {
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _flutterTts.setErrorHandler((msg) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleEnCtrl.dispose();
    _titleHiCtrl.dispose();
    _descEnCtrl.dispose();
    _descHiCtrl.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _syncControllersWithState() {
    final draft = ref.read(addProductFlowProvider);
    if (_titleEnCtrl.text != draft.titleEn) _titleEnCtrl.text = draft.titleEn;
    if (_titleHiCtrl.text != draft.titleHi) _titleHiCtrl.text = draft.titleHi;
    if (_descEnCtrl.text != draft.descriptionEn) _descEnCtrl.text = draft.descriptionEn;
    if (_descHiCtrl.text != draft.descriptionHi) _descHiCtrl.text = draft.descriptionHi;
  }

  Future<void> _speakDescription() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() => _isSpeaking = false);
      return;
    }

    final draft = ref.read(addProductFlowProvider);
    final isHindi = _tabController.index == 1;

    final textToSpeak = isHindi
        ? '${draft.titleHi}. ${draft.descriptionHi}'
        : '${draft.titleEn}. ${draft.descriptionEn}';

    if (textToSpeak.trim().isEmpty) return;

    try {
      setState(() => _isSpeaking = true);
      await _flutterTts.setLanguage(isHindi ? 'hi-IN' : 'en-US');
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.85);
      await _flutterTts.speak(textToSpeak);
    } catch (e) {
      debugPrint('TTS Error: $e');
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  void _onSaveAndNext() {
    ref.read(addProductFlowProvider.notifier).updateListingDetails(
          titleEn: _titleEnCtrl.text,
          titleHi: _titleHiCtrl.text,
          descriptionEn: _descEnCtrl.text,
          descriptionHi: _descHiCtrl.text,
        );
    ref.read(addProductFlowProvider.notifier).nextStep();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(addProductFlowProvider);
    _syncControllersWithState();

    if (draft.isAiProcessing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.terracotta),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'generating_listing'.tr(),
                style: AppTextStyles.headlineMedium.copyWith(color: AppColors.terracotta),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'AI is translating and generating SEO-friendly bilingual titles and descriptions...',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.terracotta),
              const SizedBox(width: AppSpacing.xs),
              Text('ai_review_title'.tr(), style: AppTextStyles.headlineLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ai_review_subtitle'.tr(),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),

          // Audio Listen Back Button (TTS)
          AppButton(
            label: _isSpeaking ? 'stop_recording'.tr() : 'listen_back'.tr(),
            type: AppButtonType.outlined,
            icon: _isSpeaking ? Icons.stop : Icons.volume_up,
            customColor: AppColors.indigo,
            onPressed: _speakDescription,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Tabbed English / Hindi Toggle
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.terracotta,
              labelColor: AppColors.terracotta,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: AppTextStyles.labelLarge,
              tabs: [
                Tab(text: 'tab_english'.tr()),
                Tab(text: 'tab_hindi'.tr()),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Tab View for Title & Description
          SizedBox(
            height: 230,
            child: TabBarView(
              controller: _tabController,
              children: [
                // English Form
                Column(
                  children: [
                    TextField(
                      controller: _titleEnCtrl,
                      decoration: InputDecoration(
                        labelText: '${'product_title_label'.tr()} (EN)',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _descEnCtrl,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: '${'product_desc_label'.tr()} (EN)',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ],
                ),
                // Hindi Form
                Column(
                  children: [
                    TextField(
                      controller: _titleHiCtrl,
                      decoration: InputDecoration(
                        labelText: '${'product_title_label'.tr()} (HI)',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _descHiCtrl,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: '${'product_desc_label'.tr()} (HI)',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Category Chips
          Text('category_label'.tr(), style: AppTextStyles.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: categories.map((cat) {
              final isSelected = draft.category.toLowerCase() == cat.toLowerCase();
              return ChoiceChip(
                label: Text(cat),
                selected: isSelected,
                selectedColor: AppColors.terracottaLight,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(addProductFlowProvider.notifier).updateListingDetails(category: cat);
                    ref.read(addProductFlowProvider.notifier).calculatePriceSuggestion();
                  }
                },
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.md),

          // Tags Chips
          Text('tags_label'.tr(), style: AppTextStyles.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: draft.tags.map((tag) {
              return Chip(
                label: Text('#$tag'),
                backgroundColor: AppColors.surfaceVariant,
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.xl),

          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'looks_good'.tr(),
                  icon: Icons.arrow_forward,
                  onPressed: _onSaveAndNext,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              AppButton(
                label: 'regenerate'.tr(),
                type: AppButtonType.outlined,
                width: 140,
                icon: Icons.refresh,
                onPressed: () {
                  String localeCode = 'en';
                  try {
                    localeCode = context.locale.languageCode;
                  } catch (_) {}
                  ref.read(addProductFlowProvider.notifier).generateAiListing(localeCode);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
