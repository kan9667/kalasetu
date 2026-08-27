import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/auth/screens/sign_in_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_auth_test');
    Hive.init(tempDir.path);
    if (!Hive.isBoxOpen('auth_box')) {
      await Hive.openBox('auth_box');
    }
  });

  testWidgets('Sign-in happy path renders phone entry field and buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SignInScreen(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));

    // Verify phone input field is present
    final phoneField = find.byType(TextField);
    expect(phoneField, findsOneWidget);

    // Enter phone number
    await tester.enterText(phoneField, '9876543210');
    await tester.pump(const Duration(milliseconds: 500));

    // Verify continue button is visible
    expect(find.byType(ElevatedButton), findsWidgets);
  });
}
