import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';

class TestMockApiService extends MockApiService {
  int unpublishCalls = 0;
  String? lastUnpublishProductId;
  String? lastUnpublishIdempotencyKey;

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    unpublishCalls++;
    lastUnpublishProductId = productId;
    lastUnpublishIdempotencyKey = idempotencyKey;
    return Product(
      id: productId,
      title: 'Mock Product',
      description: 'Desc',
      price: 1000,
      photoPath: 'photo.jpg',
      category: 'Handicrafts',
      status: ProductStatus.draft,
      revision: 2,
      artisanId: 'artisan_client_status',
    );
  }
}

class DelayedMockApiService extends MockApiService {
  final Completer<List<Product>> completer;
  DelayedMockApiService(this.completer);

  @override
  Future<List<Product>> getProducts({String? artisanId, String? category}) {
    return completer.future;
  }
}

class ProductListMockApiService extends MockApiService {
  final List<Product> products;
  ProductListMockApiService(this.products);

  @override
  Future<List<Product>> getProducts({String? artisanId, String? category}) async {
    return products;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('status_integrity_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }

    final authBox = await Hive.openBox('auth_box');
    await authBox.put('is_authenticated', true);
    await authBox.put('user_id', 'artisan_client_status');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Client Status Integrity & Unpublish Pipeline', () {
    test('Online unpublish calls server endpoint and updates local status to draft', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      const validHash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final publishedProduct = Product(
        id: 'prod_online_unpub',
        title: 'Brass Diya',
        description: 'Traditional Diya',
        price: 850,
        photoPath: 'diya.jpg',
        category: 'Metal Craft',
        status: ProductStatus.published,
        revision: 1,
        contentHash: validHash,
        publishedAt: DateTime.now(),
        approvedAt: DateTime.now(),
        approvedRevision: 1,
      );
      await productsBox.put(publishedProduct.id, publishedProduct);

      final mockApi = TestMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final result = await repo.unpublishProduct('prod_online_unpub', isOnline: true);

      expect(mockApi.unpublishCalls, 1);
      expect(mockApi.lastUnpublishProductId, 'prod_online_unpub');
      expect(result.status, ProductStatus.draft);

      final stored = productsBox.get('prod_online_unpub')!;
      expect(stored.status, ProductStatus.draft);
      expect(pendingBox.isEmpty, isTrue);
    });

    test('Offline unpublish creates UNPUBLISH offline operation and preserves metadata until sync', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      const validHash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final publishedProduct = Product(
        id: 'prod_offline_unpub',
        title: 'Silk Scarf',
        description: 'Handwoven silk',
        price: 1500,
        photoPath: 'silk.jpg',
        category: 'Textiles',
        status: ProductStatus.published,
        revision: 2,
        contentHash: validHash,
        publishedAt: DateTime.now(),
        approvedAt: DateTime.now(),
        approvedRevision: 2,
      );
      await productsBox.put(publishedProduct.id, publishedProduct);

      final mockApi = TestMockApiService();
      final repo = ProductRepository(apiService: mockApi);

      final result = await repo.unpublishProduct('prod_offline_unpub', isOnline: false);

      expect(mockApi.unpublishCalls, 0);
      // Invariant: Do NOT set local product to draft and do NOT clear approval metadata while queued
      expect(result.status, ProductStatus.pendingUnpublishSync);
      expect(result.publishedAt, isNotNull);
      expect(result.approvedAt, isNotNull);
      expect(result.approvedRevision, 2);

      // Verify offline operation was queued
      expect(pendingBox.length, 1);
      final rawOp = pendingBox.values.first;
      final op = OfflineOperation.fromPendingString(rawOp, pendingBox.keys.first.toString());
      expect(op.action, OfflineOperation.actionUnpublish);
      expect(op.productId, 'prod_offline_unpub');
      expect(op.revision, 2);
      expect(op.contentHash, validHash);

      // Now drain the queue as if reconnecting
      final synced = await repo.syncPendingQueue();
      expect(synced, 1);
      expect(mockApi.unpublishCalls, 1);
      expect(mockApi.lastUnpublishProductId, 'prod_offline_unpub');
      expect(mockApi.lastUnpublishIdempotencyKey, op.idempotencyKey);

      // Authoritative transition to draft occurs only after server success
      final stored = productsBox.get('prod_offline_unpub')!;
      expect(stored.status, ProductStatus.draft);
    });

