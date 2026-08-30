import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'connectivity_pill.dart';

/// Shared scaffold for main screens. Builds the AppBar itself (from [title]
/// + [actions] + [leading]) so the connectivity pill is always injected
/// consistently — screens should stop constructing their own AppBar and use
/// these params instead. [rawAppBar] remains as an escape hatch for a screen
/// that truly needs a custom AppBar; in that case, add ConnectivityPill into
/// its actions yourself.
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
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final builtAppBar = rawAppBar ??
        ((title != null || titleWidget != null)
            ? AppBar(
                title: titleWidget ?? Text(title!),
                leading: leading,
                automaticallyImplyLeading: automaticallyImplyLeading,
                actions: [
                  ...?actions,
                  if (showConnectivityPill)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Center(child: ConnectivityPill()),
                    ),
                ],
              )
            : null);

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      appBar: builtAppBar,
      body: SafeArea(
        child: padding != null ? Padding(padding: padding!, child: body) : body,
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}