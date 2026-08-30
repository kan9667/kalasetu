import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/language_picker.dart';
import '../../../core/providers/app_providers.dart';

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCode = context.locale.languageCode;

    return AppScaffold(
      title: 'language_settings_title'.tr(),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        itemCount: LanguagePicker.languages.length,
        separatorBuilder: (c, i) => const Divider(),
        itemBuilder: (context, index) {
          final lang = LanguagePicker.languages[index];
          final isSelected = currentCode == lang['code'];

          return ListTile(
            title: Text(lang['name']!, style: AppTextStyles.bodyLarge),
            subtitle: Text(lang['native']!, style: AppTextStyles.bodyMedium),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: AppColors.terracotta, size: 28)
                : const Icon(Icons.circle_outlined, color: AppColors.textTertiary, size: 28),
            onTap: () async {
              final newLocale = Locale(lang['code']!);
              await context.setLocale(newLocale);

              final currentProfile = ref.read(userProfileProvider);
              ref.read(userProfileProvider.notifier).updateProfile(
                currentProfile.copyWith(preferredLanguage: lang['code']!),
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Language set to ${lang['name']}')),
                );
              }
            },
          );
        },
      ),
    );
  }
}