    test('getProducts excludes null-artisanId legacy records without pending ops, but keeps null-artisanId with pending ops', () async {
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      // Legacy product without artisanId and without pending ops (should be excluded)
      final legacyForeign = Product(
        id: 'prod_legacy_foreign',
        title: 'Legacy Foreign Item',
        description: 'No owner stamp',
        price: 500,
        photoPath: 'legacy.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: null,
      );
      await productsBox.put(legacyForeign.id, legacyForeign);

      // Local draft without artisanId BUT with a pending outbox op (should be included)
      final localDraft = Product(
        id: 'prod_local_draft',
        title: 'Local Offline Draft',
        description: 'Pending upload',
        price: 700,
        photoPath: 'draft.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: null,
      );
      await productsBox.put(localDraft.id, localDraft);
      final op = OfflineOperation(
        id: 'op_create_local_draft',
        action: OfflineOperation.actionCreate,
        productId: 'prod_local_draft',
        payloadSnapshot: localDraft.toJson(),
        idempotencyKey: 'idem_test_local_draft_123',
        createdAt: DateTime.now(),
        owner: 'artisan_client_status',
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Authenticated artisan product (should be included)
      final ownedProduct = Product(
        id: 'prod_owned',
        title: 'My Stamped Item',
        description: 'Owned by me',
        price: 1200,
        photoPath: 'owned.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: 'artisan_client_status',
      );
      await productsBox.put(ownedProduct.id, ownedProduct);

      final repo = ProductRepository(apiService: TestMockApiService());
      final visible = await repo.getProducts(isOnline: false);

      final visibleIds = visible.map((p) => p.id).toList();
      expect(visibleIds.contains('prod_legacy_foreign'), isFalse,
          reason: 'Legacy foreign items without pending ops must be excluded at read boundary');
      expect(visibleIds.contains('prod_local_draft'), isTrue,
          reason: 'Local drafts with pending ops must be preserved');
      expect(visibleIds.contains('prod_owned'), isTrue,
          reason: 'Artisan owned items must be returned');
    });

    test('Two-artisan account switch: artisan B must not see artisan A pending-op product, and prod_A remains in Hive', () async {
      final authBox = await Hive.openBox('auth_box');
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      // 1. Artisan A is logged in
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_A');
      ActiveSessionManager.bumpSessionGeneration();

      // prod_A added to Hive with artisanId: null
      final prodA = Product(
        id: 'prod_A',
        title: 'Artisan A Draft',
        description: 'Pending upload by A',
        price: 500,
        photoPath: 'photo_a.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: null,
      );
      await productsBox.put(prodA.id, prodA);

      // Pending operation owned by artisan_A
      final opA = OfflineOperation(
        id: 'op_create_prod_A',
        action: OfflineOperation.actionCreate,
        productId: 'prod_A',
        payloadSnapshot: prodA.toJson(),
        idempotencyKey: 'idem_op_a_123',
        createdAt: DateTime.now(),
        owner: 'artisan_A',
      );
      await pendingBox.put(opA.id, opA.toPendingString());

      // 2. Artisan B logs in
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      // 3. Query repository for artisan B
      final repo = ProductRepository(apiService: TestMockApiService());
      final visibleForB = await repo.getProducts(isOnline: false);

      // Assert artisan B does not see prod_A
      expect(visibleForB.map((p) => p.id), isNot(contains('prod_A')),
          reason: 'Artisan B must not see artisan A unassigned draft with pending op');
      expect(visibleForB, isEmpty);

      // Assert prod_A record is still present in Hive (not deleted)
      expect(productsBox.containsKey('prod_A'), isTrue,
          reason: 'prod_A must remain safely stored in Hive');
    });

    test('Delayed A-response after B-login: B list stays isolated and A response is discarded', () async {
      final authBox = await Hive.openBox('auth_box');
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      // 1. Artisan A is logged in
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_A');
      ActiveSessionManager.bumpSessionGeneration();

      final completer = Completer<List<Product>>();
      final delayedApi = DelayedMockApiService(completer);
      final repo = ProductRepository(apiService: delayedApi);

      // 2. Artisan A starts getProducts(forceRefresh: true)
      final fetchFuture = repo.getProducts(forceRefresh: true, isOnline: true);

      // Wait a tick for request to enter in-flight
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 3. Artisan B logs in while A request is in-flight
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      // 4. Release the mock response for artisan A's request with artisan_A's products
      final prodA = Product(
        id: 'prod_remote_A',
        title: 'Remote Product A',
        description: 'Server product for A',
        price: 800,
        photoPath: 'photo_a.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: 'artisan_A',
      );
      completer.complete([prodA]);

      final result = await fetchFuture;

      // Assert: The in-flight response completed after session changed, so it should return empty
      // and NOT write prod_remote_A to productsBox
      expect(result, isEmpty, reason: 'Stale completion after account switch must return empty list');
      expect(productsBox.containsKey('prod_remote_A'), isFalse,
          reason: 'Stale response from previous artisan session must not mutate cache');

      // Querying as artisan B must return only B's products
      final visibleForB = await repo.getProducts(isOnline: false);
      expect(visibleForB, isEmpty);
    });

    test('Unauthenticated catalogue read must not dispatch and throws StateError', () async {
      final authBox = await Hive.openBox('auth_box');
      await authBox.clear();
      await authBox.put('is_authenticated', false);
      await authBox.delete('user_id');
      ActiveSessionManager.bumpSessionGeneration();

      final dio = Dio();
      int networkCalls = 0;
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          networkCalls++;
          handler.resolve(Response(requestOptions: options, statusCode: 200, data: []));
        },
      ));

