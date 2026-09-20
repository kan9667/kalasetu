import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/widgets/app_button.dart';
import 'package:kalasetu/features/catalogue/screens/review_existing_product_screen.dart';
import 'package:kalasetu/features/chatbot/providers/chat_provider.dart';

class AdversarialMockApiService extends MockApiService {
  final List<String> callLog = [];
  final Map<String, int> callCounts = {};
  Product? currentServerProduct;
  bool throwStaleOnUnpublish = false;
  int? staleServerRevision;

  @override
  Future<Product> getProduct(String productId) async {
    callLog.add('getProduct:$productId');
    if (currentServerProduct != null && currentServerProduct!.id == productId) {
      return currentServerProduct!;
    }
    return Product(
      id: productId,
      title: 'Server Terracotta Pot',
      description: 'Server description',
      price: 1200,
      photoPath: 'server_pot.jpg',
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: 3,
      contentHash: '1111111111111111111111111111111111111111111111111111111111111111',
    );
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    callLog.add('approveAndPublishProduct:$productId:rev$revision');
    callCounts['approveAndPublish'] = (callCounts['approveAndPublish'] ?? 0) + 1;
    final published = Product(
      id: productId,
      title: 'Published Item',
      description: 'Description',
      price: 1500,
      photoPath: 'photo.jpg',
      category: 'Pottery',
      status: ProductStatus.published,
      revision: revision,
      contentHash: contentHash,
      publishedAt: DateTime.now(),
      approvedAt: DateTime.now(),
      approvedRevision: revision,
    );
    currentServerProduct = published;
    return published;
  }

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    callLog.add('unpublishProduct:$productId:rev$expectedRevision:hash$contentHash');
    callCounts['unpublish'] = (callCounts['unpublish'] ?? 0) + 1;

    if (throwStaleOnUnpublish) {
      throw StaleRevisionException(
        'Revision or hash conflict on unpublish',
        serverRevision: staleServerRevision ?? 99,
      );
    }

    final unpublished = Product(
      id: productId,
      title: 'Unpublished Item',
      description: 'Description',
      price: 1500,
      photoPath: 'photo.jpg',
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: expectedRevision + 1,
      contentHash: '2222222222222222222222222222222222222222222222222222222222222222',
      publishedAt: null,
      approvedAt: null,
      approvedRevision: null,
    );
    currentServerProduct = unpublished;
    return unpublished;
  }
}

class _FailingGetProductMockApiService extends AdversarialMockApiService {
  final AdversarialMockApiService delegate;
  _FailingGetProductMockApiService(this.delegate) {
    throwStaleOnUnpublish = true;
    staleServerRevision = 5;
  }

  @override
  Future<Product> getProduct(String productId) async {
    throw Exception('Simulated network timeout during conflict refresh');
  }

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    return delegate.unpublishProduct(
      productId,
      expectedRevision: expectedRevision,
      contentHash: contentHash,
      idempotencyKey: idempotencyKey,
    );
  }
}

