import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';

class ChainingMockApiService extends MockApiService {
  int createCount = 0;
  int mediaUploadCount = 0;
  int updateCount = 0;
  int publishCount = 0;

  final List<String> capturedIdempotencyKeys = [];
  final List<String> capturedUploadKeys = [];
  final List<String> capturedPublishKeys = [];

  int? lastPublishedRevision;
  String? lastPublishedContentHash;
  bool failPublishWithConflict = false;
  bool failFirstCreate = false;
  bool firstCreateAttemptDone = false;

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    createCount++;
    if (idempotencyKey != null) {
      capturedIdempotencyKeys.add(idempotencyKey);
    }
    if (failFirstCreate && !firstCreateAttemptDone) {
      firstCreateAttemptDone = true;
      throw Exception('Simulated network timeout before response received (response-lost)');
    }
    return product.copyWith(
      status: ProductStatus.draft,
      revision: 1,
      contentHash: 'server_hash_create_${product.id}_rev_1',
    );
  }

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    mediaUploadCount++;
    if (idempotencyKey != null) {
      capturedUploadKeys.add(idempotencyKey);
    }
    return {
      'media_id': 'med_server_12345',
      'file_url': '/api/v1/media/med_server_12345',
      'mime_type': 'image/jpeg',
      'byte_size': 20480,
      'sha256_checksum': 'abc_checksum_999',
      'status': 'ready',
    };
  }

  @override
  Future<Product> updateProduct(Product product, {int? expectedRevision, String? idempotencyKey}) async {
    updateCount++;
    final newRevision = (product.revision) + 1;
    final serverHash = 'server_hash_rev_${newRevision}_with_med_${product.mediaId}';
    return product.copyWith(
      revision: newRevision,
      contentHash: serverHash,
      status: ProductStatus.draft,
    );
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    publishCount++;
    if (idempotencyKey != null) {
      capturedPublishKeys.add(idempotencyKey);
    }
    lastPublishedRevision = revision;
    lastPublishedContentHash = contentHash;

    if (failPublishWithConflict) {
      throw StaleRevisionException('Stale revision conflict from server');
    }

    return Product(
      id: productId,
      title: 'Synced Handloom Scarf',
      description: 'Pure silk handloom scarf',
      price: 1500.0,
      photoPath: '/tmp/scarf.jpg',
      category: 'Textiles',
      status: ProductStatus.published,
      revision: revision,
      approvedRevision: revision,
      contentHash: contentHash,
      mediaId: 'med_server_12345',
      approvedAt: DateTime.now(),
      publishedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_outbox_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }

    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    final productsBox = Hive.box<Product>('products_box');
    final pendingBox = Hive.box<String>('pending_sync_box');
    await productsBox.clear();
    await pendingBox.clear();
  });

  group('Offline Append-Only Outbox & Durability Tests', () {
    test('Offline create-then-approve chains dependencies: CREATE -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH', () async {
      final mockApi = ChainingMockApiService();
      final repo = ProductRepository(apiService: mockApi);
      final productsBox = Hive.box<Product>('products_box');

      // Create a temporary dummy image file
      final testImageFile = File('${tempDir.path}/test_scarf.jpg');
      testImageFile.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);

      // 1. Offline CREATE
      final draft = Product(
        id: 'prod_offline_chain',
        title: 'Silk Scarf',
        description: 'Handmade pure silk',
        price: 1500.0,
        photoPath: testImageFile.path,
        category: 'Textiles',
      );
      final createdLocal = await repo.addProduct(draft, isOnline: false);
      expect(createdLocal.status, ProductStatus.pendingSync);

      // 2. Offline APPROVE
      final approvedLocal = await repo.approveAndPublishProduct(
        'prod_offline_chain',
        isOnline: false,
      );

      // INVARIANT: Do NOT mark approved/published locally while offline!
      expect(approvedLocal.status, ProductStatus.pendingApprovalSync);
      expect(approvedLocal.approvedAt, isNull);
      expect(approvedLocal.publishedAt, isNull);
      expect(approvedLocal.approvedRevision, isNull);

      // 3. Inspect Outbox operations
      final allOps = repo.getAllOperations();
      expect(allOps.length, 4, reason: 'Must have CREATE, MEDIA_UPLOAD, ATTACH_MEDIA, APPROVE_PUBLISH');

      final createOp = allOps.firstWhere((o) => o.action == OfflineOperation.actionCreate);
      final mediaOp = allOps.firstWhere((o) => o.action == OfflineOperation.actionMediaUpload);
      final attachOp = allOps.firstWhere((o) => o.action == OfflineOperation.actionAttachMedia);
      final pubOp = allOps.firstWhere((o) => o.action == OfflineOperation.actionApprovePublish);

      // Dependency ordering verification
      expect(mediaOp.dependsOnOpId, createOp.id);
      expect(attachOp.dependsOnOpId, mediaOp.id);
      expect(pubOp.dependsOnOpId, attachOp.id);

      // 4. Drain queue
      final syncedCount = await repo.syncPendingQueue();
      expect(syncedCount, 4);

      // Server calls verification
      expect(mockApi.createCount, 1);
      expect(mockApi.mediaUploadCount, 1);
      expect(mockApi.updateCount, 1);
      expect(mockApi.publishCount, 1);

      // Published state in Hive
      final storedProduct = productsBox.get('prod_offline_chain');
      expect(storedProduct, isNotNull);
      expect(storedProduct!.status, ProductStatus.published);
      expect(storedProduct.mediaId, 'med_server_12345');
      expect(storedProduct.revision, 2);

      // Outbox drained
      expect(repo.getPendingCount(), 0);
    });

    test('Restart recovery: Outbox survives Hive box closure and re-opening', () async {
      final mockApi = ChainingMockApiService();
      var repo = ProductRepository(apiService: mockApi);

      final draft = Product(
        id: 'prod_restart_test',
        title: 'Terracotta Bell',
        description: 'Wind bell',
        price: 450.0,
        photoPath: '',
        category: 'Pottery',
      );
      await repo.addProduct(draft, isOnline: false);
      await repo.approveAndPublishProduct('prod_restart_test', isOnline: false);

      expect(repo.getAllOperations().length, 2); // CREATE and APPROVE_PUBLISH

      // Simulate App Kill / Restart
      await Hive.close();

      // Re-open Hive
      await Hive.openBox<Product>('products_box');
      await Hive.openBox<String>('pending_sync_box');
      repo = ProductRepository(apiService: mockApi);

      // Operations survive restart
      final restoredOps = repo.getAllOperations();
      expect(restoredOps.length, 2);
      expect(restoredOps.any((o) => o.action == OfflineOperation.actionCreate), isTrue);
      expect(restoredOps.any((o) => o.action == OfflineOperation.actionApprovePublish), isTrue);

      // Successfully drain after restart
      final synced = await repo.syncPendingQueue();
      expect(synced, 2);
      expect(repo.getPendingCount(), 0);
    });

    test('Response-lost retry: Exact idempotency key is preserved and re-transmitted', () async {
      final mockApi = ChainingMockApiService()..failFirstCreate = true;
      final repo = ProductRepository(apiService: mockApi);

      final draft = Product(
        id: 'prod_response_lost',
        title: 'Brass Ganesha',
        description: 'Lost wax casting',
        price: 2100.0,
        photoPath: '',
        category: 'Metal Craft',
      );
      await repo.addProduct(draft, isOnline: false);

      final initialOp = repo.getAllOperations().first;
      final savedIdempotencyKey = initialOp.idempotencyKey;
      expect(savedIdempotencyKey, isNotEmpty);

      // First sync attempt fails with network drop
      await repo.syncPendingQueue();
      expect(mockApi.createCount, 1);
      expect(repo.getPendingCount(), 1);

      // Second sync attempt (retry)
      await repo.syncPendingQueue();
      expect(mockApi.createCount, 2);
      expect(repo.getPendingCount(), 0);

      // Assert BOTH attempts used the EXACT SAME idempotency key
      expect(mockApi.capturedIdempotencyKeys.length, 2);
      expect(mockApi.capturedIdempotencyKeys[0], savedIdempotencyKey);
      expect(mockApi.capturedIdempotencyKeys[1], savedIdempotencyKey);
    });

    test('Duplicate-retry safety: Repeated drains are idempotent and do not duplicate', () async {
      final mockApi = ChainingMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final draft = Product(
        id: 'prod_dedup_test',
        title: 'Handmade Wool Shawl',
        description: 'Warm pashmina shawl',
        price: 3200.0,
        photoPath: '',
        category: 'Textiles',
      );
      await repo.addProduct(draft, isOnline: false);

      // First sync drain
      final count1 = await repo.syncPendingQueue();
      expect(count1, 1);
      expect(mockApi.createCount, 1);

      // Second sync drain immediately following
      final count2 = await repo.syncPendingQueue();
      expect(count2, 0);
      expect(mockApi.createCount, 1, reason: 'Duplicate sync must not re-invoke API calls');
    });

    test('Later local edit: Edits to un-synced draft append UPDATE preserving dependencies', () async {
      final mockApi = ChainingMockApiService();
      final repo = ProductRepository(apiService: mockApi);
      final productsBox = Hive.box<Product>('products_box');

      // 1. Initial draft creation
      final draft = Product(
        id: 'prod_later_edit',
        title: 'Original Title',
        description: 'Original description',
        price: 600.0,
        photoPath: '',
        category: 'Pottery',
        revision: 1,
      );
      await repo.addProduct(draft, isOnline: false);

      // 2. Later local edit before sync
      final modifiedDraft = draft.copyWith(
        title: 'Edited Modern Title',
        price: 750.0,
      );
      await repo.updateProduct(modifiedDraft, isOnline: false);

      // Both operations exist in outbox without overwriting each other
      final ops = repo.getAllOperations();
      expect(ops.length, 2);

      final createOp = ops.firstWhere((o) => o.action == OfflineOperation.actionCreate);
      final updateOp = ops.firstWhere((o) => o.action == OfflineOperation.actionUpdate);

      expect(updateOp.dependsOnOpId, createOp.id);

      // 3. Drain queue
      await repo.syncPendingQueue();

      expect(mockApi.createCount, 1);
      expect(mockApi.updateCount, 1);

      // Final product in Hive has the updated attributes
      final finalProduct = productsBox.get('prod_later_edit');
      expect(finalProduct, isNotNull);
      expect(finalProduct!.title, 'Edited Modern Title');
      expect(finalProduct.revision, 2);
    });

    test('Upstream results retention: Completed operations remain until dependents finish', () async {
      final mockApi = ChainingMockApiService()..failPublishWithConflict = true;
      final repo = ProductRepository(apiService: mockApi);
      final pendingBox = Hive.box<String>('pending_sync_box');

      final draft = Product(
        id: 'prod_retention_test',
        title: 'Wood Carving',
        description: 'Rosewood relief',
        price: 1800.0,
        photoPath: '',
        category: 'Woodcraft',
      );
      await repo.addProduct(draft, isOnline: false);
      await repo.approveAndPublishProduct('prod_retention_test', isOnline: false);

      // Attempt drain: CREATE succeeds, APPROVE_PUBLISH encounters conflict
      await repo.syncPendingQueue();

      // Invariant: CREATE completed, but must NOT be purged because APPROVE_PUBLISH depends on it!
      final remainingOps = repo.getAllOperations();
      final createOp = remainingOps.firstWhere((o) => o.action == OfflineOperation.actionCreate);
      final pubOp = remainingOps.firstWhere((o) => o.action == OfflineOperation.actionApprovePublish);

      expect(createOp.status, OfflineOperation.statusCompleted);
      expect(createOp.resultData, isNotNull);
      expect(createOp.resultData!['server_product_id'], 'prod_retention_test');

      expect(pubOp.status, OfflineOperation.statusUserActionRequired);
      expect(pendingBox.containsKey(createOp.id), isTrue,
          reason: 'Completed upstream operation must be retained while dependent remains');
    });
  });
}
