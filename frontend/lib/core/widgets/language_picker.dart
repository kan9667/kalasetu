import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import '../providers/app_providers.dart';
import 'motifs/mehrab_clipper.dart';

class LanguagePicker extends ConsumerWidget {
  final bool isCompact;

  const LanguagePicker({super.key, this.isCompact = false});

  static const List<Map<String, String>> languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ்'},
    {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা'},
  ];

  void _showLanguageBottomSheet(BuildContext context, WidgetRef ref) {
    showMehrabBottomSheet(
      context: context,
      builder: (modalContext) {
        final profileLang = ref.read(userProfileProvider).preferredLanguage;
        final liveLocale = Localizations.maybeLocaleOf(context)?.languageCode ??
            EasyLocalization.of(context)?.locale.languageCode ??
            profileLang;
        final currentLocaleCode = liveLocale.isNotEmpty ? liveLocale : 'en';

        return Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.screenPadding,
            right: AppSpacing.screenPadding,
            bottom: AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.language, color: AppColors.terracotta, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'select_language'.tr(),
                    style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(color: AppColors.line, height: 1),
              const SizedBox(height: AppSpacing.xs),
              ...languages.map((lang) {
                final isSelected = currentLocaleCode == lang['code'];
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: '${lang['name']} (${lang['native']})',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      title: Text(
                        lang['name']!,
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.terracotta : AppColors.ink,
                        ),
                      ),
                      subtitle: Text(
                        lang['native']!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: AppColors.terracotta)
                          : const Icon(Icons.circle_outlined, color: AppColors.border),
                      onTap: () async {
                        final newLocale = Locale(lang['code']!);
                        try {
                          await context.setLocale(newLocale);
                          debugPrint('setLocale SUCCESS: ${newLocale.languageCode}');
                        } catch (e, st) {
                          debugPrint('setLocale ERROR: $e\n$st');
                        }

                        // Also update profile state
                        final currentProfile = ref.read(userProfileProvider);
                        ref.read(userProfileProvider.notifier).updateProfile(
                              currentProfile.copyWith(preferredLanguage: lang['code']!),
                            );

                        if (modalContext.mounted) {
                          Navigator.pop(modalContext);
                        }
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileLang = ref.watch(userProfileProvider).preferredLanguage;
    final liveLocale = Localizations.maybeLocaleOf(context)?.languageCode ??
        EasyLocalization.of(context)?.locale.languageCode ??
        profileLang;
    final currentCode = liveLocale.isNotEmpty ? liveLocale : 'en';

    final currentLang = languages.firstWhere(
      (l) => l['code'] == currentCode,
      orElse: () => languages[0],
    );

    return Semantics(
      button: true,
      label: 'Current language: ${currentLang['name']}. Double tap to change.',
      child: InkWell(
        onTap: () => _showLanguageBottomSheet(context, ref),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
            minWidth: AppSpacing.minTouchTarget,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSpacing.sm : AppSpacing.md,
            vertical: isCompact ? AppSpacing.xs : AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: isCompact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.language, size: AppSpacing.iconSize, color: AppColors.terracotta),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${currentLang['native']} (${currentLang['name']})',
                style: AppTextStyles.labelMedium,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.arrow_drop_down, size: AppSpacing.iconSize, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}