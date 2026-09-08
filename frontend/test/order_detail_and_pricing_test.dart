import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalasetu/features/orders/models/order.dart';
import 'package:kalasetu/features/orders/screens/order_detail_screen.dart';
import 'package:kalasetu/features/orders/widgets/packaging_suggestions_sheet.dart';
import 'package:kalasetu/features/add_product/widgets/step4_pricing_widget.dart';
import 'package:kalasetu/core/providers/app_providers.dart';

void main() {
  final testOrder = Order(
    id: 'ORD-TEST-1234',
    productTitle: 'Handcrafted Terracotta Pot',
    productCategory: 'Pottery & Ceramic',
    productImagePath: 'assets/images/placeholder.jpg',
    buyerName: 'Ananya Sharma',
    buyerLocation: 'Varanasi, Uttar Pradesh',
    amount: 1250,
    quantity: 2,
    status: OrderStatus.newOrder,
    placedAt: DateTime(2026, 9, 8, 14, 30),
  );

  group('Order Detail Screen & Packaging Guide Localization Tests', () {
    testWidgets('OrderDetailScreen renders localized Product, Quantity, and Amount keys', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('hi'),
            supportedLocales: const [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: OrderDetailScreen(order: testOrder),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify product section label key and rows
      expect(find.text('उत्पाद'), findsOneWidget); // uppercase label in _SectionCard
      expect(find.text('मात्रा'), findsOneWidget);
      expect(find.text('राशि'), findsOneWidget);
      expect(find.text('₹1250'), findsOneWidget);
      expect(find.text('Handcrafted Terracotta Pot'), findsOneWidget);
      // Category is localized using filter_pottery in Hindi
      expect(find.text('मिट्टी के बर्तन'), findsOneWidget);
    });

    testWidgets('PackagingSuggestionsSheet displays localized category subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('hi'),
          supportedLocales: const [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: PackagingSuggestionsSheet(category: 'Pottery & Ceramic'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('packaging_suggestions_title'), findsOneWidget);
      expect(find.text('filter_pottery'), findsOneWidget);
    });
  });

  group('Fair Pricing Assistant (Step 4) Typography Tests', () {
    testWidgets('Cost breakdown and market benchmarks use body sans-serif while AI reasoning keeps Fraunces serif', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => AddProductFlowNotifier(ref)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Step4PricingWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. AI Reasoning header should use Fraunces (serif display/headline font)
      final reasoningFinder = find.text('ai_reasoning');
      expect(reasoningFinder, findsOneWidget);
      final Text reasoningWidget = tester.widget(reasoningFinder);
      expect(reasoningWidget.style?.fontFamily, equals('Fraunces'));
      expect(reasoningWidget.style?.fontWeight, equals(FontWeight.w600));

      // 2. Cost Breakdown header should use Manrope (sans-serif body font) with bodyMedium
      final costFloorFinder = find.text('cost_breakdown_floor_title');
      expect(costFloorFinder, findsOneWidget);
      final Text costFloorWidget = tester.widget(costFloorFinder);
      expect(costFloorWidget.style?.fontFamily, equals('Manrope'));
      expect(costFloorWidget.style?.fontWeight, equals(FontWeight.w600));
      expect(costFloorWidget.style?.fontSize, equals(15)); // bodyMedium size

      // 3. Market Benchmarks header should use Manrope (sans-serif body font) with bodyMedium
      final benchmarksFinder = find.text('market_benchmarks_title');
      expect(benchmarksFinder, findsOneWidget);
      final Text benchmarksWidget = tester.widget(benchmarksFinder);
      expect(benchmarksWidget.style?.fontFamily, equals('Manrope'));
      expect(benchmarksWidget.style?.fontWeight, equals(FontWeight.w600));
      expect(benchmarksWidget.style?.fontSize, equals(15)); // bodyMedium size
    });
  });
}
