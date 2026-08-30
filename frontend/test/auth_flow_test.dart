import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/auth/screens/sign_in_screen.dart';
import 'package:kalasetu/features/auth/screens/register_screen.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';
import 'package:kalasetu/data/models/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_auth_test');
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

  testWidgets('Sign-in screen renders phone entry, register option, and action buttons', (WidgetTester tester) async {
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

    // Verify multiple action buttons exist (Continue, Register, NGO assist)
    expect(find.byType(ElevatedButton), findsWidgets);
    expect(find.byType(OutlinedButton), findsWidgets);
  });

  testWidgets('Register screen renders all required artisan profile fields', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RegisterScreen(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));

    // Verify presence of form text fields (Name, Phone, Location, Experience, Pehchan ID)
    expect(find.byType(TextFormField), findsNWidgets(5));
    // Verify presence of DropdownFormField (Craft Type, State)
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));

    // Enter artisan name and details
    final textFields = find.byType(TextFormField);
    await tester.enterText(textFields.at(0), 'Shanti Devi'); // Name
    await tester.enterText(textFields.at(1), '9876543210'); // Phone
    await tester.enterText(textFields.at(2), 'Madhubani Art Cluster'); // Cluster
    await tester.enterText(textFields.at(3), '12'); // Experience
    await tester.enterText(textFields.at(4), 'PEH1234567890'); // Pehchan ID
    await tester.pump();

    // Verify Register Button is rendered
    expect(find.byType(ElevatedButton), findsWidgets);
  });

  test('AuthNotifier saves registered profile on OTP verification', () async {
    final container = ProviderContainer();
    final authNotifier = container.read(authStateProvider.notifier);

    final newArtisan = UserProfile(
      id: '',
      name: 'Ravi Verma',
      phone: '9876501234',
      craftType: 'Woodwork & Carving',
      locationCluster: 'Saharanpur Woodcraft Hub',
      state: 'Uttar Pradesh',
      experienceYears: '15',
      pehchanId: 'UP1234567',
      preferredLanguage: 'hi',
    );

    await authNotifier.registerWithDetails(newArtisan);
    expect(container.read(authStateProvider).pendingRegistration, isNotNull);
    expect(container.read(authStateProvider).phoneNumber, '9876501234');

    // Verify OTP
    final verified = await authNotifier.verifyOtp('9876501234', '123456');
    expect(verified, isTrue);
    expect(container.read(authStateProvider).isAuthenticated, isTrue);
    expect(container.read(authStateProvider).pendingRegistration, isNull);

    // Verify persisted to user_profile_box
    final box = Hive.box<UserProfile>('user_profile_box');
    final savedProfile = box.get('current_profile');
    expect(savedProfile, isNotNull);
    expect(savedProfile?.name, 'Ravi Verma');
    expect(savedProfile?.craftType, 'Woodwork & Carving');
    expect(savedProfile?.locationCluster, 'Saharanpur Woodcraft Hub');
  });
}
