import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/services/app_tts_service.dart';
import '../../../core/services/tts_page_guides.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/motifs/mehrab_clipper.dart';
import '../../../core/widgets/speaker_affordance.dart';

class _PackagingStep {
  final IconData icon;
  final String title;
  final String detail;
  final bool isWarning;
  const _PackagingStep({
    required this.icon,
    required this.title,
    required this.detail,
    this.isWarning = false,
  });
}

Map<String, List<_PackagingStep>> _guideForCategory(String category) {
  final cat = category.toLowerCase();
  if (cat.contains('pottery') || cat.contains('ceramic') || cat.contains('clay')) {
    return {
      'pottery': [
        _PackagingStep(
          icon: Icons.layers_outlined,
          title: 'packaging_pottery_step1_title'.tr(),
          detail: 'packaging_pottery_step1_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'packaging_pottery_step2_title'.tr(),
          detail: 'packaging_pottery_step2_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'packaging_pottery_step3_title'.tr(),
          detail: 'packaging_pottery_step3_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.warning_amber_rounded,
          title: 'packaging_pottery_step4_title'.tr(),
          detail: 'packaging_pottery_step4_detail'.tr(),
          isWarning: true,
        ),
      ],
    };
  } else if (cat.contains('textile') || cat.contains('fabric') || cat.contains('saree') || cat.contains('silk') || cat.contains('cloth')) {
    return {
      'textile': [
        _PackagingStep(
          icon: Icons.layers_outlined,
          title: 'packaging_textile_step1_title'.tr(),
          detail: 'packaging_textile_step1_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.water_drop_outlined,
          title: 'packaging_textile_step2_title'.tr(),
          detail: 'packaging_textile_step2_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'packaging_textile_step3_title'.tr(),
          detail: 'packaging_textile_step3_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.sticky_note_2_outlined,
          title: 'packaging_textile_step4_title'.tr(),
          detail: 'packaging_textile_step4_detail'.tr(),
        ),
      ],
    };
  } else if (cat.contains('jewel') || cat.contains('silver') || cat.contains('gold') || cat.contains('brass')) {
    return {
      'jewelry': [
        _PackagingStep(
          icon: Icons.diamond_outlined,
          title: 'packaging_jewelry_step1_title'.tr(),
          detail: 'packaging_jewelry_step1_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.padding_outlined,
          title: 'packaging_jewelry_step2_title'.tr(),
          detail: 'packaging_jewelry_step2_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.lock_outline,
          title: 'packaging_jewelry_step3_title'.tr(),
          detail: 'packaging_jewelry_step3_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.shield_outlined,
          title: 'packaging_jewelry_step4_title'.tr(),
          detail: 'packaging_jewelry_step4_detail'.tr(),
          isWarning: true,
        ),
      ],
    };
  } else if (cat.contains('wood') || cat.contains('toy') || cat.contains('cane') || cat.contains('bamboo')) {
    return {
      'woodwork': [
        _PackagingStep(
          icon: Icons.dry_cleaning_outlined,
          title: 'packaging_woodwork_step1_title'.tr(),
          detail: 'packaging_woodwork_step1_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'packaging_woodwork_step2_title'.tr(),
          detail: 'packaging_woodwork_step2_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'packaging_woodwork_step3_title'.tr(),
          detail: 'packaging_woodwork_step3_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.wb_sunny_outlined,
          title: 'packaging_woodwork_step4_title'.tr(),
          detail: 'packaging_woodwork_step4_detail'.tr(),
          isWarning: true,
        ),
      ],
    };
  } else {
    return {
      'general': [
        _PackagingStep(
          icon: Icons.bubble_chart_outlined,
          title: 'packaging_general_step1_title'.tr(),
          detail: 'packaging_general_step1_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.inventory_2_outlined,
          title: 'packaging_general_step2_title'.tr(),
          detail: 'packaging_general_step2_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.label_outline,
          title: 'packaging_general_step3_title'.tr(),
          detail: 'packaging_general_step3_detail'.tr(),
        ),
        _PackagingStep(
          icon: Icons.local_shipping_outlined,
          title: 'packaging_general_step4_title'.tr(),
          detail: 'packaging_general_step4_detail'.tr(),
        ),
      ],
    };
  }
}

