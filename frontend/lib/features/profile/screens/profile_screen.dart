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
import '../../../core/providers/app_providers.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final profile = ref.watch(userProfileProvider);
    final productsAsync = ref.watch(productListProvider);

    final totalCount = productsAsync.value?.length ?? 0;
    final pendingCount = ref.read(productRepositoryProvider).getPendingCount();

    return AppScaffold(
      appBar: AppBar(
        title: Text('profile_title'.tr()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          children: [
            // Avatar
            CircleAvatar(
              radius: 46,
              backgroundColor: AppColors.terracotta,
              child: const Icon(
                Icons.person,
                size: 52,
                color: AppColors.textOnPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              profile.name,
              style: AppTextStyles.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              profile.phone.isNotEmpty ? profile.phone : (authState.phoneNumber ?? 'No phone'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Chip(
              label: Text(profile.craftType),
              backgroundColor: AppColors.terracottaLight.withValues(alpha: 0.3),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Stats cards row
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'total_listings'.tr(),
                    value: '$totalCount',
                    icon: Icons.inventory_2,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    title: 'pending_sync_count'.tr(),
                    value: '$pendingCount',
                    icon: Icons.sync,
                    color: AppColors.turmericDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _StatCard(
              title: 'estimated_earnings'.tr(),
              value: '₹${(totalCount * 1850).toStringAsFixed(0)}',
              icon: Icons.currency_rupee,
              color: AppColors.forestGreen,
            ),

            const SizedBox(height: AppSpacing.xl),

            // Menu items
            _MenuTile(
              icon: Icons.language,
              title: 'language_settings_title'.tr(),
              subtitle: 'lang_${context.locale.languageCode}'.tr(),
              onTap: () => context.pushNamed(AppRouteConstants.languageSettings),
            ),
            _MenuTile(
              icon: Icons.bar_chart,
              title: 'my_stats_title'.tr(),
              onTap: () => context.pushNamed(AppRouteConstants.myStats),
            ),
            _MenuTile(
              icon: Icons.help_outline,
              title: 'help_support'.tr(),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'KalaSetu',
                  applicationVersion: '1.0.0',
                  applicationLegalese: 'about_desc'.tr(),
                );
              },
            ),
            _MenuTile(
              icon: Icons.info_outline,
              title: 'about_kalasetu'.tr(),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('about_kalasetu'.tr(), style: AppTextStyles.headlineMedium),
                    content: Text('about_desc'.tr(), style: AppTextStyles.bodyMedium),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('close'.tr()),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.xl),

            AppButton(
              label: 'sign_out'.tr(),
              type: AppButtonType.outlined,
              customColor: AppColors.error,
              icon: Icons.logout,
              onPressed: () async {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('sign_out_confirm_title'.tr(), style: AppTextStyles.headlineMedium),
                    content: Text('sign_out_confirm_msg'.tr(), style: AppTextStyles.bodyMedium),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('cancel'.tr()),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await ref.read(authStateProvider.notifier).signOut();
                          if (context.mounted) {
                            context.goNamed(AppRouteConstants.signIn);
                          }
                        },
                        child: Text('sign_out'.tr(), style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.terracotta;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: activeColor),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: AppTextStyles.headlineLarge.copyWith(color: activeColor)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.terracotta),
      title: Text(title, style: AppTextStyles.bodyMedium),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTextStyles.bodySmall)
          : null,
      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
    );
  }
}
