import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

class _MockBarrierApiService extends MockApiService {
  int getProductsCalls = 0;
  int createProductCalls = 0;
  int updateProductCalls = 0;
  int approveCalls = 0;
  int unpublishCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<Product>> getProducts({String? artisanId, String? category}) async {
    getProductsCalls++;
    return [];
  }

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    createProductCalls++;
    return product.copyWith(status: ProductStatus.draft);
  }

  @override
  Future<Product> updateProduct(Product product, {int? expectedRevision, String? idempotencyKey}) async {
    updateProductCalls++;
    return product.copyWith(revision: product.revision + 1);
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    approveCalls++;
    return Product(
      id: productId,
      title: 'Item',
      description: 'Desc',
      price: 1000,
      photoPath: '',
      category: 'Pottery',
      status: ProductStatus.published,
      revision: revision,
      contentHash: contentHash,
    );
  }

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    unpublishCalls++;
    return Product(
      id: productId,
      title: 'Item',
      description: 'Desc',
      price: 1000,
      photoPath: '',
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: expectedRevision + 1,
      contentHash: contentHash,
    );
  }

  @override
  Future<bool> deleteProduct(String id, {String? idempotencyKey}) async {
    deleteCalls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box<Product> productsBox;
  late Box<String> pendingBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_barrier_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }

    productsBox = await Hive.openBox<Product>('products_box');
    pendingBox = await Hive.openBox<String>('pending_sync_box');
    final authBox = await Hive.openBox('auth_box');
    await authBox.put('is_authenticated', true);
    await authBox.put('user_id', 'artisan_barrier_test');
    await authBox.put('phone_number', '+919876543210');
  });

  tearDownAll(() async {
    await productsBox.close();
    await pendingBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    await productsBox.clear();
    await pendingBox.clear();
  });

  group('ProductRepository Initialization Barrier & Fail-Closed Malformed Handling', () {
    test('Initialization is single-flight across concurrent invocations', () async {
      final mockApi = _MockBarrierApiService();
      final repo = ProductRepository(apiService: mockApi);

      final f1 = repo.initialize();
      final f2 = repo.initialize();

      expect(identical(f1, f2), isTrue, reason: 'Concurrent initialize calls must share the exact same Future');
      await Future.wait([f1, f2]);

      final f3 = repo.initialize();
      // After resolution, initialize returns an already completed future
      await f3;
      expect(true, isTrue);
    });

    test('All repository entry points gate on initialization', () async {
      final mockApi = _MockBarrierApiService();
      final repo = ProductRepository(apiService: mockApi);

      // Add a product to local box to allow update/approve/unpublish/delete
      const testHash = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final product = Product(
        id: 'prod_barrier_1',
        title: 'Barrier Vase',
        description: 'Handmade vase',
        price: 2500,
        photoPath: 'vase.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: testHash,
      );
      await productsBox.put(product.id, product);

      // getProducts gates on initialize
      final products = await repo.getProducts();
      expect(products.length, equals(1));

      // addProduct gates on initialize
      final newProd = Product(
        id: 'prod_barrier_2',
        title: 'Barrier Bowl',
        description: 'Clay bowl',
        price: 1800,
        photoPath: 'bowl.jpg',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: testHash,
      );
      await repo.addProduct(newProd);
      expect(mockApi.createProductCalls, equals(1));

      // updateProduct gates on initialize
      await repo.updateProduct(newProd.copyWith(price: 2000));
      expect(mockApi.updateProductCalls, equals(1));

      // approveAndPublishProduct gates on initialize
      await repo.approveAndPublishProduct(
        product.id,
        revision: 1,
        contentHash: testHash,
      );
      expect(mockApi.approveCalls, equals(1));

      // unpublishProduct gates on initialize
      await repo.unpublishProduct(product.id);
      expect(mockApi.unpublishCalls, equals(1));

      // deleteProduct gates on initialize
      await repo.deleteProduct(product.id);
      expect(mockApi.deleteCalls, equals(1));

      // syncPendingQueue gates on initialize
      final synced = await repo.syncPendingQueue();
      expect(synced, equals(0));
    });

    test('Initialize reclaims expired in-flight leases automatically', () async {
      final expiredOp = OfflineOperation(
        id: 'op_expired_init_01',
        action: OfflineOperation.actionUpdate,
        productId: 'prod_test_lease',
        idempotencyKey: 'key_expired_01',
        status: OfflineOperation.statusInFlight,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        leaseExpiresAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      await pendingBox.put(expiredOp.id, expiredOp.toPendingString());

      final mockApi = _MockBarrierApiService();
      final repo = ProductRepository(apiService: mockApi);

      await repo.initialize();

      final raw = pendingBox.get(expiredOp.id);
      expect(raw, isNotNull);
      final reclaimedOp = OfflineOperation.fromPendingString(raw!, expiredOp.id);
      expect(reclaimedOp.status, equals(OfflineOperation.statusPending));
      expect(reclaimedOp.leaseExpiresAt, isNull);
    });

    test('Initialize migrates legacy raw action strings to modern OfflineOperation records', () async {
      // Legacy string format
      await pendingBox.put('prod_legacy_01', 'CREATE');

      final mockApi = _MockBarrierApiService();
      final repo = ProductRepository(apiService: mockApi);

      await repo.initialize();

      final raw = pendingBox.get('prod_legacy_01');
      expect(raw, isNotNull);
      final op = OfflineOperation.fromPendingString(raw!, 'prod_legacy_01');
      expect(op.id, equals('prod_legacy_01'));
      expect(op.action, equals('CREATE'));
      expect(op.status, equals(OfflineOperation.statusPending));
      // Re-encoded as valid JSON
      expect(raw.trim().startsWith('{'), isTrue);
    });

    test('Malformed modern JSON queue records throw FormatException and fail fast', () {
      const corruptJson = '{"id": "op_corrupted", "action": "CREATE", "product_id":';
      expect(
        () => OfflineOperation.fromPendingString(corruptJson, 'op_corrupted'),
        throwsA(isA<FormatException>()),
      );

      const unclosedJson = '{"id": "op_unclosed", "action": "CREATE"';
      expect(
        () => OfflineOperation.fromPendingString(unclosedJson, 'op_unclosed'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