/// Shows the packaging guide sheet with the scalloped Mehrab top edge motif.
void showPackagingSuggestionsSheet(
  BuildContext context, {
  required String category,
  VoidCallback? onMarkPacked,
}) {
  showMehrabBottomSheet(
    context: context,
    builder: (ctx) => PackagingSuggestionsSheet(
      category: category,
      onMarkPacked: onMarkPacked,
    ),
  );
}

class PackagingSuggestionsSheet extends StatefulWidget {
  final String category;
  final VoidCallback? onMarkPacked;

  const PackagingSuggestionsSheet({
    super.key,
    required this.category,
    this.onMarkPacked,
  });

  @override
  State<PackagingSuggestionsSheet> createState() =>
      _PackagingSuggestionsSheetState();
}

class _PackagingSuggestionsSheetState extends State<PackagingSuggestionsSheet> {
  final AppTtsService _tts = AppTtsService();
  bool _voiceUnavailable = false;

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

  Future<void> _speakAllSteps(List<_PackagingStep> steps) async {
    if (_tts.isSpeaking) {
      await _tts.stop();
      return;
    }

    final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final isHindi = locale == 'hi';
    final languageCode = isHindi ? 'hi' : 'en';
    final prefix = isHindi ? 'चरण' : 'Step';
    final sentence = steps
        .asMap()
        .entries
        .map((e) => '$prefix ${e.key + 1}: ${e.value.title}. ${e.value.detail}')
        .join(' ');

    final guide = TtsPageGuides.packaging.forLanguage(languageCode);

    final result = await _tts.speak(
      guide + sentence,
      languageCode: languageCode,
    );

    if (mounted) {
      setState(() => _voiceUnavailable = result == TtsResult.voiceUnavailable);
    }
  }

  Future<void> _handleVoiceDownload() async {
    final opened = await _tts.openVoiceDownloadScreen();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('voice_download_settings_hint'.tr()),
        ),
      );
    }
  }

  String _localizedCategory(BuildContext context, String cat) {
    final isHi = (Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode) ==
        'hi';
    if (!isHi) return cat;
    final lower = cat.toLowerCase();
    if (lower.contains('pottery') || lower.contains('clay') || lower.contains('ceramic')) {
      return 'filter_pottery'.tr();
    } else if (lower.contains('textile') || lower.contains('saree') || lower.contains('silk') || lower.contains('fabric') || lower.contains('handloom')) {
      return 'filter_textiles'.tr();
    } else if (lower.contains('jewel') || lower.contains('silver') || lower.contains('gold') || lower.contains('brass')) {
      return 'filter_jewelry'.tr();
    } else if (lower.contains('wood') || lower.contains('toy') || lower.contains('bamboo') || lower.contains('cane')) {
      return 'filter_woodwork'.tr();
    } else if (lower.contains('paint') || lower.contains('art')) {
      return 'filter_paintings'.tr();
    }
    return cat;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _guideForCategory(widget.category).values.first;

    return Padding(
      padding: const EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 6.0,
        bottom: 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with icon, title/sub and round close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.terracottaLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.terracottaDark,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'packaging_suggestions_title'.tr(),
                      style: AppTextStyles.headlineSmall.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _localizedCategory(context, widget.category),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.inkSoft,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              SpeakerAffordance(
                isSpeaking: _tts.isSpeaking,
                onTap: () => _speakAllSteps(steps),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: AppColors.parchmentDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_voiceUnavailable)
            VoiceUnavailableNotice(onDownload: _handleVoiceDownload),

          const SizedBox(height: 18),

          // Packaging steps list
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isWarning = step.isWarning;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step icon pill
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isWarning
                          ? AppColors.goldLight
                          : AppColors.terracottaLight,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isWarning
                          ? Icon(
                              step.icon,
                              size: 13,
                              color: AppColors.goldDark,
                            )
                          : Icon(
                              step.icon,
                              size: 13,
                              color: AppColors.terracottaDark,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: AppTextStyles.labelMedium.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.detail,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),

          // Primary action button
          AppButton(
            label: widget.onMarkPacked != null
                ? 'update_status_packed'.tr()
                : 'ready_to_pack'.tr(),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onMarkPacked?.call();
            },
          ),
        ],
      ),
    );
  }
}
