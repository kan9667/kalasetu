import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/widgets/cycling_guidance_cue.dart';

void main() {
  group('CyclingGuidanceCue Tests', () {
    const cues = [
      GuidanceCue(
        text: 'First Tip',
        icon: Icons.lightbulb,
        insertText: 'Tip 1: ',
      ),
      GuidanceCue(
        text: 'Second Tip',
        icon: Icons.camera_alt,
        insertText: 'Tip 2: ',
      ),
      GuidanceCue(
        text: 'Third Tip',
        icon: Icons.wb_sunny,
        insertText: 'Tip 3: ',
      ),
    ];

    testWidgets('renders first cue initially with header and affordances', (tester) async {
      GuidanceCue? tappedCue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyclingGuidanceCue(
              headerTitle: 'TEST TIPS',
              headerIcon: Icons.tips_and_updates,
              cues: cues,
              onCueTap: (cue) => tappedCue = cue,
            ),
          ),
        ),
      );

      // Verify header and affordances
      expect(find.text('TEST TIPS'), findsOneWidget);
      expect(find.text('tap_to_hear'), findsOneWidget);
      expect(find.text('First Tip'), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb), findsOneWidget);

      // Tap the cue to verify onCueTap callback
      await tester.tap(find.text('First Tip'));
      await tester.pump();
      expect(tappedCue?.text, 'First Tip');
      expect(tappedCue?.insertText, 'Tip 1: ');
    });

    testWidgets('auto-advances cue after interval elapses', (tester) async {
      GuidanceCue? lastChangedCue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CyclingGuidanceCue(
              cues: cues,
              interval: const Duration(milliseconds: 1000),
              onCueChanged: (cue) => lastChangedCue = cue,
            ),
          ),
        ),
      );

      expect(find.text('First Tip'), findsOneWidget);

      // Advance by 1 second (interval) + animation duration
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Second Tip'), findsOneWidget);
      expect(lastChangedCue?.text, 'Second Tip');

      // Advance again to reach Third Tip
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Third Tip'), findsOneWidget);
      expect(lastChangedCue?.text, 'Third Tip');

      // Advance again to wrap around to First Tip
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('First Tip'), findsOneWidget);
    });

    testWidgets('manual chevron navigation works back and forth', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyclingGuidanceCue(
              cues: cues,
              isPaused: true, // pause timer so only manual triggers advance
            ),
          ),
        ),
      );

      expect(find.text('First Tip'), findsOneWidget);

      // Tap next chevron
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Second Tip'), findsOneWidget);

      // Tap next chevron again
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Third Tip'), findsOneWidget);

      // Tap previous chevron
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Second Tip'), findsOneWidget);
    });

    testWidgets('pausing halts auto-advance', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CyclingGuidanceCue(
              cues: cues,
              interval: Duration(milliseconds: 500),
              isPaused: true,
            ),
          ),
        ),
      );

      expect(find.text('First Tip'), findsOneWidget);

      // Advance clock by several intervals
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Should still be on First Tip
      expect(find.text('First Tip'), findsOneWidget);
    });
  });
}
