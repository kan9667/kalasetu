import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/core/offline_sync/database/database.dart';
import 'package:kalasetu/core/offline_sync/offline_sync_service.dart';
import 'package:kalasetu/core/offline_sync/services/upload_api.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';
import 'package:kalasetu/core/widgets/app_button.dart';

class _FakeFailingAuthRepository extends AuthRepository {
  @override
  Future<VerifyOtpResult> verifyOtpWithBackend(String phoneNumber, String otp) async {
    return const VerifyOtpFailure(
      message: 'Invalid OTP code. 2 attempt(s) remaining.',
      statusCode: 400,
    );
  }

  @override
  Future<RequestOtpResult> requestOtp(String phone) async {
    return const RequestOtpSuccess(message: 'Challenge created', expiresInSeconds: 300);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('phase1_gap_regression_test_');
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

  tearDown(() async {
    final draftBox = Hive.box('draft_box');
    await draftBox.clear();
    final pendingBox = Hive.box<String>('pending_sync_box');
    await pendingBox.clear();
  });

  group('Amendment 1: Draft Snapshot Single Source of Truth & Migration', () {
    test('Successful migration from legacy multi-key data writes snapshot, verifies readback, and purges legacy keys', () async {
      final box = Hive.box('draft_box');
      await box.clear();

      // Populate legacy keys
      await box.put('draft_id', 'draft_legacy_999');
      await box.put('draft_title_en', 'Legacy Brass Bell');
      await box.put('draft_category', 'Metalwork');
      await box.put('draft_raw_material_cost', 150.0);
      await box.put('draft_labor_hours', 3.0);
      await box.put('draft_hourly_rate', 70.0);
      await box.put('draft_image', '/path/to/legacy_image.jpg');

      expect(box.containsKey(AddProductFlowNotifier.snapshotKey), isFalse);

      final container = ProviderContainer();
      // Trigger notifier creation and migration
      container.read(addProductFlowProvider.notifier);

      // Await migration completion
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Verify active_draft_snapshot exists and has __version == 1
      expect(box.containsKey(AddProductFlowNotifier.snapshotKey), isTrue);
      final rawSnapshot = box.get(AddProductFlowNotifier.snapshotKey) as String;
      final decoded = jsonDecode(rawSnapshot) as Map<String, dynamic>;
      expect(decoded['draft_id'], equals('draft_legacy_999'));
      expect(decoded['title_en'], equals('Legacy Brass Bell'));
      expect(decoded['category'], equals('Metalwork'));
      expect(decoded['__version'], equals(1));

      // Verify legacy keys were purged after successful readback
      expect(box.containsKey('draft_id'), isFalse);
      expect(box.containsKey('draft_title_en'), isFalse);
      expect(box.containsKey('draft_category'), isFalse);
      expect(box.containsKey('draft_raw_material_cost'), isFalse);

      container.dispose();
    });

    test('Corrupt active draft snapshot fails closed with hasCorruptedDraft and does not silently fall back', () async {
      final box = Hive.box('draft_box');
      await box.clear();

      // Write corrupt string into active_draft_snapshot
      await box.put(AddProductFlowNotifier.snapshotKey, '{invalid json syntax: missing closing brace');
      // Also write a legacy key to verify it is NOT silently fallen back to
      await box.put('draft_id', 'stale_legacy_id');

      final container = ProviderContainer();
      final draft = container.read(addProductFlowProvider);

      // Must flag corrupt draft for user recovery
      expect(draft.hasCorruptedDraft, isTrue);
      // Must not silently populate from stale legacy key
      expect(draft.draftId, isNot(equals('stale_legacy_id')));

      container.dispose();
    });
  });

  group('Amendment 3: Immediate Input Invalidation & Floor Protection', () {
    test('Category and tags edits immediately bump generations, clear opIds, and drop stale suggestions', () async {
      final container = ProviderContainer();
      final flow = container.read(addProductFlowProvider.notifier);

      flow.loadSavedDraftState(
        draftId: 'draft_inv_01',
        originalImagePath: '/path/test.jpg',
        enhancedImagePath: '',
        transcript: 'Clay pot',
        category: 'Pottery',
        tags: ['Clay', 'Handmade'],
      );

      expect(container.read(addProductFlowProvider).category, equals('Pottery'));
      final initialListingGen = container.read(addProductFlowProvider).listingInputGeneration;
      final initialPricingGen = container.read(addProductFlowProvider).pricingInputGeneration;

      // User changes category
      await flow.updateListingDetails(category: 'Textiles');

      final updatedDraft = container.read(addProductFlowProvider);
      expect(updatedDraft.category, equals('Textiles'));
      expect(updatedDraft.listingInputGeneration, equals(initialListingGen + 1));
      expect(updatedDraft.pricingInputGeneration, equals(initialPricingGen + 1));
      expect(updatedDraft.voiceListingOpId, isNull);
      expect(updatedDraft.pricingOpId, isNull);

      // User adds tag
      await flow.addTag('Cotton');
      final draftAfterTag = container.read(addProductFlowProvider);
      expect(draftAfterTag.tags.contains('Cotton'), isTrue);
      expect(draftAfterTag.listingInputGeneration, equals(initialListingGen + 1));
      expect(draftAfterTag.pricingInputGeneration, equals(initialPricingGen + 2));
      expect(draftAfterTag.voiceListingOpId, isNull);
      expect(draftAfterTag.pricingOpId, isNull);

      container.dispose();
    });

    test('Cost parameter edits bump pricingInputGeneration, clear pricingOpId, and recalculate floor price', () async {
      final container = ProviderContainer();
      final flow = container.read(addProductFlowProvider.notifier);

      flow.loadSavedDraftState(
        draftId: 'draft_cost_01',
        originalImagePath: '/path/test.jpg',
        enhancedImagePath: '',
        transcript: 'Wooden bowl',
        rawMaterialCost: 100.0,
        laborHours: 2.0,
        hourlyRate: 50.0,
        floorPrice: 200.0,
        pricingOpId: 'op_old_pricing',
      );

      expect(container.read(addProductFlowProvider).floorPrice, equals(200.0));
      final initialPricingGen = container.read(addProductFlowProvider).pricingInputGeneration;

      // Edit cost parameters
      await flow.updateCostParameters(
        materialCost: 300.0,
        laborHours: 4.0,
        hourlyRate: 100.0,
      );

      final updatedDraft = container.read(addProductFlowProvider);
      // Floor price must be recalculated: 300 + 4 * 100 = 700
      expect(updatedDraft.floorPrice, equals(700.0));
      expect(updatedDraft.pricingInputGeneration, equals(initialPricingGen + 1));
      expect(updatedDraft.pricingOpId, isNull);

      container.dispose();
    });

    test('Retake photo invalidates image enhancement, mediaId, listing, and pricing operations', () async {
      final dummyPhoto = File('${tempDir.path}/new_photo.jpg');
      await dummyPhoto.writeAsBytes([1, 2, 3, 4, 5]);

      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      final flow = container.read(addProductFlowProvider.notifier);

      flow.loadSavedDraftState(
        draftId: 'draft_photo_retake',
        originalImagePath: '/path/original.jpg',
        enhancedImagePath: 'https://test/enhanced.jpg',
        transcript: 'Terracotta vase',
        mediaId: 'med_asset_001',
        imageEnhanceOpId: 'op_img_1',
        voiceListingOpId: 'op_voice_1',
        pricingOpId: 'op_price_1',
      );

      final initialImgGen = container.read(addProductFlowProvider).imageInputGeneration;
      final initialPricingGen = container.read(addProductFlowProvider).pricingInputGeneration;

      await flow.retakePhoto(dummyPhoto);

      final updated = container.read(addProductFlowProvider);
      expect(updated.mediaId, isNull);
      expect(updated.imageEnhanceOpId, isNull);
      expect(updated.pricingOpId, isNull);
      expect(updated.imageInputGeneration, equals(initialImgGen + 1));
      expect(updated.pricingInputGeneration, equals(initialPricingGen + 1));

      container.dispose();
    });

    test('Retake voice invalidates transcript, voice listing op, and pricing operations', () async {
      final dummyAudio = File('${tempDir.path}/new_audio.m4a');
      await dummyAudio.writeAsBytes([6, 7, 8, 9]);

      final container = ProviderContainer(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      final flow = container.read(addProductFlowProvider.notifier);

      flow.loadSavedDraftState(
        draftId: 'draft_voice_retake',
        originalImagePath: '/path/test.jpg',
        enhancedImagePath: '',
        transcript: 'Old voice description',
        voiceListingOpId: 'op_voice_1',
        pricingOpId: 'op_price_1',
      );

      final initialVoiceGen = container.read(addProductFlowProvider).voiceInputGeneration;
      final initialListingGen = container.read(addProductFlowProvider).listingInputGeneration;
      final initialPricingGen = container.read(addProductFlowProvider).pricingInputGeneration;

      await flow.retakeVoice(dummyAudio);

      final updated = container.read(addProductFlowProvider);
      expect(updated.voiceTranscript, isEmpty);
      expect(updated.voiceListingOpId, isNull);
      expect(updated.pricingOpId, isNull);
      expect(updated.voiceInputGeneration, equals(initialVoiceGen + 1));
      expect(updated.listingInputGeneration, equals(initialListingGen + 1));
      expect(updated.pricingInputGeneration, equals(initialPricingGen + 1));

      container.dispose();
    });
  });

  group('Amendment 2: Exact-Image Approval & Offline Media Checksum Verification', () {
    testWidgets('Step 5 blocks publishing if raw photo is displayed while publishing enhanced asset', (tester) async {
      await tester.runAsync(() async {
        final container = ProviderContainer(
          overrides: [
            apiServiceProvider.overrideWithValue(MockApiService()),
          ],
        );

        final rawPhoto = File('${tempDir.path}/step5_raw.jpg')
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

        final flow = container.read(addProductFlowProvider.notifier);
        flow.loadSavedDraftState(
          draftId: 'draft_exact_mismatch',
          originalImagePath: rawPhoto.path,
          enhancedImagePath: '',
          transcript: 'Clay bowl',
          category: 'Pottery',
          mediaId: 'med_enhanced_xyz', // Stale or enhanced media
          imageInputGeneration: 1, // Retaken photo generation
          boundMediaGeneration: 0, // Old media generation
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

        // Publish button must be disabled due to mismatched media generation
        final buttonFinder = find.byType(AppButton).last;
        expect(buttonFinder, findsOneWidget);

        final appButton = tester.widget<AppButton>(buttonFinder);
        expect(appButton.onPressed, isNull);

        container.dispose();
      });
    });

    test('Offline publishing embeds media_sha256 in payloadSnapshot and sync fails closed if file modified', () async {
      final dbFile = File('${tempDir.path}/offline_sync_test.sqlite');
      final db = OfflineSyncDatabase(NativeDatabase(dbFile));
      final uploadApi = MockUploadApi();
      await OfflineSyncService.instance.init(uploadApi: uploadApi, db: db);

      // Create a genuine local image file
      final photoFile = File('${tempDir.path}/product_photo.jpg');
      await photoFile.writeAsBytes([10, 20, 30, 40, 50, 60, 70, 80]);
      final originalSha256 = sha256.convert(photoFile.readAsBytesSync()).toString();

      final productBox = Hive.box<Product>('products_box');

      final product = Product(
        id: 'prod_offline_001',
        title: 'Handmade Pot',
        titleHi: 'हाथ का बना बर्तन',
        description: 'Earthen pot',
        descriptionHi: 'मिट्टी का बर्तन',
        price: 500.0,
        floorPrice: 300.0,
        materialsCost: 150.0,
        laborHours: 2.0,
        hourlyRate: 75.0,
        category: 'Pottery',
        photoPath: photoFile.path,
        status: ProductStatus.draft,
        revision: 1,
      );
      await productBox.put(product.id, product);

      final repo = ProductRepository(
        apiService: MockApiService(),
      );
      await repo.initialize();

      // Approve and publish while offline
      await repo.approveAndPublishProduct(
        product.id,
        revision: 1,
        contentHash: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
        isOnline: false,
      );

      // Find the media upload operation in the pending outbox
      final ops = repo.getAllOperations();
      final mediaUploadOp = ops.firstWhere((op) => op.action == OfflineOperation.actionMediaUpload);
      expect(mediaUploadOp, isNotNull);

      // Verify media_sha256 is present in the payloadSnapshot
      final payload = mediaUploadOp.payloadSnapshot!;
      expect(payload['media_sha256'], equals(originalSha256));

      // Tamper with the file on disk (corrupt its bytes)
      await photoFile.writeAsBytes([99, 99, 99, 99, 99]);

      // Attempt to sync the queue
      await repo.syncPendingQueue();

      // Verify the operation failed closed instead of uploading corrupted media
      final updatedOps = repo.getAllOperations();
      final tamperedOp = updatedOps.firstWhere((op) => op.id == mediaUploadOp.id);
      expect(tamperedOp.status, equals(OfflineOperation.statusFailed));

      await OfflineSyncService.instance.dispose();
      await db.close();
    });
  });

  group('Amendment 5: Login Blockers & Session Security Invariants', () {
    test('AuthRepository returns typed VerifyOtpFailure and AuthNotifier does not create fake profile on failure', () async {
      final fakeAuthRepo = _FakeFailingAuthRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuthRepo),
        ],
      );

      final authNotifier = container.read(authStateProvider.notifier);

      // Verify OTP fails with wrong code
      final success = await authNotifier.verifyOtp('9876543210', '000000');
      expect(success, isFalse);

      final authState = container.read(authStateProvider);
      expect(authState.isAuthenticated, isFalse);
      expect(authState.authError, contains('Invalid OTP code'));
      expect(authState.userId, isNull);

      container.dispose();
    });

    test('Local authentication flags alone do not establish verified session without token', () async {
      // SecureTokenStorage has empty token
      final storage = SecureTokenStorage();
      await storage.clearToken();

      final authRepo = AuthRepository(
        tokenStorage: storage,
      );

      // Even if local state thought user was logged in, repository rejects session
      final isAuth = await authRepo.isAuthenticated();
      expect(isAuth, isFalse);
    });

    test('expireSession preserves offline draft_box data', () async {
      final draftBox = Hive.box('draft_box');
      await draftBox.put(AddProductFlowNotifier.snapshotKey, jsonEncode({'draft_id': 'important_draft_123'}));

      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      // Expire session (e.g. 401 unauthorized from backend)
      authNotifier.expireSession();

      // draft_box must remain completely intact
      expect(draftBox.containsKey(AddProductFlowNotifier.snapshotKey), isTrue);
      final raw = draftBox.get(AddProductFlowNotifier.snapshotKey) as String;
      expect(raw, contains('important_draft_123'));

      container.dispose();
    });

    test('NGO/coordinator simulation explicitly sets isNgoSimulation: true', () async {
      final container = ProviderContainer();
      final authNotifier = container.read(authStateProvider.notifier);

      await authNotifier.signInWithCoordinator('coordinator_demo_1');

      final authState = container.read(authStateProvider);
      expect(authState.userId, equals('coordinator_demo_1'));
      expect(authState.isNgoSimulation, isTrue);

      container.dispose();
    });
  });
}
