import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/profile/screens/profile_screen.dart';
import 'package:kalasetu/features/profile/screens/my_stats_screen.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/models/product.dart';

class _FakeUserProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  _FakeProductListNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_profile_test');
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

  group('Profile Screen Compact Header & Stat Cards Test', () {
    testWidgets('Renders compact horizontal header and 3 stat cards in a single row without overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(MockApiService()),
            productListProvider.overrideWith(
              (ref) => _FakeProductListNotifier(const AsyncValue.data([])),
            ),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Meera Devi',
                phone: '+91 98765 43210',
                craftType: 'Blue Pottery',
                locationCluster: 'Jaipur, Rajasthan',
                state: 'Rajasthan',
              ),
            )),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify compact avatar is rendered
      final avatarFinder = find.byType(CircleAvatar);
      expect(avatarFinder, findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(avatarFinder);
      expect(avatar.radius, 28);

      // Verify name, phone, craft type are displayed
      expect(find.text('Meera Devi'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('Blue Pottery'), findsOneWidget);

      // Verify all 3 stat cards exist
      expect(find.text('total_listings'), findsOneWidget);
      expect(find.text('pending_sync_count'), findsOneWidget);
      expect(find.text('estimated_earnings'), findsOneWidget);
    });
  });

  group('Analytics Screen Overflow & Responsiveness Tests', () {
    testWidgets('Renders MyStatsScreen on a narrow 320dp screen with zero overflows', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(MockApiService()),
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(
            home: MyStatsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify title and cards render
      expect(find.text('my_stats_title'), findsOneWidget);
      expect(find.text('fair_wage_premium_title'), findsOneWidget);
      expect(find.text('sales_trend_title'), findsOneWidget);
      expect(find.text('popular_crafts_title'), findsOneWidget);
    });
  });
}
