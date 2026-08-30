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
import '../../../core/widgets/language_picker.dart';
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
      showConnectivityPill: false,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.terracotta.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'sign_in_subtitle'.tr(),
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              const Center(child: LanguagePicker()),

              const SizedBox(height: AppSpacing.xl),

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

              AppButton(
                label: 'continue_btn'.tr(),
                icon: Icons.login,
                onPressed: _handleContinue,
                isCompact: isCompact,
              ),

              const SizedBox(height: AppSpacing.lg),

              // Divider with 'OR'
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: Text(
                      'new_artisan_prompt'.tr(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.border)),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Register as New Artisan Button
              AppButton(
                label: 'new_artisan_register_btn'.tr(),
                type: AppButtonType.secondary,
                icon: Icons.person_add_alt_1,
                onPressed: () {
                  context.pushNamed(AppRouteConstants.register);
                },
                isCompact: isCompact,
              ),

              const SizedBox(height: AppSpacing.md),

              // NGO Coordinator Assist Button
              AppButton(
                label: 'ngo_assist_btn'.tr(),
                type: AppButtonType.outlined,
                icon: Icons.support_agent,
                onPressed: () {
                  context.pushNamed(AppRouteConstants.ngoAuth);
                },
                isCompact: isCompact,
              ),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}