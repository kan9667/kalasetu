import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/widgets/app_button.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('exact_media_review_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());
    await Hive.openBox<Product>('products_box');
    await Hive.openBox<String>('pending_sync_box');
    await Hive.openBox('draft_box');
    await Hive.openBox<UserProfile>('user_profile_box');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('Photo A -> retake B invalidates mediaId, and mismatched generation blocks Step 5 publishing', (tester) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(MockApiService()),
        ],
      );

      final flow = container.read(addProductFlowProvider.notifier);

      // Initial draft with Photo A enhanced
      flow.loadSavedDraftState(
        draftId: 'draft_exact_001',
        originalImagePath: '${tempDir.path}/photo_A.jpg',
        enhancedImagePath: 'https://test/enhanced_A.jpg',
        transcript: 'Blue clay pot',
        category: 'Pottery',
        mediaId: 'med_asset_A',
        originalMediaId: 'med_asset_raw_A',
        imageInputGeneration: 0,
        boundMediaGeneration: 0,
      );

      expect(container.read(addProductFlowProvider).mediaId, equals('med_asset_A'));
      expect(container.read(addProductFlowProvider).imageInputGeneration, equals(0));
      expect(container.read(addProductFlowProvider).boundMediaGeneration, equals(0));

      // Retake Photo B
      final photoB = File('${tempDir.path}/photo_B.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
      await flow.setImage(photoB.path);

      final draftAfterRetake = container.read(addProductFlowProvider);
      expect(draftAfterRetake.mediaId, isNull, reason: 'Retaking photo must invalidate old mediaId');
      expect(draftAfterRetake.imageEnhanceOpId, isNull);
      expect(draftAfterRetake.imageInputGeneration, equals(1));
      expect(draftAfterRetake.boundMediaGeneration, isNull);

      // Simulate stale draft where older mediaId was assigned to mismatched generation
      flow.loadSavedDraftState(
        draftId: 'draft_exact_001',
        originalImagePath: photoB.path,
        enhancedImagePath: '',
        transcript: 'Blue clay pot',
        category: 'Pottery',
        mediaId: 'med_asset_A', // Stale asset from Photo A
        imageInputGeneration: 1, // Photo B generation
        boundMediaGeneration: 0, // Belongs to Photo A!
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Step5ConfirmWidget(),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify prominent error banner is displayed
      expect(find.text('Verification Required Before Publishing'), findsOneWidget);
      expect(find.textContaining('belongs to an earlier photo'), findsOneWidget);

      // 2. Verify "List Product" button is disabled
      final buttonFinder = find.byType(AppButton).last;
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<AppButton>(buttonFinder);
      expect(button.onPressed, isNull, reason: 'Publishing must be disabled when media generation is mismatched');

      container.dispose();
    });
  });

  testWidgets('Missing local photo file blocks publication with actionable banner', (tester) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(MockApiService()),
        ],
      );

      final flow = container.read(addProductFlowProvider.notifier);

      // Draft with non-existent local file and no mediaId
      flow.loadSavedDraftState(
        draftId: 'draft_missing_photo',
        originalImagePath: '${tempDir.path}/does_not_exist.jpg',
        enhancedImagePath: '',
        transcript: 'Missing photo item',
        category: 'Woodcraft',
        mediaId: null,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Step5ConfirmWidget(),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Error banner must indicate valid photo is required
      expect(find.text('Verification Required Before Publishing'), findsOneWidget);
      expect(find.textContaining('A valid product photo is required'), findsOneWidget);

      // 2. Publish button must be disabled
      final buttonFinder = find.byType(AppButton).last;
      final button = tester.widget<AppButton>(buttonFinder);
      expect(button.onPressed, isNull, reason: 'Missing photo cannot be published');

      container.dispose();
    });
  });

  testWidgets('Offline raw photo approval is permitted when local photo exists and is verified', (tester) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [
          apiServiceProvider.overrideWithValue(MockApiService()),
        ],
      );

      final flow = container.read(addProductFlowProvider.notifier);

      // Create a real non-empty local file with valid decodable image bytes
      final realPhoto = File('${tempDir.path}/valid_pot.png')
        ..writeAsBytesSync(const [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
          0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
          0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
          0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]);

      flow.loadSavedDraftState(
        draftId: 'draft_valid_raw',
        originalImagePath: realPhoto.path,
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        category: 'Pottery',
        mediaId: null,
        imageInputGeneration: 0,
        boundMediaGeneration: 0,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Step5ConfirmWidget(),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verification error banner must NOT be displayed
      expect(find.text('Verification Required Before Publishing'), findsNothing);

      // Publish button must be enabled
      final buttonFinder = find.byType(AppButton).last;
      final button = tester.widget<AppButton>(buttonFinder);
      expect(button.onPressed, isNotNull, reason: 'Valid offline photo can be approved and published');

      container.dispose();
    });
  });
}
