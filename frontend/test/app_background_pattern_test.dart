import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalasetu/core/widgets/app_background_pattern.dart';
import 'package:kalasetu/core/widgets/app_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackgroundPattern Tests', () {
    testWidgets('renders IgnorePointer with ignoring true and Image widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBackgroundPattern(opacity: 0.08),
          ),
        ),
      );

      final ignorePointerFinder = find.descendant(
        of: find.byType(AppBackgroundPattern),
        matching: find.byType(IgnorePointer),
      );
      expect(ignorePointerFinder, findsOneWidget);

      final ignorePointer = tester.widget<IgnorePointer>(ignorePointerFinder);
      expect(ignorePointer.ignoring, isTrue);

      final imageFinder = find.descendant(
        of: find.byType(AppBackgroundPattern),
        matching: find.byType(Image),
      );
      expect(imageFinder, findsOneWidget);

      final image = tester.widget<Image>(imageFinder);
      expect(image.colorBlendMode, BlendMode.modulate);
    });

    testWidgets('returns SizedBox.shrink when opacity is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBackgroundPattern(opacity: 0.0),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppBackgroundPattern),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    });

    testWidgets('AppScaffold renders AppBackgroundPattern in body stack by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AppScaffold(
              title: null,
              body: Text('Screen Content'),
            ),
          ),
        ),
      );

      expect(find.byType(AppBackgroundPattern), findsOneWidget);
      expect(find.text('Screen Content'), findsOneWidget);
    });

    testWidgets('AppScaffold suppresses AppBackgroundPattern when showBackgroundPattern is false', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AppScaffold(
              title: null,
              showBackgroundPattern: false,
              body: Text('Screen Content'),
            ),
          ),
        ),
      );

      expect(find.byType(AppBackgroundPattern), findsNothing);
      expect(find.text('Screen Content'), findsOneWidget);
    });
  });
}
