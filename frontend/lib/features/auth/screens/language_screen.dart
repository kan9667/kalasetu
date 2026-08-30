import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/language_picker.dart';
import '../../../core/providers/app_providers.dart';

class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String _selectedCode = 'en';

  Future<void> _handleContinue() async {
    await context.setLocale(Locale(_selectedCode));

    final currentProfile = ref.read(userProfileProvider);
    ref.read(userProfileProvider.notifier).updateProfile(
          currentProfile.copyWith(preferredLanguage: _selectedCode),
        );

    await ref.read(hasSelectedLanguageProvider.notifier).markLanguageSelected();

    if (mounted) {
      context.goNamed(AppRouteConstants.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenPadding = AppSpacing.getScreenPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const Icon(Icons.language, size: 48, color: AppColors.terracotta),
              const SizedBox(height: AppSpacing.md),
              Text(
                'choose_language_title'.tr(),
                style: AppTextStyles.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'choose_language_subtitle'.tr(),
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final lang in LanguagePicker.languages)
                        Semantics(
                          button: true,
                          selected: _selectedCode == lang['code'],
                          label: '${lang['name']} (${lang['native']})',
                          child: InkWell(
                            onTap: () => setState(() => _selectedCode = lang['code']!),
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.md,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedCode == lang['code']
                                    ? AppColors.terracotta
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadii.xl),
                                border: Border.all(
                                  color: _selectedCode == lang['code']
                                      ? AppColors.terracottaDark
                                      : AppColors.oak,
                                ),
                              ),
                              child: Text(
                                lang['native']!,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _selectedCode == lang['code']
                                      ? AppColors.textOnPrimary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'continue_btn'.tr(),
                onPressed: _handleContinue,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}