      final httpApi = HttpApiService(baseUrl: 'https://fixture.invalid', dio: dio);

      expect(
        () => httpApi.getProducts(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('no authenticated artisan session present'),
        )),
      );
      expect(networkCalls, 0, reason: 'HttpApiService must fail closed before making any HTTP request');
      dio.close();
    });

    test('forceRefresh prune never deletes records whose artisanId is a different known artisan', () async {
      final authBox = await Hive.openBox('auth_box');
      final productsBox = await Hive.openBox<Product>('products_box');
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await productsBox.clear();
      await pendingBox.clear();

      // Cached product of artisan_A
      final prodA = Product(
        id: 'prod_cached_A',
        title: 'Artisan A Product',
        description: 'Owned by A',
        price: 900,
        photoPath: 'photo_a.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: 'artisan_A',
      );
      await productsBox.put(prodA.id, prodA);

      // Unowned orphan product without pending ops (should be pruned)
      final orphan = Product(
        id: 'prod_orphan',
        title: 'Orphan Product',
        description: 'No owner',
        price: 300,
        photoPath: 'orphan.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        artisanId: null,
      );
      await productsBox.put(orphan.id, orphan);

      // Artisan B logs in
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      final mockApi = ProductListMockApiService([
        Product(
          id: 'prod_remote_B',
          title: 'Remote Product B',
          description: 'Owned by B',
          price: 1500,
          photoPath: 'photo_b.jpg',
          category: 'Pottery',
          status: ProductStatus.draft,
          artisanId: 'artisan_B',
        )
      ]);
      final repo = ProductRepository(apiService: mockApi);

      await repo.getProducts(forceRefresh: true, isOnline: true);

      // prod_cached_A must NOT have been deleted
      expect(productsBox.containsKey('prod_cached_A'), isTrue,
          reason: 'Artisan A product must NOT be deleted when artisan B force-refreshes');
      // Orphan must have been deleted
      expect(productsBox.containsKey('prod_orphan'), isFalse,
          reason: 'Unowned orphan record without pending ops is safely pruned');
      // Artisan B product must be present
      expect(productsBox.containsKey('prod_remote_B'), isTrue);
    });

    test('Server responses with null or mismatched artisanId are rejected from cache', () async {
      final authBox = await Hive.openBox('auth_box');
      final productsBox = await Hive.openBox<Product>('products_box');
      await productsBox.clear();

      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      final mockApi = ProductListMockApiService([
        Product(
          id: 'prod_null_owner',
          title: 'Null Owner',
          description: 'Desc',
          price: 500,
          photoPath: 'p1.jpg',
          category: 'Pottery',
          status: ProductStatus.draft,
          artisanId: null, // contract violation: null
        ),
        Product(
          id: 'prod_wrong_owner',
          title: 'Wrong Owner',
          description: 'Desc',
          price: 600,
          photoPath: 'p2.jpg',
          category: 'Pottery',
          status: ProductStatus.draft,
          artisanId: 'artisan_A', // contract violation: different artisan
        ),
        Product(
          id: 'prod_correct_owner',
          title: 'Correct Owner',
          description: 'Desc',
          price: 700,
          photoPath: 'p3.jpg',
          category: 'Pottery',
          status: ProductStatus.draft,
          artisanId: 'artisan_B', // valid
        ),
      ]);

      final repo = ProductRepository(apiService: mockApi);
      final products = await repo.getProducts(forceRefresh: true, isOnline: true);

      expect(products.map((p) => p.id), ['prod_correct_owner']);
      expect(productsBox.containsKey('prod_null_owner'), isFalse,
          reason: 'Null artisanId response must not be stamped or written to cache');
      expect(productsBox.containsKey('prod_wrong_owner'), isFalse,
          reason: 'Mismatched artisanId response must be rejected');
      expect(productsBox.containsKey('prod_correct_owner'), isTrue);
    });

    test('AuthRepository saveAuthData throws StateError when Hive unavailable, and clearAuthData clears secure token', () async {
      final secureStorage = SecureTokenStorage();
      await secureStorage.saveToken('test_secure_token_123');
      expect(await secureStorage.getToken(), 'test_secure_token_123');

      final authRepo = AuthRepository(tokenStorage: secureStorage);

      // Simulate Hive failure
      AuthRepository.setForceBoxFailureForTesting(true);

      // saveAuthData must throw StateError
      expect(
        () => authRepo.saveAuthData('artisan_X', '+919999999999', token: 'new_token'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('auth_box unavailable'),
        )),
      );

      // clearAuthData must still clear secure storage even when Hive is unavailable
      await authRepo.clearAuthData();
      expect(await secureStorage.getToken(), isNull,
          reason: 'Secure token must be cleared independently of Hive box availability');

      // Reset testing flag
      AuthRepository.setForceBoxFailureForTesting(false);
    });
  });
}
