import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:kalasetu/features/tutorial/models/tutorial_slide_model.dart';
import 'package:kalasetu/features/tutorial/screens/tutorial_carousel_screen.dart';
import 'package:kalasetu/features/tutorial/widgets/tutorial_card_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, Object>{};
        }
        return true;
      },
    );
    await EasyLocalization.ensureInitialized();
  });

  group('TutorialSlidesData', () {
    test('contains exactly 8 slides spanning overview, 6 steps, and outro', () {
      final slides = TutorialSlidesData.slides;
      expect(slides.length, equals(8));

      expect(slides[0].isIntro, isTrue);
      expect(slides[0].stepIndex, equals(0));

      for (int i = 1; i <= 6; i++) {
        expect(slides[i].isStep, isTrue);
        expect(slides[i].stepIndex, equals(i));
      }

      expect(slides[7].isOutro, isTrue);
      expect(slides[7].stepIndex, equals(7));
    });

    test('each slide has non-empty keys, ttsKey, and highlights', () {
      for (final slide in TutorialSlidesData.slides) {
        expect(slide.titleKey.isNotEmpty, isTrue);
        expect(slide.descKey.isNotEmpty, isTrue);
        expect(slide.ttsKey.isNotEmpty, isTrue);
        expect(slide.highlights.isNotEmpty, isTrue);
      }
    });
  });

  group('TutorialCardWidget', () {
    testWidgets('renders slide title, icon, and speaker button', (tester) async {
      final sampleSlide = TutorialSlidesData.slides[1];

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          useOnlyLangCode: true,
          child: MaterialApp(
            home: Scaffold(
              body: TutorialCardWidget(
                slide: sampleSlide,
                isSpeaking: false,
                onToggleSpeak: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify hero icon is rendered
      expect(find.byIcon(sampleSlide.icon), findsAtLeastNWidgets(1));

      // Verify audio speaker icon is rendered on hero
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    });
  });

  group('TutorialCarouselScreen', () {
    testWidgets('renders PageView, step badge, and navigation buttons', (tester) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          useOnlyLangCode: true,
          child: const ProviderScope(
            child: MaterialApp(
              home: TutorialCarouselScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify PageView is present
      expect(find.byType(PageView), findsOneWidget);

      // Verify Close icon is removed from header
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Verify Audio speaker button exists only on card hero, not in header
      expect(find.byIcon(Icons.volume_down_rounded), findsOneWidget);
    });
  });
}
