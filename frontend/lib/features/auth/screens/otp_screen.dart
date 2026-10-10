import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/router/app_route_constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/providers/app_providers.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  final bool isNewUser;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    this.isNewUser = false,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startCooldown() {
    if (!mounted) return;
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  void _handleResend() async {
    if (_resendCooldown > 0) return;
    final notifier = ref.read(authStateProvider.notifier);
    final result = await notifier.resendOtp(widget.phoneNumber);
    if (!mounted) return;
    if (result is RequestOtpSuccess) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('call_initiated_msg'.tr())),
      );
    } else if (result is RequestOtpFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _handleOtpComplete() async {
    final otp = _controllers.map((c) => c.text).join().trim();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('enter_6_digits_hint'.tr()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final notifier = ref.read(authStateProvider.notifier);
    final success = await notifier.verifyOtp(
      widget.phoneNumber,
      otp,
    );

    if (!mounted) return;

    if (success) {
      await ref.read(userProfileProvider.notifier).reloadProfile();
      // Explicit reload — purges any foreign products and fetches the newly-logged-in
      // artisan's catalogue before the home screen renders.
      unawaited(
        ref.read(productListProvider.notifier).loadProducts(forceRefresh: true),
      );
      if (mounted) {
        context.goNamed(AppRouteConstants.home);
      }
    } else {
      final error = ref.read(authStateProvider).authError ?? 'Verification failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return AppScaffold(
      rawAppBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (widget.isNewUser) {
              context.goNamed(AppRouteConstants.register);
            } else {
              context.goNamed(AppRouteConstants.signIn);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(
              'verify_phone_title'.tr(),
              style: AppTextStyles.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${'verify_phone_subtitle'.tr()}\n+91 ${widget.phoneNumber}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),

            // Voice Call Guidance Banner
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.terracotta.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: AppColors.terracotta.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_in_talk,
                    color: AppColors.terracotta,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'listen_code_hint'.tr(),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.terracottaDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // OTP Input Boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 48,
                  height: 56,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: AppTextStyles.headlineLarge,
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      } else if (value.isEmpty && index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                      if (index == 5 && value.isNotEmpty) {
                        _handleOtpComplete();
                      }
                    },
                  ),
                );
              }),
            ),

            const SizedBox(height: AppSpacing.xl),

            AppButton(
              label: 'verify_btn'.tr(),
              icon: Icons.check_circle_outline,
              onPressed: _handleOtpComplete,
              isLoading: authState.isLoading,
            ),

            const SizedBox(height: AppSpacing.md),

            AppButton(
              label: _resendCooldown > 0
                  ? '${'resend_otp'.tr()} (${_resendCooldown}s)'
                  : 'resend_otp'.tr(),
              type: AppButtonType.text,
              icon: Icons.phone_callback,
              onPressed: _resendCooldown > 0 ? null : _handleResend,
            ),

            const SizedBox(height: AppSpacing.xxl),

            if (authState.demoOtp != null && authState.demoOtp!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.statusPendingBg,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: AppColors.goldLight),
                ),
                child: Text(
                  'Demo Mode: Your verification code is ${authState.demoOtp}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.goldDark,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
