import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../providers/auth_provider.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    if (_formKey.currentState?.validate() ?? false) {
      final phone = _phoneController.text.trim();
      ref.read(authStateProvider.notifier).signInWithPhone(phone);
      context.goNamed(AppRouteConstants.otp, queryParameters: {'phone': phone});
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final screenPadding = AppSpacing.getScreenPadding(context);
    final isCompact = width < 480;

    return AppScaffold(
      showOfflineBanner: false,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xl),

                // Brand Mark
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.terracotta,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.palette,
                    size: 48,
                    color: AppColors.textOnPrimary,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Brand Text
                Text(
                  'KalaSetu',
                  style: AppTextStyles.displayLarge.copyWith(
                    color: AppColors.terracotta,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.sm),

                Text(
                  'sign_in_subtitle'.tr(),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppSpacing.xl),

                // Language Selector
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Container(
                        padding: EdgeInsets.all(screenPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Select Language',
                              style: AppTextStyles.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            ..._buildLanguageOptions(),
                          ],
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.language, size: AppSpacing.iconSize),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'English',
                            style: AppTextStyles.labelMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.arrow_drop_down, size: AppSpacing.iconSize),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Phone Input Form
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: 'phone_label'.tr(),
                      hintText: 'phone_hint'.tr(),
                      prefixIcon: const Icon(Icons.phone),
                      counterText: '',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'phone_required'.tr();
                      }
                      if (value.length < 10) {
                        return 'phone_invalid'.tr();
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Continue Button
                AppButton(
                  label: 'continue_btn'.tr(),
                  onPressed: _handleContinue,
                  isCompact: isCompact,
                ),

                const SizedBox(height: AppSpacing.md),

                // NGO Assist Button
                AppButton(
                  label: 'ngo_assist_btn'.tr(),
                  type: AppButtonType.outlined,
                  icon: Icons.support_agent,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          'ngo_assist_title'.tr(),
                          style: AppTextStyles.headlineMedium,
                        ),
                        content: Text(
                          'ngo_assist_description'.tr(),
                          style: AppTextStyles.bodyMedium,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('got_it'.tr()),
                          ),
                        ],
                      ),
                    );
                  },
                  isCompact: isCompact,
                ),

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLanguageOptions() {
    final languages = [
      {'code': 'en', 'name': 'English', 'native': 'English'},
      {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
      {'code': 'ta', 'name': 'Tamil', 'native': 'தமிழ்'},
      {'code': 'bn', 'name': 'Bengali', 'native': 'বাংলা'},
    ];

    return languages.map((lang) {
      return ListTile(
        title: Text(lang['name']!, style: AppTextStyles.bodyMedium),
        subtitle: Text(lang['native']!, style: AppTextStyles.bodySmall),
        trailing: const Icon(Icons.check, color: AppColors.terracotta),
        onTap: () => Navigator.pop(context),
      );
    }).toList();
  }
}
