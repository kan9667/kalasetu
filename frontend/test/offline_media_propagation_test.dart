import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/offline_sync/database/database.dart';
import 'package:kalasetu/core/offline_sync/offline_sync_service.dart';
import 'package:kalasetu/core/offline_sync/services/connectivity_service.dart';
import 'package:kalasetu/core/offline_sync/services/sync_manager.dart';
import 'package:kalasetu/core/offline_sync/services/upload_api.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_media_propagation_test_');
    Hive.init(tempDir.path);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Drift Database Queue Durability & Offline Media Lineage', () {
    test('Drift OfflineSyncDatabase persists queue items and survives database restarts', () async {
      final dbFile = File('${tempDir.path}/drift_durability.sqlite');
      var db = OfflineSyncDatabase(NativeDatabase(dbFile));

      const localId = 'queue_local_id_101';
      const draftId = 'draft_artisan_101';
      const originalPath = '/data/artisan/photo_raw.jpg';

      // 1. Insert pending queue item
      await db.insertQueueItem(
        QueueItemsCompanion(
          localId: const Value(localId),
          type: const Value(QueueItemType.imageEnhance),
          localFilePath: const Value(originalPath),
          productDraftId: const Value(draftId),
          status: const Value(QueueStatus.pending),
          createdAt: Value(DateTime.now()),
        ),
      );

      final inserted = await db.findItemByLocalId(localId);
      expect(inserted, isNotNull);
      expect(inserted!.status, equals(QueueStatus.pending));
      expect(inserted.type, equals(QueueItemType.imageEnhance));

      // 2. Transition through processing states to completed with structured resultJson
      final completedPayload = {
        'enhancedImageUrl': 'https://api.kaarigarconnect.in/uploads/enhanced/artisan_pot.jpg',
        'mediaId': 'med_enhanced_uuid_456',
        'originalMediaId': 'med_raw_uuid_123',
        'sha256Checksum': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'isDegraded': true,
        'degradedReason': 'rembg optional dependency unavailable; raw upload preserved',
      };

      final updatedItem = inserted.copyWith(
        status: QueueStatus.completed,
        jobId: const Value('job_enhance_999'),
        resultJson: Value(jsonEncode(completedPayload)),
      );
      await db.updateQueueItem(updatedItem);

      // Verify item updated in active db session
      final activeItem = await db.findItemByLocalId(localId);
      expect(activeItem!.status, equals(QueueStatus.completed));
      expect(activeItem.jobId, equals('job_enhance_999'));

      // 3. Close database connection to simulate app process termination
      await db.close();

      // 4. Reopen database from same SQLite disk file
      final reopenedDb = OfflineSyncDatabase(NativeDatabase(dbFile));
      final durableItem = await reopenedDb.findItemByLocalId(localId);

      expect(durableItem, isNotNull);
      expect(durableItem!.status, equals(QueueStatus.completed));
      expect(durableItem.jobId, equals('job_enhance_999'));
      expect(durableItem.resultJson, isNotNull);

      final decodedJson = jsonDecode(durableItem.resultJson!) as Map<String, dynamic>;
      expect(decodedJson['mediaId'], equals('med_enhanced_uuid_456'));
      expect(decodedJson['originalMediaId'], equals('med_raw_uuid_123'));
      expect(decodedJson['isDegraded'], isTrue);
      expect(decodedJson['degradedReason'], contains('rembg optional dependency unavailable'));

      await reopenedDb.close();
    });

    test('End-to-End Drift Queue Item propagates to AddProductDraft, persists in Hive, and binds to Product Step 5', () async {
      final dbFile = File('${tempDir.path}/drift_propagation.sqlite');
      final db = OfflineSyncDatabase(NativeDatabase(dbFile));

      await Hive.openBox('draft_box');
      await Hive.openBox<UserProfile>('user_profile_box');

      const localId = 'queue_local_prop_202';
      const draftId = 'draft_artisan_202';

      final mockApi = MockUploadApi(failureRate: 0.0);
      await OfflineSyncService.instance.init(uploadApi: mockApi, db: db);

      final container = ProviderContainer();
      final notifier = container.read(addProductFlowProvider.notifier);

      // 1. Initialize draft with imageQueueItemId listening to Drift queue
      notifier.loadSavedDraftState(
        draftId: draftId,
        originalImagePath: '/data/local_image.jpg',
        enhancedImagePath: '',
        transcript: 'Handmade terracotta pot',
        category: 'Pottery',
        imageQueueItemId: localId,
      );

      // 2. Insert completed enhancement into real Drift DB
      final completedPayload = {
        'enhancedImageUrl': 'https://api.kaarigarconnect.in/uploads/enhanced/terracotta.jpg',
        'mediaId': 'media_asset_uuid_789',
        'originalMediaId': 'media_asset_uuid_123',
        'sha256Checksum': 'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899',
        'isDegraded': true,
        'degradedReason': 'rembg optional dependency unavailable; raw upload preserved',
      };

      await db.insertQueueItem(
        QueueItemsCompanion(
          localId: const Value(localId),
          type: const Value(QueueItemType.imageEnhance),
          localFilePath: const Value('/data/local_image.jpg'),
          productDraftId: const Value(draftId),
          status: const Value(QueueStatus.completed),
          createdAt: Value(DateTime.now()),
          resultJson: Value(jsonEncode(completedPayload)),
        ),
      );

      // Allow Drift watch stream to automatically propagate to AddProductNotifier
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final draftState = container.read(addProductFlowProvider);
      expect(draftState.mediaId, 'media_asset_uuid_789');
      expect(draftState.originalMediaId, 'media_asset_uuid_123');
      expect(draftState.sha256Checksum, 'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899');
      expect(draftState.isDegraded, isTrue);
      expect(draftState.degradedReason, contains('rembg optional dependency unavailable'));

      // 3. Verify durable persistence in Hive's draft_box
      final draftBox = Hive.box('draft_box');
      final snapshotRaw = draftBox.get('active_draft_snapshot');
      expect(snapshotRaw, isNotNull);
      final snapshot = jsonDecode(snapshotRaw.toString()) as Map<String, dynamic>;
      expect(snapshot['media_id'], 'media_asset_uuid_789');
      expect(snapshot['original_media_id'], 'media_asset_uuid_123');
      expect(snapshot['sha256_checksum'], 'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899');
      expect(snapshot['is_degraded'], isTrue);
      expect(snapshot['degraded_reason'], contains('rembg optional dependency unavailable'));

      // 4. Simulate app restart / fresh ProviderContainer with automatic hydration
      final newContainer = ProviderContainer();
      final newNotifier = newContainer.read(addProductFlowProvider.notifier);
      newNotifier.resumeExistingDraft();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final restoredState = newContainer.read(addProductFlowProvider);
      expect(restoredState.mediaId, 'media_asset_uuid_789');
      expect(restoredState.originalMediaId, 'media_asset_uuid_123');
      expect(restoredState.sha256Checksum, 'a1b2c3d4e5f600112233445566778899aabbccddeeff00112233445566778899');
      expect(restoredState.isDegraded, isTrue);
      expect(restoredState.degradedReason, contains('rembg optional dependency unavailable'));

      // 5. Ensure Product construction in Step 5 receives authoritative mediaId
      final step5Product = Product(
        id: 'prod_test_step5',
        title: restoredState.titleEn.isNotEmpty ? restoredState.titleEn : 'Handcrafted Pottery',
        description: restoredState.descriptionEn,
        price: 500,
        photoPath: restoredState.originalImagePath,
        category: restoredState.category,
        mediaId: restoredState.mediaId,
      );

      expect(step5Product.mediaId, 'media_asset_uuid_789');
      expect(step5Product.toBackendJson()['media_id'], 'media_asset_uuid_789');

      container.dispose();
      newContainer.dispose();
      await OfflineSyncService.instance.dispose();
    });

    test('Real Drift queue path with Mock HTTP processes upload, persists sha256Checksum, and reconciles across restart', () async {
      final dbFile = File('${tempDir.path}/drift_real_upload_path.sqlite');
      var db = OfflineSyncDatabase(NativeDatabase(dbFile));

      await Hive.openBox('draft_box');
      await Hive.openBox<UserProfile>('user_profile_box');

      const expectedMediaId = 'med_enhanced_live_777';
      const expectedSha256 = '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b';

      final dio = Dio(BaseOptions(baseUrl: 'https://api.kalasetu.org'));
      dio.httpClientAdapter = _MockHttpAdapter((options) async {
        if (options.path.contains('/api/v1/catalog/enhance-image')) {
          return ResponseBody.fromString(
            jsonEncode({
              'enhanced_url': '/api/v1/media/$expectedMediaId',
              'original_url': '/api/v1/media/med_raw_orig_888',
              'media_id': expectedMediaId,
              'original_media_id': 'med_raw_orig_888',
              'sha256_checksum': expectedSha256,
              'is_degraded': true,
              'degraded_reason': 'rembg unavailable in backend worker; raw fallback used',
              'status': 'ready',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString(jsonEncode({'error': 'Not found'}), 404);
      });

      final uploadApi = RealUploadApi(baseUrl: 'https://api.kalasetu.org', dio: dio);
      final connectivityService = _FakeConnectivityService(isOnline: true);
      final syncManager = SyncManager(
        db: db,
        uploadApi: uploadApi,
        connectivityService: connectivityService,
      );

      // Create physical local photo
      final rawImageFile = File('${tempDir.path}/raw_artisan_capture.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

      // Enqueue via real SyncManager
      final localId = await syncManager.enqueue(
        file: rawImageFile,
        type: QueueItemType.imageEnhance,
        productDraftId: 'draft_live_test_777',
      );

      // Trigger actual sync engine loop
      await syncManager.triggerSyncIfOnline();

      // Verify Drift DB record transitioned to completed with sha256_checksum
      final completedDriftItem = await db.findItemByLocalId(localId);
      expect(completedDriftItem, isNotNull);
      expect(completedDriftItem!.status, equals(QueueStatus.completed));
      expect(completedDriftItem.resultJson, isNotNull);

      final resultJson = jsonDecode(completedDriftItem.resultJson!) as Map<String, dynamic>;
      expect(resultJson['mediaId'], equals(expectedMediaId));
      expect(resultJson['sha256_checksum'], equals(expectedSha256));
      expect(resultJson['sha256Checksum'], equals(expectedSha256));
      expect(resultJson['isDegraded'], isTrue);

      // Close and reopen Drift database from same SQLite disk file
      await db.close();
      final reopenedDb = OfflineSyncDatabase(NativeDatabase(dbFile));
      final durableItem = await reopenedDb.findItemByLocalId(localId);
      expect(durableItem, isNotNull);
      expect(durableItem!.status, equals(QueueStatus.completed));

      final durableJson = jsonDecode(durableItem.resultJson!) as Map<String, dynamic>;
      expect(durableJson['sha256_checksum'], equals(expectedSha256));
      expect(durableJson['mediaId'], equals(expectedMediaId));

      // Feed into AddProductDraft and ensure propagation to Hive and Step 5
      final container = ProviderContainer();
      final notifier = container.read(addProductFlowProvider.notifier);

      notifier.loadSavedDraftState(
        draftId: 'draft_live_test_777',
        originalImagePath: rawImageFile.path,
        enhancedImagePath: durableJson['enhancedImageUrl'] as String? ?? '',
        transcript: 'Clay water pot',
        mediaId: durableJson['mediaId'] as String?,
        sha256Checksum: durableJson['sha256_checksum'] as String?,
        isDegraded: durableJson['isDegraded'] as bool?,
        degradedReason: durableJson['degradedReason'] as String?,
      );

      final draftState = container.read(addProductFlowProvider);
      expect(draftState.mediaId, equals(expectedMediaId));
      expect(draftState.sha256Checksum, equals(expectedSha256));
      expect(draftState.isDegraded, isTrue);

      final draftBox = Hive.box('draft_box');
      final snapshotRaw = draftBox.get('active_draft_snapshot');
      expect(snapshotRaw, isNotNull);
      final snapshot = jsonDecode(snapshotRaw.toString()) as Map<String, dynamic>;
      expect(snapshot['media_id'], equals(expectedMediaId));
      expect(snapshot['sha256_checksum'], equals(expectedSha256));

      final step5Product = Product(
        id: 'prod_reconciled_777',
        title: 'Handcrafted Clay Water Pot',
        description: draftState.descriptionEn.isNotEmpty ? draftState.descriptionEn : 'Traditional clay water pot',
        price: 750,
        photoPath: draftState.originalImagePath,
        category: 'Pottery',
        mediaId: draftState.mediaId,
      );
      expect(step5Product.mediaId, equals(expectedMediaId));

      container.dispose();
      await reopenedDb.close();
      syncManager.dispose();
    });

    test('ProductRepository.initialize reclaims expired in-flight approval lease and preserves dependent unpublish sequencing', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await pendingBox.clear();
      await productsBox.clear();

      final initialProduct = Product(
        id: 'prod_lease_reclaim',
        title: 'Madhubani Painting',
        description: 'Traditional folk painting on handmade paper',
        price: 1500,
        photoPath: '/data/artisan/painting.jpg',
        category: 'Painting',
        status: ProductStatus.draft,
      );
      await productsBox.put(initialProduct.id, initialProduct);

      final expiredLeaseTime = DateTime.now().subtract(const Duration(minutes: 15));
      final approveOp = OfflineOperation(
        id: 'op_approve_reclaim_001',
        action: OfflineOperation.actionApprovePublish,
        productId: 'prod_lease_reclaim',
        revision: 1,
        contentHash: 'f' * 64,
        idempotencyKey: 'idem_appr_001',
        status: OfflineOperation.statusInFlight,
        leaseExpiresAt: expiredLeaseTime,
      );
      await pendingBox.put(approveOp.id, approveOp.toPendingString());

      final unpublishOp = OfflineOperation(
        id: 'op_unpublish_dep_002',
        action: OfflineOperation.actionUnpublish,
        productId: 'prod_lease_reclaim',
        revision: 1,
        contentHash: 'f' * 64,
        idempotencyKey: 'idem_unpub_002',
        status: OfflineOperation.statusPending,
        dependsOnOpId: 'op_approve_reclaim_001',
      );
      await pendingBox.put(unpublishOp.id, unpublishOp.toPendingString());

      // Simulate app restart: Instantiate fresh repository and await initialize
      final repository = ProductRepository(apiService: MockApiService());
      await repository.initialize(now: DateTime.now());

      final allOps = repository.getAllOperations();
      final reclaimedApprove = allOps.firstWhere((o) => o.id == 'op_approve_reclaim_001');
      expect(reclaimedApprove.status, equals(OfflineOperation.statusPending));
      expect(reclaimedApprove.leaseExpiresAt, isNull);

      final depUnpublish = allOps.firstWhere((o) => o.id == 'op_unpublish_dep_002');
      expect(depUnpublish.status, equals(OfflineOperation.statusPending));
      expect(depUnpublish.dependsOnOpId, equals('op_approve_reclaim_001'));

      // Ensure operations can be inspected by product ID
      expect(repository.hasPendingOperationsFor('prod_lease_reclaim'), isTrue);
    });
  });
}

class _MockHttpAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  _MockHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeConnectivityService extends ConnectivityService {
  final bool isOnline;
  _FakeConnectivityService({this.isOnline = true}) : super(healthCheckUrl: 'http://test/health');

  @override
  Future<bool> hasRealInternet() async => isOnline;

  @override
  Stream<bool> get onConnectivityChanged => Stream.value(isOnline);
}
