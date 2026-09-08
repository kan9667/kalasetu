import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/auth/screens/register_screen.dart';
import 'package:kalasetu/data/models/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_register_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isBoxOpen('auth_box')) {
      await Hive.openBox('auth_box');
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
  });

  test('English and Hindi localization files contain all new bank and pehchan keys', () {
    final enFile = File('assets/translations/en.json');
    final hiFile = File('assets/translations/hi.json');

    expect(enFile.existsSync(), isTrue);
    expect(hiFile.existsSync(), isTrue);

    final enMap = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    final hiMap = jsonDecode(hiFile.readAsStringSync()) as Map<String, dynamic>;

    final requiredKeys = [
      'bank_details_title',
      'bank_details_subtitle',
      'bank_details_desc',
      'bank_account_holder_label',
      'bank_account_holder_hint',
      'bank_account_number_label',
      'bank_account_number_hint',
      'bank_ifsc_label',
      'bank_ifsc_hint',
      'bank_name_label',
      'bank_name_hint',
      'pehchan_photo_label',
      'pehchan_photo_desc',
      'pehchan_photo_attached',
      'remove_photo',
      'change_photo',
    ];

    for (final key in requiredKeys) {
      expect(enMap.containsKey(key), isTrue, reason: 'Missing $key in en.json');
      expect(hiMap.containsKey(key), isTrue, reason: 'Missing $key in hi.json');
      expect((enMap[key] as String).isNotEmpty, isTrue);
      expect((hiMap[key] as String).isNotEmpty, isTrue);
    }
  });

  testWidgets('Register screen renders Pehchan Card photo options and Bank Details section', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RegisterScreen(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));

    // Verify 9 text fields:
    // 1: Name, 2: Phone, 3: Cluster, 4: Experience, 5: Pehchan ID
    // 6: Account Holder, 7: Account Number, 8: IFSC, 9: Bank Name
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(9));

    // Scroll to see Pehchan Card section and Bank Details
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    // Verify Camera and Gallery buttons are present for Pehchan card photo upload
    expect(find.byIcon(Icons.camera_alt), findsWidgets);
    expect(find.byIcon(Icons.photo_library), findsWidgets);

    // Verify Bank Details icons are present
    expect(find.byIcon(Icons.account_balance_outlined), findsWidgets);
    expect(find.byIcon(Icons.confirmation_number_outlined), findsOneWidget);

    // Enter Bank Details
    await tester.enterText(textFields.at(5), 'Ramesh Kumar');
    await tester.enterText(textFields.at(6), '987654321098');
    await tester.enterText(textFields.at(7), 'PUNB0123400');
    await tester.enterText(textFields.at(8), 'Punjab National Bank');
    await tester.pump();
  });
}
