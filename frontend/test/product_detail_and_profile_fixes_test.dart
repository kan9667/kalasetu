import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/catalogue/screens/product_detail_screen.dart';
import 'package:kalasetu/features/profile/screens/profile_screen.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';

class _FakeProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  _FakeProductListNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_fixes_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
  });

  group('Fix 1 & 2: Localization Keys Consistency & Overflow Menu', () {
    test('en.json and hi.json both contain all required listing and menu keys identically', () {
      final enFile = File('assets/translations/en.json');
      final hiFile = File('assets/translations/hi.json');

      final Map<String, dynamic> en = jsonDecode(enFile.readAsStringSync());
      final Map<String, dynamic> hi = jsonDecode(hiFile.readAsStringSync());

      final requiredKeys = [
        'mark_sold_out_btn',
        'remove_listing_btn',
        'relist_item_btn',
        'listing_info_btn',
        'delete',
        'listing_actions',
      ];

      for (final key in requiredKeys) {
        expect(en.containsKey(key), isTrue, reason: 'en.json missing $key');
        expect(hi.containsKey(key), isTrue, reason: 'hi.json missing $key');
        expect(en[key], isNotEmpty);
        expect(hi[key], isNotEmpty);
      }

      expect(en['mark_sold_out_btn'], 'Mark as Sold Out');
      expect(hi['mark_sold_out_btn'], 'बिक गया (स्टॉक समाप्त) चिह्नित करें');

      expect(en['remove_listing_btn'], 'Remove Listing from ONDC');
      expect(hi['remove_listing_btn'], 'ओएनडीसी से लिस्टिंग हटाएं');

      expect(en['listing_info_btn'], 'Remove vs Delete Info');
      expect(hi['listing_info_btn'], 'हटाने और मिटाने की जानकारी');

      expect(en['relist_item_btn'], 'Relist Item (Make Live)');
      expect(hi['relist_item_btn'], 'पुनः सूचीबद्ध करें (लाइव करें)');
    });

    testWidgets('ProductDetailScreen renders IntrinsicHeight and equal height pills', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleProduct = Product(
        id: 'prod-101',
        title: 'Terracotta Vase',
        description: 'Handcrafted clay vase',
        price: 850,
        photoPath: 'https://example.com/vase.jpg',
        category: 'Pottery',
        status: ProductStatus.live,
        statusUpdatedAt: DateTime(2026, 9, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(MockApiService()),
            productListProvider.overrideWith(
              (ref) => _FakeProductListNotifier(AsyncValue.data([sampleProduct])),
            ),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Ramesh Kumar',
                phone: '+91 99999 88888',
                craftType: 'Pottery',
                locationCluster: 'Khurja',
                state: 'Uttar Pradesh',
              ),
            )),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(productId: 'prod-101'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to reveal the listing actions card
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm IntrinsicHeight is used for the action buttons row
      expect(find.byType(IntrinsicHeight), findsAtLeastNWidgets(1));

      // Confirm FittedBox is used inside both buttons for text scaling
      expect(find.byType(FittedBox), findsAtLeastNWidgets(2));

      // Confirm OutlinedButton pills exist
      final buttons = find.byType(OutlinedButton);
      expect(buttons, findsNWidgets(2));

      final size0 = tester.getSize(buttons.at(0));
      final size1 = tester.getSize(buttons.at(1));

      // Both buttons must have identical uniform height
      expect(size0.height, equals(size1.height));
    });
  });

  group('Fix 3: Profile Screen Stat Tiles Removal', () {
    testWidgets('ProfileScreen has no stat cards and has compact spacing to menu', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(MockApiService()),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Ramesh Kumar',
                phone: '+91 99999 88888',
                craftType: 'Pottery',
                locationCluster: 'Khurja',
                state: 'Uttar Pradesh',
              ),
            )),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pump();

      // Ensure stat tiles are not found
      expect(find.text('total_listings'), findsNothing);
      expect(find.text('pending_sync_count'), findsNothing);
      expect(find.text('estimated_earnings'), findsNothing);
      expect(find.byIcon(Icons.inventory_2), findsNothing);
      expect(find.byIcon(Icons.currency_rupee), findsNothing);

      // Verify the language menu tile exists
      expect(find.byIcon(Icons.language), findsOneWidget);
    });
  });
}
