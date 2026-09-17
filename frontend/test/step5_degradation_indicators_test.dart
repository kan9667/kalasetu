import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/widgets/app_image.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('step5_degradation_test_');
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

  testWidgets('Step 5 displays mediaId and all transparent degradation indicators', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) {
              final notifier = AddProductFlowNotifier(ref);
              notifier.loadSavedDraftState(
                draftId: 'draft_degrade_777',
                originalImagePath: '',
                enhancedImagePath: '',
                transcript: 'Terracotta cup with clay polish',
                titleEn: 'Handmade Terracotta Cup',
                descriptionEn: 'Traditional baked clay cup',
                mediaId: 'med_test_server_asset_888',
                isDegraded: true,
                degradedReason: 'rembg background removal failed',
                isVoiceDegraded: true,
                voiceDegradedReason: 'Low confidence audio recording',
                isListingDegraded: true,
                listingDegradedReason: 'LLM timed out after 25 seconds',
                isPricingDegraded: true,
                pricingDegradedReason: 'ChromaDB comparables unavailable',
              );
              return notifier;
            }),
            apiServiceProvider.overrideWithValue(MockApiService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Step5ConfirmWidget(),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. Verify AppImage received the mediaId as displayImage
      final appImageFinder = find.byType(AppImage);
      expect(appImageFinder, findsOneWidget);
      final appImage = tester.widget<AppImage>(appImageFinder);
      expect(appImage.imageUrl, equals('med_test_server_asset_888'));

      // 2. Verify photo degradation banner
      expect(find.textContaining('Photo Enhancement Degraded: rembg background removal failed'), findsOneWidget);

      // 3. Verify voice transcription degradation banner
      expect(find.textContaining('Voice Transcription Degraded: Low confidence audio recording'), findsOneWidget);

      // 4. Verify AI listing degradation banner
      expect(find.textContaining('AI Listing Degraded: LLM timed out after 25 seconds'), findsOneWidget);

      // 5. Verify AI pricing degradation banner
      expect(find.textContaining('AI Pricing Degraded: ChromaDB comparables unavailable'), findsOneWidget);
    });
  });
}