class _MockReviewProductListNotifier
    extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  String? approvedProductId;
  int? approvedRevision;
  String? approvedContentHash;
  bool addProductCalled = false;

  _MockReviewProductListNotifier() : super(const AsyncValue.data([]));

  @override
  Future<Product> addProduct(Product product) async {
    addProductCalled = true;
    return product;
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    int? revision,
    String? contentHash,
    String? idempotencyKey,
    String? reviewedChecksum,
  }) async {
    approvedProductId = productId;
    approvedRevision = revision;
    approvedContentHash = contentHash;
    return Product(
      id: productId,
      title: 'Published Item',
      description: 'Desc',
      price: 1200,
      photoPath: '',
      category: 'Pottery',
      status: ProductStatus.published,
      revision: revision ?? 1,
      contentHash: contentHash,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const sampleHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('coalescing_adv_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Safe APPROVE_PUBLISH and UNPUBLISH Coalescing & Dependency Adversarial Tests', () {
    test('Scenario a: APPROVE_PUBLISH never submitted is safely cancelled/superseded by UNPUBLISH', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      // Local product in awaiting approval
      final draft = Product(
        id: 'prod_never_submitted',
        title: 'Clay Pot',
        description: 'Desc',
        price: 500,
        photoPath: 'pot.jpg',
        category: 'Pottery',
        status: ProductStatus.awaitingApproval,
        revision: 1,
        contentHash: sampleHash,
      );
      await productsBox.put(draft.id, draft);

      // Queue an APPROVE_PUBLISH operation that has never been submitted
      final approveOp = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: draft.id,
        revision: 1,
        contentHash: sampleHash,
        idempotencyKey: 'idem_approve_never_submitted',
        status: OfflineOperation.statusPending,
        retryCount: 0,
        leaseExpiresAt: null,
        resultData: null,
      );
      await pendingBox.put(approveOp.id, approveOp.toPendingString());

      // User triggers unpublish while offline
      final unpubResult = await repo.unpublishProduct(draft.id, isOnline: false);
      expect(unpubResult.status, ProductStatus.pendingUnpublishSync);

      // Verify APPROVE_PUBLISH was cancelled / superseded
      final storedApproveRaw = pendingBox.get(approveOp.id)!;
      final storedApprove = OfflineOperation.fromPendingString(storedApproveRaw, approveOp.id);
      expect(storedApprove.status, OfflineOperation.statusSuperseded);
      expect(storedApprove.errorMessage, contains('Superseded by unpublish'));

      // Drain sync queue: approve was superseded, unpublish completes
      final syncedCount = await repo.syncPendingQueue();
      expect(syncedCount, 1);
      expect(mockApi.callCounts['approveAndPublish'] ?? 0, 0); // Never published!
      expect(mockApi.callCounts['unpublish'] ?? 0, 1);
    });

    test('Scenario b: APPROVE_PUBLISH in-flight is NEVER cancelled, and UNPUBLISH chains dependency', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final draft = Product(
        id: 'prod_inflight',
        title: 'Clay Lamp',
        description: 'Desc',
        price: 800,
        photoPath: 'lamp.jpg',
        category: 'Pottery',
        status: ProductStatus.awaitingApproval,
        revision: 2,
        contentHash: sampleHash,
      );
      await productsBox.put(draft.id, draft);

      // Approval operation is currently leased / in-flight
      final inflightApprove = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: draft.id,
        revision: 2,
        contentHash: sampleHash,
        idempotencyKey: 'idem_inflight_key',
        status: OfflineOperation.statusInFlight,
        leaseExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await pendingBox.put(inflightApprove.id, inflightApprove.toPendingString());

      // User calls unpublish
      await repo.unpublishProduct(draft.id, isOnline: false);

      // Approval MUST NOT be cancelled or deleted
      final storedApproveRaw = pendingBox.get(inflightApprove.id)!;
      final storedApprove = OfflineOperation.fromPendingString(storedApproveRaw, inflightApprove.id);
      expect(storedApprove.status, OfflineOperation.statusInFlight);

      // UNPUBLISH must depend on the approval operation
      final unpubOpRaw = pendingBox.values.firstWhere(
        (val) => val.contains(OfflineOperation.actionUnpublish),
      );
      final unpubOp = OfflineOperation.fromPendingString(unpubOpRaw, '');
      expect(unpubOp.dependsOnOpId, inflightApprove.id);
    });

    test('Scenario c: Server published but response lost — replayed with original key, authoritative hash recovered, then unpublished', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final draft = Product(
        id: 'prod_response_lost',
        title: 'Terracotta Vase',
        description: 'Desc',
        price: 1500,
        photoPath: 'vase.jpg',
        category: 'Pottery',
        status: ProductStatus.awaitingApproval,
        revision: 1,
        contentHash: sampleHash,
      );
      await productsBox.put(draft.id, draft);

      // Approval had response lost: retryCount > 0
      final responseLostApprove = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: draft.id,
        revision: 1,
        contentHash: sampleHash,
        idempotencyKey: 'idem_lost_response_123',
        status: OfflineOperation.statusPending,
        retryCount: 1,
      );
      await pendingBox.put(responseLostApprove.id, responseLostApprove.toPendingString());

      // User requests unpublish while outcome is uncertain
      await repo.unpublishProduct(draft.id, isOnline: false);

      // Approval MUST NOT be deleted
      expect(pendingBox.containsKey(responseLostApprove.id), isTrue);

      // Now sync queue:
      // 1. APPROVE_PUBLISH replays with original idempotency key, publishes server item
      // 2. UNPUBLISH executes next, recovering published resultData and safely unpublishing it
      final syncedCount = await repo.syncPendingQueue();
      expect(syncedCount, 2);

      expect(mockApi.callCounts['approveAndPublish'], 1);
      expect(mockApi.callCounts['unpublish'], 1);

      // Final state on client must be draft
      final finalStored = productsBox.get(draft.id)!;
      expect(finalStored.status, ProductStatus.draft);
    });

    test('Scenario d: Approval completed before offline unpublish uses authoritative revision and hash', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      const authoritativePublishedHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final completedApprove = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: 'prod_completed_before_unpub',
        revision: 2,
        contentHash: authoritativePublishedHash,
        idempotencyKey: 'idem_completed_approval_key',
        status: OfflineOperation.statusCompleted,
        resultData: {
          'server_product_id': 'prod_completed_before_unpub',
          'revision': 2,
          'content_hash': authoritativePublishedHash,
        },
      );
      await pendingBox.put(completedApprove.id, completedApprove.toPendingString());

      final publishedProduct = Product(
        id: 'prod_completed_before_unpub',
        title: 'Handmade Carpet',
        description: 'Desc',
        price: 4500,
        photoPath: 'carpet.jpg',
        category: 'Textiles',
        status: ProductStatus.published,
        revision: 2,
        contentHash: authoritativePublishedHash,
        publishedAt: DateTime.now(),
        approvedAt: DateTime.now(),
        approvedRevision: 2,
      );
      await productsBox.put(publishedProduct.id, publishedProduct);

      // User calls unpublish while offline
      final res = await repo.unpublishProduct(publishedProduct.id, isOnline: false);
      expect(res.status, ProductStatus.pendingUnpublishSync);

      // Drain sync queue
      final synced = await repo.syncPendingQueue();
      expect(synced, 1);
      expect(
        mockApi.callLog.any(
          (c) => c.contains('unpublishProduct:prod_completed_before_unpub:rev2:hash$authoritativePublishedHash'),
        ),
        isTrue,
      );

      final cachedProduct = productsBox.get(publishedProduct.id)!;
      expect(cachedProduct.status, ProductStatus.draft);
    });

    test('Scenario e: Upstream ATTACH_MEDIA bumps revision/hash, and UNPUBLISH resolves them dynamically', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      const initialHash = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const updatedHash = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

      // Simulating an active upstream operation that will yield revision 5 and updatedHash
      final attachOp = OfflineOperation(
        action: OfflineOperation.actionAttachMedia,
        productId: 'prod_upstream_bump',
        revision: 4,
        contentHash: initialHash,
        idempotencyKey: 'idem_attach_key',
        status: OfflineOperation.statusCompleted,
        resultData: {
          'server_product_id': 'prod_upstream_bump',
          'revision': 5,
          'content_hash': updatedHash,
        },
      );
      await pendingBox.put(attachOp.id, attachOp.toPendingString());

      final product = Product(
        id: 'prod_upstream_bump',
        title: 'Wooden Elephant',
        description: 'Desc',
        price: 2200,
        photoPath: 'elephant.jpg',
        category: 'Woodwork',
        status: ProductStatus.published,
        revision: 4,
        contentHash: initialHash,
      );
      await productsBox.put(product.id, product);

      // Queue unpublish with dependency on attachOp
      final unpubOp = OfflineOperation(
        action: OfflineOperation.actionUnpublish,
        productId: product.id,
        revision: 4,
        contentHash: initialHash,
        idempotencyKey: 'idem_unpub_dep_key',
        dependsOnOpId: attachOp.id,
      );
      await pendingBox.put(unpubOp.id, unpubOp.toPendingString());

      final synced = await repo.syncPendingQueue();
      expect(synced, 1);

      // Must have resolved authoritative revision 5 and updatedHash from parent resultData!
      expect(
        mockApi.callLog.any(
          (c) => c.contains('unpublishProduct:prod_upstream_bump:rev5:hash$updatedHash'),
        ),
        isTrue,
      );
    });

    test('Scenario f: Missing or non-64-char hex contentHash halts with statusUserActionRequired without guessing', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      // Queue unpublish with corrupted / non-hex content_hash
      final unpubOp = OfflineOperation(
        action: OfflineOperation.actionUnpublish,
        productId: 'prod_bad_hash',
        revision: 2,
        contentHash: 'not_a_valid_64_char_hex_hash',
        idempotencyKey: 'idem_bad_hash',
      );
      await pendingBox.put(unpubOp.id, unpubOp.toPendingString());

      final synced = await repo.syncPendingQueue();
      expect(synced, 0);

      final storedOp = OfflineOperation.fromPendingString(pendingBox.get(unpubOp.id)!, unpubOp.id);
      expect(storedOp.status, OfflineOperation.statusUserActionRequired);
      expect(storedOp.errorMessage, contains('valid 64-char SHA-256'));
      expect(mockApi.callCounts['unpublish'] ?? 0, 0); // Halted without submitting!
    });

    test('Scenario g: Revision conflict (409) refreshes product and halts with user_action_required', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      mockApi.throwStaleOnUnpublish = true;
      mockApi.staleServerRevision = 4;
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'prod_conflict',
        title: 'Pottery Item',
        description: 'Desc',
        price: 700,
        photoPath: 'pot.jpg',
        category: 'Pottery',
        status: ProductStatus.published,
        revision: 2,
        contentHash: sampleHash,
      );
      await productsBox.put(product.id, product);

      final unpubOp = OfflineOperation(
        action: OfflineOperation.actionUnpublish,
        productId: product.id,
        revision: 2,
        contentHash: sampleHash,
        idempotencyKey: 'idem_conflict_key',
      );
      await pendingBox.put(unpubOp.id, unpubOp.toPendingString());

      final synced = await repo.syncPendingQueue();
      expect(synced, 0);

      // Op marked user_action_required
      final storedOp = OfflineOperation.fromPendingString(pendingBox.get(unpubOp.id)!, unpubOp.id);
      expect(storedOp.status, OfflineOperation.statusUserActionRequired);

      // Product refreshed from server
      final refreshed = productsBox.get(product.id)!;
      expect(refreshed.revision, 3); // Server authoritative revision fetched
      expect(mockApi.callLog, contains('getProduct:prod_conflict'));
    });

    test('Scenario h: App restart reclaims expired in-flight lease and drains pending queue', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'prod_restart_test',
        title: 'Terracotta Vase',
        description: 'Vase description',
        price: 1200,
        photoPath: 'vase.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: sampleHash,
      );
      await productsBox.put(product.id, product);

      // Simulate an operation that was left in-flight before app crash/kill with expired lease
      final expiredOp = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: product.id,
        revision: 1,
        contentHash: sampleHash,
        idempotencyKey: 'idem_restart_key_1',
        status: OfflineOperation.statusInFlight,
        leaseExpiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await pendingBox.put(expiredOp.id, expiredOp.toPendingString());

      // Verify operation is initially in_flight in box
      final initialRaw = pendingBox.get(expiredOp.id)!;
      final initialOp = OfflineOperation.fromPendingString(initialRaw, expiredOp.id);
      expect(initialOp.status, equals(OfflineOperation.statusInFlight));

      // Reclaim expired leases explicitly (as happens during startup / before sync)
      final reclaimedCount = await repo.reclaimExpiredLeases();
      expect(reclaimedCount, equals(1));

      final reclaimedOp = OfflineOperation.fromPendingString(pendingBox.get(expiredOp.id)!, expiredOp.id);
      expect(reclaimedOp.status, equals(OfflineOperation.statusPending));
      expect(reclaimedOp.leaseExpiresAt, isNull);

      // Now syncPendingQueue drains it successfully
      final synced = await repo.syncPendingQueue();
      expect(synced, equals(1));

      // With no remaining dependents, completed op is purged from outbox
      expect(pendingBox.get(expiredOp.id), isNull);
      final publishedProduct = productsBox.get(product.id)!;
      expect(publishedProduct.status, equals(ProductStatus.published));
    });

    test('Scenario i: Unpublish conflict with network error on refresh retains pendingUnpublishSync', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      final mockApi = AdversarialMockApiService();
      mockApi.throwStaleOnUnpublish = true;
      mockApi.staleServerRevision = 5;

      final failingApi = _FailingGetProductMockApiService(mockApi);
      final repo = ProductRepository(apiService: failingApi);

      final product = Product(
        id: 'prod_unpub_fail_refresh',
        title: 'Brass Bell',
        description: 'Traditional temple bell',
        price: 1500,
        photoPath: 'bell.jpg',
        category: 'Metalwork',
        status: ProductStatus.pendingUnpublishSync,
        revision: 2,
        contentHash: sampleHash,
      );
      await productsBox.put(product.id, product);

      final unpubOp = OfflineOperation(
        action: OfflineOperation.actionUnpublish,
        productId: product.id,
        revision: 2,
        contentHash: sampleHash,
        idempotencyKey: 'idem_unpub_conflict_fail',
      );
      await pendingBox.put(unpubOp.id, unpubOp.toPendingString());

      final synced = await repo.syncPendingQueue();
      expect(synced, equals(0));

      // Stale refresh failed: product MUST retain pendingUnpublishSync (not overwritten by awaitingApproval)
      final retainedProduct = productsBox.get(product.id)!;
      expect(retainedProduct.status, equals(ProductStatus.pendingUnpublishSync));

      // Op marked user_action_required
      final storedOp = OfflineOperation.fromPendingString(pendingBox.get(unpubOp.id)!, unpubOp.id);
      expect(storedOp.status, equals(OfflineOperation.statusUserActionRequired));
    });
  });

  group('ReviewExistingProductScreen Widget & Concurrency Tests', () {
    testWidgets('Fetches authoritative product on entry, detects revision mismatch and renders exact hash', (tester) async {
      final mockApi = AdversarialMockApiService();

      final initialProduct = Product(
        id: 'prod_review_test',
        title: 'Initial Title',
        description: 'Initial Description',
        price: 900,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1, // Navigation snapshot was revision 1
        contentHash: sampleHash,
      );

      mockApi.currentServerProduct = Product(
        id: 'prod_review_test',
        title: 'Updated Server Vase',
        description: 'Updated Server Description',
        price: 1200,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 3, // Server is revision 3
        contentHash: '1111111111111111111111111111111111111111111111111111111111111111',
      );

      final fakeNotifier = _MockReviewProductListNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            apiServiceProvider.overrideWithValue(mockApi),
            productListProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: MaterialApp(
            home: ReviewExistingProductScreen(initialProduct: initialProduct),
          ),
        ),
      );
      // Advance frames so postFrameCallback runs and completes getProduct
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Fetched newer revision: displays mismatch notice
      expect(find.textContaining('Server product was updated (Rev 1 ➔ Rev 3)'), findsOneWidget);
      expect(find.text('Authoritative Revision: 3'), findsOneWidget);
      expect(find.textContaining('1111111111111111111111111111111111111111111111111111111111111111'), findsOneWidget);
      expect(find.text('Updated Server Vase'), findsOneWidget);

      // Tap Approve and Publish
      await tester.tap(find.textContaining('Approve and Publish Revision 3'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5)); // Drain SnackBar timer

      // Verified approveAndPublishProduct was called with exact server revision 3 and hash
      expect(fakeNotifier.approvedProductId, 'prod_review_test');
      expect(fakeNotifier.approvedRevision, 3);
      expect(fakeNotifier.approvedContentHash, '1111111111111111111111111111111111111111111111111111111111111111');

      // Verified Invariant: It must never call addProduct
      expect(fakeNotifier.addProductCalled, isFalse);
    });

    testWidgets('Online fetch failure disables approval and displays retry banner', (tester) async {
      final mockApi = AdversarialMockApiService();

      final initialProduct = Product(
        id: 'prod_fail_fetch',
        title: 'Initial Title',
        description: 'Initial Description',
        price: 900,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: sampleHash,
      );

      final failingApi = _FailingGetProductMockApiService(mockApi);
      final fakeNotifier = _MockReviewProductListNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            apiServiceProvider.overrideWithValue(failingApi),
            productListProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: MaterialApp(
            home: ReviewExistingProductScreen(initialProduct: initialProduct),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Error banner displayed
      expect(find.textContaining('Unable to fetch authoritative product from server. Publication disabled for data integrity.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Button is disabled with verification failed label
      expect(find.text('Verification Failed (Approval Disabled)'), findsOneWidget);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('Offline listing with missing or invalid content hash disables approval', (tester) async {
      final mockApi = AdversarialMockApiService();
      final fakeNotifier = _MockReviewProductListNotifier();

      final invalidOfflineProduct = Product(
        id: 'prod_offline_invalid_hash',
        title: 'Offline Pot',
        description: 'Offline Description',
        price: 800,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: 'not_a_valid_sha256_hash',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(false)), // Offline
            apiServiceProvider.overrideWithValue(mockApi),
            productListProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: MaterialApp(
            home: ReviewExistingProductScreen(initialProduct: invalidOfflineProduct),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Warning banner displayed
      expect(find.textContaining('Offline approval requires a valid revision and 64-character SHA-256 hash'), findsOneWidget);

      // Button disabled
      expect(find.text('Offline Verification Required'), findsOneWidget);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.onPressed, isNull);
    });
  });

  group('Chatbot Relist/Undo & Explicit Human Approval Invariant Tests', () {
    test('undoProductStatusUpdate for live/published/draft returns typed navigation action and NEVER calls updateProduct', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      await productsBox.clear();

      final product = Product(
        id: 'prod_chatbot_undo',
        title: 'Blue Ceramic Vase',
        description: 'Vase description',
        price: 1500,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.soldOut, // Currently sold out
        revision: 2,
        contentHash: sampleHash,
      );
      await productsBox.put(product.id, product);

      final fakeNotifier = _MockReviewProductListNotifier();
      final container = ProviderContainer(
        overrides: [
          productListProvider.overrideWith((ref) => fakeNotifier),
          productRepositoryProvider.overrideWithValue(ProductRepository()),
        ],
      );

      final chatNotifier = container.read(chatNotifierProvider.notifier);

      // Attempt undo where previous status was 'live'
      final action = await chatNotifier.undoProductStatusUpdate(
        'msg_test_1',
        'prod_chatbot_undo',
        'live',
      );

      // Verify returned action is a navigation action to review
      expect(action, isNotNull);
      expect(action!.isNavigate, isTrue);
      expect(action.destination, equals('review_product'));
      expect(action.route, equals('/review-product'));
      expect(action.updatedProductId, equals('prod_chatbot_undo'));

      // Invariant: ProductListNotifier.updateProduct must NEVER be called for live/published/draft
      expect(fakeNotifier.addProductCalled, isFalse);
      // Product in box must NOT have been converted to live or published
      final boxProduct = productsBox.get('prod_chatbot_undo')!;
      expect(boxProduct.status, equals(ProductStatus.soldOut));
    });
  });
}
