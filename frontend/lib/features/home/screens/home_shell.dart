import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../catalogue/screens/catalogue_screen.dart';
import '../../add_product/screens/add_product_flow_screen.dart';
import '../../profile/screens/profile_screen.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 1); // Default to Catalogue or 0

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(homeTabIndexProvider);

    final screens = const [
      AddProductFlowScreen(),
      CatalogueScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => ref.read(homeTabIndexProvider.notifier).state = index,
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.terracotta,
          unselectedItemColor: AppColors.textSecondary,
          items: [
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: currentIndex == 0
                    ? BoxDecoration(
                        color: AppColors.terracottaLight.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: const Icon(Icons.add_photo_alternate, size: 26),
              ),
              label: 'tab_add_product'.tr(),
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: currentIndex == 1
                    ? BoxDecoration(
                        color: AppColors.terracottaLight.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: const Icon(Icons.grid_view, size: 26),
              ),
              label: 'tab_catalogue'.tr(),
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: currentIndex == 2
                    ? BoxDecoration(
                        color: AppColors.terracottaLight.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: const Icon(Icons.person, size: 26),
              ),
              label: 'tab_profile'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
