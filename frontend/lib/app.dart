import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class KalaSetuApp extends ConsumerWidget {
  const KalaSetuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    List<LocalizationsDelegate<dynamic>>? delegates;
    List<Locale> supported = const [
      Locale('en'),
      Locale('hi'),
      Locale('ta'),
      Locale('bn'),
    ];
    Locale? currentLocale;

    try {
      delegates = context.localizationDelegates;
      supported = context.supportedLocales;
      currentLocale = context.locale;
    } catch (_) {}

    return MaterialApp.router(
      title: 'KalaSetu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: delegates,
      supportedLocales: supported,
      locale: currentLocale,
    );
  }
}
