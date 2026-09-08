import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../catalogue/screens/catalogue_screen.dart';
import '../../add_product/screens/add_product_flow_screen.dart';
import '../../orders/screens/my_orders_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../chatbot/widgets/kalamitra_fab.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 1); // Default: Catalogue

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  Future<void> _handleTabTap(int index, BuildContext context, WidgetRef ref) async {
    if (index == 0) {
      final draft = ref.read(addProductFlowProvider);
      if (draft.hasExistingDraft && !draft.resumePromptHandled) {
        final shouldResume = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text('resume_draft_title'.tr(context: context)),
            content: Text('resume_draft_msg'.tr(context: context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('start_fresh_btn'.tr(context: context)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('resume_btn'.tr(context: context)),
              ),
            ],
          ),
        );

        if (shouldResume == true) {
          ref.read(addProductFlowProvider.notifier).resumeExistingDraft();
        } else {
          ref.read(addProductFlowProvider.notifier).discardPreviousDraft();
        }
      }
    }

    ref.read(homeTabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _ = Localizations.maybeLocaleOf(context);
    final _ = ref.watch(userProfileProvider).preferredLanguage;
    final currentIndex = ref.watch(homeTabIndexProvider);

    const screens = [
      AddProductFlowScreen(),
      CatalogueScreen(),
      MyOrdersScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      // AnimatedSwitcher gives a gentle fade when switching tabs
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: IndexedStack(
          key: ValueKey<int>(currentIndex),
          index: currentIndex,
          children: screens,
        ),
      ),
      floatingActionButton: const KalaMitraFab(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          border: Border(
            top: BorderSide(color: AppColors.line, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.add_photo_alternate_outlined,
                    label: 'tab_add_product'.tr(context: context),
                    isActive: currentIndex == 0,
                    onTap: () => _handleTabTap(0, context, ref),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.grid_view_outlined,
                    label: 'tab_catalogue'.tr(context: context),
                    isActive: currentIndex == 1,
                    onTap: () => _handleTabTap(1, context, ref),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'tab_my_orders'.tr(context: context),
                    isActive: currentIndex == 2,
                    onTap: () => _handleTabTap(2, context, ref),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_outline,
                    label: 'tab_profile'.tr(context: context),
                    isActive: currentIndex == 3,
                    onTap: () => _handleTabTap(3, context, ref),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single bottom-nav tab item with tanka-stitch dashed underline when active.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.terracotta : AppColors.inkFaint;

    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontSize: 10.5,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 3),
              // Tanka-stitch dashed underline — active tab only
              if (isActive)
                SizedBox(
                  width: 14,
                  height: 2,
                  child: CustomPaint(painter: _DashedLinePainter(color: color)),
                )
              else
                const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws a dashed horizontal line — the "tanka stitch" motif for the active nav tab.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashWidth = 3.0;
    const dashGap = 2.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}