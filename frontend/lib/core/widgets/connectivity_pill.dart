import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../data/models/product.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ConnectivityPill extends ConsumerWidget {
  const ConnectivityPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityAsync = ref.watch(connectivityProvider);
    final isOnline = connectivityAsync.value ?? true;

    final productsAsync = ref.watch(productListProvider);
    final isSyncing = productsAsync.maybeWhen(
      data: (list) => list.any((p) => p.status == ProductStatus.pendingSync),
      orElse: () => false,
    );

    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String label;

    if (!isOnline) {
      bgColor = AppColors.error.withOpacity(0.15);
      textColor = AppColors.error;
      icon = Icons.wifi_off_rounded;
      label = 'offline'.tr();
    } else if (isSyncing) {
      bgColor = AppColors.warning.withOpacity(0.15);
      textColor = AppColors.warning;
      icon = Icons.sync_rounded;
      label = 'syncing'.tr();
    } else {
      bgColor = AppColors.success.withOpacity(0.15);
      textColor = AppColors.success;
      icon = Icons.wifi_rounded;
      label = 'online'.tr();
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}