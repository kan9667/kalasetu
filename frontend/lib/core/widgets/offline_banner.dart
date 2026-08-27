import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';
import '../providers/app_providers.dart';

final offlineBannerDismissedProvider = StateProvider<bool>((ref) => false);

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityProvider);
    final isDismissed = ref.watch(offlineBannerDismissedProvider);

    final isOnline = connectivityAsync.value ?? true;

    // Reset dismissal whenever connection state toggles
    if (isOnline) {
      return const SizedBox.shrink();
    }

    if (isDismissed) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.indigoDark,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off,
            color: AppColors.turmericLight,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'offline_banner_msg'.tr(),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textOnPrimary,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.surfaceVariant, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              ref.read(offlineBannerDismissedProvider.notifier).state = true;
            },
          ),
        ],
      ),
    );
  }
}
