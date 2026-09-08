import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kalasetu/features/add_product/widgets/step3_ai_review_widget.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';

class _FakeAddProductFlowNotifier extends StateNotifier<AddProductDraft>
    implements AddProductFlowNotifier {
  _FakeAddProductFlowNotifier(super.state);

  @override
  void updateListingDetails({
    String? titleEn,
    String? titleHi,
    String? descriptionEn,
    String? descriptionHi,
    String? category,
    List<String>? tags,
  }) {
    state = state.copyWith(
      titleEn: titleEn ?? state.titleEn,
      titleHi: titleHi ?? state.titleHi,
      descriptionEn: descriptionEn ?? state.descriptionEn,
      descriptionHi: descriptionHi ?? state.descriptionHi,
      category: category ?? state.category,
      tags: tags ?? state.tags,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('hive_add_product_bilingual_test');
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
  });

  group('Step 5 Review & Publish Bilingual Tests', () {
    const testDraft = AddProductDraft(
      titleEn: 'Blue Pottery Plate',
      titleHi: 'नीली मिट्टी की प्लेट',
      descriptionEn: 'Glazed handmade ceramic plate from Jaipur.',
      descriptionHi: 'जयपुर से हस्तनिर्मित चमकदार सिरेमिक प्लेट।',
      category: 'Pottery',
      finalPrice: 850.0,
      tags: ['ceramic', 'jaipur'],
    );

    testWidgets(
        'Step 5 renders Hindi title, secondary English title, and Hindi description when locale is Hindi',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider
                .overrideWith((ref) => _FakeAddProductFlowNotifier(testDraft)),
          ],
          child: const MaterialApp(
            locale: Locale('hi'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step5ConfirmWidget()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Hindi title is displayed as primary title
      expect(find.text('नीली मिट्टी की प्लेट'), findsOneWidget);
      // English title is displayed as secondary title
      expect(find.text('Blue Pottery Plate'), findsOneWidget);
      // Hindi description is displayed
      expect(find.text('जयपुर से हस्तनिर्मित चमकदार सिरेमिक प्लेट।'), findsOneWidget);
      // Category is left in English without attempt at translation
      expect(find.text('Pottery'), findsOneWidget);
    });

    testWidgets(
        'Step 5 renders English title, secondary Hindi title, and English description when locale is English',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider
                .overrideWith((ref) => _FakeAddProductFlowNotifier(testDraft)),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step5ConfirmWidget()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // English title is primary
      expect(find.text('Blue Pottery Plate'), findsOneWidget);
      // Hindi title is secondary
      expect(find.text('नीली मिट्टी की प्लेट'), findsOneWidget);
      // English description is displayed
      expect(find.text('Glazed handmade ceramic plate from Jaipur.'),
          findsOneWidget);
      // Category is in English
      expect(find.text('Pottery'), findsOneWidget);
    });

    testWidgets('Step 5 falls back to English when titleHi is empty in Hindi locale',
        (WidgetTester tester) async {
      const draftWithoutHi = AddProductDraft(
        titleEn: 'Blue Pottery Plate',
        titleHi: '',
        descriptionEn: 'Glazed handmade ceramic plate from Jaipur.',
        descriptionHi: '',
        category: 'Pottery',
        finalPrice: 850.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith(
                (ref) => _FakeAddProductFlowNotifier(draftWithoutHi)),
          ],
          child: const MaterialApp(
            locale: Locale('hi'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step5ConfirmWidget()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Falls back to English title
      expect(find.text('Blue Pottery Plate'), findsOneWidget);
      // Falls back to English description
      expect(find.text('Glazed handmade ceramic plate from Jaipur.'),
          findsOneWidget);
    });
  });

  group('Step 3 AI Listing Review Bilingual Tests', () {
    const testDraft = AddProductDraft(
      titleEn: 'Blue Pottery Plate',
      titleHi: 'नीली मिट्टी की प्लेट',
      descriptionEn: 'Glazed handmade ceramic plate from Jaipur.',
      descriptionHi: 'जयपुर से हस्तनिर्मित चमकदार सिरेमिक plate.',
      category: 'Pottery',
      tags: ['ceramic'],
    );

    testWidgets('Step 3 defaults to Hindi tab and populates Hindi content when locale is Hindi',
        (WidgetTester tester) async {
      final notifier = _FakeAddProductFlowNotifier(testDraft);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            locale: Locale('hi'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step3AiReviewWidget()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial state of text fields should be the Hindi content
      final titleField = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(titleField.controller?.text, 'नीली मिट्टी की प्लेट');

      final descField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(descField.controller?.text, 'जयपुर से हस्तनिर्मित चमकदार सिरेमिक plate.');

      // Tap the English tab to verify manual switching works
      await tester.tap(find.text('tab_english'));
      await tester.pump();

      expect(titleField.controller?.text, 'Blue Pottery Plate');
      expect(descField.controller?.text, 'Glazed handmade ceramic plate from Jaipur.');

      // Tap Hindi tab again to verify switching back to Hindi works
      await tester.tap(find.text('tab_hindi'));
      await tester.pump();

      expect(titleField.controller?.text, 'नीली मिट्टी की प्लेट');
      expect(descField.controller?.text, 'जयपुर से हस्तनिर्मित चमकदार सिरेमिक plate.');
    });

    testWidgets('Step 3 defaults to English tab and populates English content when locale is English',
        (WidgetTester tester) async {
      final notifier = _FakeAddProductFlowNotifier(testDraft);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: Step3AiReviewWidget()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initial state of text fields should be the English content
      final titleField = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(titleField.controller?.text, 'Blue Pottery Plate');

      final descField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(descField.controller?.text, 'Glazed handmade ceramic plate from Jaipur.');

      // Tap the Hindi tab to verify manual switching works
      await tester.tap(find.text('tab_hindi'));
      await tester.pump();

      expect(titleField.controller?.text, 'नीली मिट्टी की प्लेट');
      expect(descField.controller?.text, 'जयपुर से हस्तनिर्मित चमकदार सिरेमिक plate.');
    });
  });
}
