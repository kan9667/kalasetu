import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/services/app_sound_service.dart';
import 'package:kalasetu/core/widgets/app_button.dart';
import 'package:kalasetu/core/widgets/app_icon_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSoundService & AppSoundFeedback Tests', () {
    test('Service initializes with sensible defaults and volume clamping', () async {
      final service = AppSoundService.instance;
      expect(service.isSoundEnabled, isTrue);
      expect(service.isHapticsEnabled, isTrue);
      expect(service.volume, 0.35);

      await service.setVolume(1.5);
      expect(service.volume, 1.0);

      await service.setVolume(-0.2);
      expect(service.volume, 0.0);

      await service.setVolume(0.35);
      expect(service.volume, 0.35);

      await service.setSoundEnabled(false);
      expect(service.isSoundEnabled, isFalse);

      await service.setSoundEnabled(true);
      expect(service.isSoundEnabled, isTrue);

      await service.setHapticsEnabled(false);
      expect(service.isHapticsEnabled, isFalse);

      await service.setHapticsEnabled(true);
      expect(service.isHapticsEnabled, isTrue);
    });

    test('AppSoundFeedback.wrap executes the underlying callback', () {
      bool called = false;
      final wrapped = AppSoundFeedback.wrap(() {
        called = true;
      });

      expect(wrapped, isNotNull);
      wrapped!();
      expect(called, isTrue);
    });

    test('AppSoundFeedback.wrap returns null when onPressed is null', () {
      final wrapped = AppSoundFeedback.wrap(null);
      expect(wrapped, isNull);
    });

    test('AppSoundFeedback.wrapValueChanged executes with value', () {
      int capturedValue = 0;
      final wrapped = AppSoundFeedback.wrapValueChanged<int>((val) {
        capturedValue = val;
      });

      expect(wrapped, isNotNull);
      wrapped!(42);
      expect(capturedValue, equals(42));
    });

    testWidgets('AppButton executes onPressed when tapped', (tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Click Me',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Click Me'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('AppIconButton executes onPressed when tapped', (tester) async {
      bool iconPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppIconButton(
              icon: const Icon(Icons.star),
              onPressed: () {
                iconPressed = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.star));
      await tester.pump();

      expect(iconPressed, isTrue);
    });
  });
}
