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

    // ASSUMPTION: I haven't seen auth_provider.dart, so this assumes
    // AuthController exposes a signInWithCoordinator method. Adjust the
    // method name/signature to match your real implementation.
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
      rawAppBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            const Icon(Icons.support_agent, size: 56, color: AppColors.terracotta),
            const SizedBox(height: AppSpacing.md),
            Text(
              'ngo_assist_title'.tr(),
              style: AppTextStyles.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'ngo_assist_description'.tr(),
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // QR placeholder — a real implementation would show a scannable
            // code for the coordinator's device to read and link accounts.
            Container(
              height: 220,
              width: 220,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.oak, width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_2, size: 96, color: AppColors.charcoalSoft),
                  const SizedBox(height: AppSpacing.sm),
                  Text('qr_placeholder_label'.tr(), style: AppTextStyles.caption, textAlign: TextAlign.center),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'or_enter_coordinator_id'.tr(),
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            Form(
              key: _formKey,
              child: TextFormField(
                controller: _coordinatorIdController,
                decoration: InputDecoration(
                  labelText: 'coordinator_id_label'.tr(),
                  hintText: 'coordinator_id_hint'.tr(),
                  prefixIcon: const Icon(Icons.badge_outlined),
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

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}