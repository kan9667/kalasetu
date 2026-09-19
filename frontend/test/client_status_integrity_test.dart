import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
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
    );
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
  });
}
