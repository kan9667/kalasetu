import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/app_route_constants.dart';
import '../theme/app_colors.dart';
import 'app_header.dart';
import 'app_background_pattern.dart';

/// Shared scaffold for main screens.
///
/// Pass [title] and optional [actions] to build a consistent [AppHeader]
/// with a notification bell + connectivity pill.
///
/// Set [showNotificationBell] = false on auth screens or nested detail
/// screens that should not show the bell.
///
/// Set [rawAppBar] as an escape hatch when a fully custom AppBar is needed.
///
/// Displays [AppBackgroundPattern] behind the screen body by default.
class AppScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? rawAppBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool showConnectivityPill;
  final bool showNotificationBell;
  final bool showBackgroundPattern;
  final double backgroundPatternOpacity;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const AppScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.rawAppBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.showConnectivityPill = true,
    this.showNotificationBell = true,
    this.showBackgroundPattern = true,
    this.backgroundPatternOpacity = 0.06,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    PreferredSizeWidget? builtAppBar;

    if (rawAppBar != null) {
      builtAppBar = rawAppBar;
    } else if (title != null || titleWidget != null) {
      final titleStr = title ?? '';
      builtAppBar = AppHeader(
        title: titleStr,
        extraActions: actions,
        showNotificationBell: showNotificationBell,
        showConnectivityPill: showConnectivityPill,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        onBellTap: () => context.pushNamed(AppRouteConstants.notifications),
      );
    }

    Widget bodyContent = SafeArea(
      child: padding != null ? Padding(padding: padding!, child: body) : body,
    );

    if (showBackgroundPattern) {
      bodyContent = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AppBackgroundPattern(
              opacity: backgroundPatternOpacity,
            ),
          ),
          bodyContent,
        ],
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      appBar: builtAppBar,
      body: bodyContent,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
