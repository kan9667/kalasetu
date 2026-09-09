import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';
import 'package:kalasetu/features/orders/screens/my_orders_screen.dart';
import 'package:kalasetu/features/catalogue/screens/catalogue_screen.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/api_service.dart';

class _FakeAddProductNotifier extends StateNotifier<AddProductDraft>
    implements AddProductFlowNotifier {
  _FakeAddProductNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  _FakeProductListNotifier(List<Product> products) : super(AsyncValue.data(products));

  @override
  Future<Product> addProduct(Product p) async {
    state = AsyncValue.data([...state.value ?? [], p]);
    return p;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_modal_analytics_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }

    if (!Hive.isBoxOpen('draft_box')) {
      await Hive.openBox('draft_box');
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  group('Product Listed Successfully Modal Overflow Tests', () {
    for (final scenario in [
      {'name': '4-digit rupee profit (+₹3500)', 'final': 5500.0, 'floor': 2000.0, 'expected': '+₹3500'},
      {'name': '5-digit rupee profit (+₹35000)', 'final': 45000.0, 'floor': 10000.0, 'expected': '+₹35000'},
      {'name': '6-digit rupee profit (+₹350000)', 'final': 400000.0, 'floor': 50000.0, 'expected': '+₹350000'},
      {'name': '7-digit rupee profit (+₹1500000)', 'final': 1700000.0, 'floor': 200000.0, 'expected': '+₹1500000'},
    ]) {
      testWidgets('Modal does not overflow with ${scenario['name']} on narrow screen (320px)', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final testDraft = AddProductDraft(
          titleEn: 'Exquisite Heritage Artifact',
          titleHi: 'उत्कृष्ट विरासत कलाकृति',
          category: 'Woodwork',
          finalPrice: scenario['final'] as double,
          floorPrice: scenario['floor'] as double,
          originalImagePath: 'test_path.jpg',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              addProductFlowProvider.overrideWith((ref) => _FakeAddProductNotifier(testDraft)),
              productListProvider.overrideWith((ref) => _FakeProductListNotifier([])),
              connectivityProvider.overrideWith((ref) => Stream.value(true)),
            ],
            child: const MaterialApp(
              locale: Locale('en'),
              supportedLocales: [Locale('en'), Locale('hi')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(body: Step5ConfirmWidget()),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap the list product button to show the modal
        final listBtn = find.text('list_product_btn');
        expect(listBtn, findsOneWidget);
        await tester.ensureVisible(listBtn);
        await tester.tap(listBtn);
        await tester.pumpAndSettle();

        // Modal should be open
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(scenario['expected'] as String), findsOneWidget);
        expect(find.text('profit_earned_label'), findsOneWidget);

        final profitFinder = find.text(scenario['expected'] as String);
        final dialogFinder = find.byType(AlertDialog);
        final dialogRenderBox = tester.renderObject(dialogFinder) as RenderBox;
        final dialogSize = dialogRenderBox.size;
        final dialogPosition = dialogRenderBox.localToGlobal(Offset.zero);

        final fittedBoxFinder = find.ancestor(of: profitFinder, matching: find.byType(FittedBox));
        final fittedBoxRenderBox = tester.renderObject(fittedBoxFinder) as RenderBox;
        final fittedBoxSize = fittedBoxRenderBox.size;
        final fittedBoxPosition = fittedBoxRenderBox.localToGlobal(Offset.zero);

        // Right edge of FittedBox must not exceed right edge of dialog
        expect(fittedBoxPosition.dx + fittedBoxSize.width, lessThanOrEqualTo(dialogPosition.dx + dialogSize.width));

        // Verify no RenderFlex overflow exception occurred
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Modal does not overflow in Hindi locale with 6-digit profit', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testDraft = AddProductDraft(
        titleEn: 'Exquisite Heritage Artifact',
        titleHi: 'उत्कृष्ट विरासत कलाकृति',
        category: 'Woodwork',
        finalPrice: 500000.0,
        floorPrice: 50000.0,
        originalImagePath: 'test_path.jpg',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => _FakeAddProductNotifier(testDraft)),
            productListProvider.overrideWith((ref) => _FakeProductListNotifier([])),
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(
            locale: Locale('hi'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step5ConfirmWidget()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listBtn = find.text('list_product_btn');
      expect(listBtn, findsOneWidget);
      await tester.ensureVisible(listBtn);
      await tester.tap(listBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('+₹450000'), findsOneWidget);

      final profitFinder = find.text('+₹450000');
      final fittedBoxFinder = find.ancestor(of: profitFinder, matching: find.byType(FittedBox));
      final fittedBoxRenderBox = tester.renderObject(fittedBoxFinder) as RenderBox;
      final dialogFinder = find.byType(AlertDialog);
      final dialogRenderBox = tester.renderObject(dialogFinder) as RenderBox;

      expect(
        fittedBoxRenderBox.localToGlobal(Offset.zero).dx + fittedBoxRenderBox.size.width,
        lessThanOrEqualTo(dialogRenderBox.localToGlobal(Offset.zero).dx + dialogRenderBox.size.width),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Analytics Trending-Up Icon in Headers', () {
    testWidgets('My Orders screen header displays trending_up icon and not analytics_outlined', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MyOrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Icons.trending_up exists in header
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      // Verify old Icons.analytics_outlined is gone
      expect(find.byIcon(Icons.analytics_outlined), findsNothing);

      // Verify tooltip
      final iconButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.trending_up));
      expect(iconButton.tooltip, 'artisan_analytics_tooltip');
    });

    testWidgets('Catalogue screen header displays trending_up icon', (WidgetTester tester) async {
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

      // Verify Icons.trending_up exists in header
      expect(find.byIcon(Icons.trending_up), findsOneWidget);
      // Verify search icon also exists
      expect(find.byIcon(Icons.search), findsOneWidget);

      // Verify tooltip matches My Orders screen
      final iconButton = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.trending_up));
      expect(iconButton.tooltip, 'artisan_analytics_tooltip');
    });
  });
}
