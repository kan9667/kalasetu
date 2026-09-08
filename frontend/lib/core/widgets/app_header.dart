import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'connectivity_pill.dart';

/// Reusable top-bar used across every main screen.
///
/// Renders:
///   [title text]  ——————————  [bell icon]  [connectivity pill]
///
/// The bell icon shows a badge with the number of unread notifications.
/// Tapping the bell calls [onBellTap] (typically navigates to Notifications).
class AppHeader extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBellTap;
  final List<Widget>? extraActions;
  final bool showNotificationBell;
  final bool showConnectivityPill;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const AppHeader({
    super.key,
    required this.title,
    this.onBellTap,
    this.extraActions,
    this.showNotificationBell = true,
    this.showConnectivityPill = true,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = showNotificationBell
        ? ref.watch(unreadNotificationCountProvider)
        : 0;

    return AppBar(
      title: Text(title),
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: [
        ...?extraActions,
        if (showNotificationBell)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Notifications',
                  onPressed: onBellTap,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: const BoxDecoration(
                          color: AppColors.terracotta,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: AppColors.textOnPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (showConnectivityPill)
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: Center(child: ConnectivityPill()),
          ),
      ],
    );
  }
}
