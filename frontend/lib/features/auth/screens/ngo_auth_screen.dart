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

import '../../../core/widgets/language_picker.dart';

class NgoAuthScreen extends ConsumerStatefulWidget {
  const NgoAuthScreen({super.key});

  @override
  ConsumerState<NgoAuthScreen> createState() => _NgoAuthScreenState();
}

class _NgoAuthScreenState extends ConsumerState<NgoAuthScreen> {
  final _coordinatorIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _coordinatorIdController.dispose();
    super.dispose();
  }

  Future<void> _handleAssistedSignIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);
    final coordinatorId = _coordinatorIdController.text.trim();

    await ref.read(authStateProvider.notifier).signInWithCoordinator(coordinatorId);

    if (mounted) {
      setState(() => _isSubmitting = false);
      context.goNamed(AppRouteConstants.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenPadding = AppSpacing.getScreenPadding(context);

    return AppScaffold(
      showConnectivityPill: false,
      rawAppBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: LanguagePicker(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.terracottaLight,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.support_agent,
                    size: 36,
                    color: AppColors.terracottaDark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'ngo_assist_title'.tr(),
              style: AppTextStyles.headlineLarge.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ngo_assist_description'.tr(),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.inkSoft,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),

            // QR container
            Center(
              child: Container(
                height: 210,
                width: 210,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: AppColors.line, width: 1.5),
                  boxShadow: AppElevation.cardShadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.qr_code_2,
                      size: 110,
                      color: AppColors.ink,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text(
                        'qr_placeholder_label'.tr(),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Reassurance info callout card
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.goldLight,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.goldDark,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'ngo_assist_explanation'.tr(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'or_enter_coordinator_id'.tr(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.line)),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            Form(
              key: _formKey,
              child: TextFormField(
                controller: _coordinatorIdController,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  labelText: 'coordinator_id_label'.tr(),
                  hintText: 'coordinator_id_hint'.tr(),
                  labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkSoft),
                  hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.inkFaint),
                  prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.terracotta),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    borderSide: const BorderSide(color: AppColors.line, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    borderSide: const BorderSide(color: AppColors.line, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                    borderSide: const BorderSide(color: AppColors.terracotta, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'coordinator_id_required'.tr();
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            AppButton(
              label: 'start_assisted_signin_btn'.tr(),
              icon: Icons.how_to_reg,
              isLoading: _isSubmitting,
              onPressed: _handleAssistedSignIn,
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}