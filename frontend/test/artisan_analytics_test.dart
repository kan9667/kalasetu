import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/profile/screens/my_stats_screen.dart';
import 'package:kalasetu/features/auth/screens/register_screen.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/models/product.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_analytics_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  group('Artisan Performance & Revenue Analytics Screen Tests', () {
    testWidgets('Renders all hero metrics, period selector tabs, and sales trend', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(
            home: MyStatsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Check title / header
      expect(find.text('my_stats_title'), findsOneWidget);

      // Check period tabs (This Month / Last 3 Months / All Time)
      expect(find.text('period_this_month'), findsOneWidget);
      expect(find.text('period_last_3_months'), findsOneWidget);
      expect(find.text('period_all_time'), findsOneWidget);

      // Check hero card labels
      expect(find.text('total_sales_revenue'), findsOneWidget);
      expect(find.text('fair_wage_premium_title'), findsOneWidget);
      expect(find.text('sales_trend_title'), findsOneWidget);
      expect(find.text('order_fulfillment_title'), findsOneWidget);
      expect(find.text('popular_crafts_title'), findsOneWidget);

      // Verify period switching works cleanly
      await tester.tap(find.text('period_all_time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Popular Crafts sort toggle works
      expect(find.text('sort_by_views'), findsOneWidget);
      expect(find.text('sort_by_sales'), findsOneWidget);
      await tester.tap(find.text('sort_by_views'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('Register Screen Help Cue Card Tests', () {
    testWidgets('Renders Ask for Help cue card with support icon and localized text', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: RegisterScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // Check presence of support_agent icon
      expect(find.byIcon(Icons.support_agent), findsOneWidget);

      // Check presence of title and body keys
      expect(find.text('registration_help_cue_title'), findsOneWidget);
      expect(find.text('registration_help_cue_body'), findsOneWidget);
    });
  });
}
