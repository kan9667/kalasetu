import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/catalogue/screens/catalogue_screen.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _FakeProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  _FakeProductListNotifier(List<Product> products) : super(AsyncValue.data(products));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_catalogue_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }

    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  testWidgets('Catalogue screen renders search bar, correct spacing, and NO fair wage banner', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(MockApiService()),
        ],
        child: const MaterialApp(
          home: CatalogueScreen(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 4));

    // Verify search bar and search icon exist
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Verify the fair-wage banner card is deleted entirely
    expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);
    expect(find.text('fair_wage_trust_badge'), findsNothing);

    // Verify 10dp spacing exists between search bar and category chips
    final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
    expect(sizedBoxes.any((sb) => sb.height == 10), isTrue);
  });

  testWidgets('Grid product card renders Hindi title when locale is Hindi and English otherwise', (WidgetTester tester) async {
    final testProduct = Product(
      id: 'test_prod_1',
      title: 'Handcrafted Terracotta Vase',
      titleHi: 'हस्तनिर्मित टेराकोटा फूलदान',
      description: 'Beautiful vase',
      descriptionHi: 'सुंदर फूलदान',
      price: 450.0,
      photoPath: '',
      category: 'Pottery',
      status: ProductStatus.live,
    );

    // Render with Hindi locale
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productListProvider.overrideWith((ref) => _FakeProductListNotifier([testProduct])),
        ],
        child: const MaterialApp(
          locale: Locale('hi'),
          supportedLocales: [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: CatalogueScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Should display Hindi title
    expect(find.text('हस्तनिर्मित टेराकोटा फूलदान'), findsOneWidget);

    // Render with English locale
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productListProvider.overrideWith((ref) => _FakeProductListNotifier([testProduct])),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: CatalogueScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Should display English title
    expect(find.text('Handcrafted Terracotta Vase'), findsOneWidget);
  });
}
