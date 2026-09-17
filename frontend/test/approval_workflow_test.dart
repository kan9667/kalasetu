import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';

class FailingApiService extends MockApiService {
  bool throwConflict = false;

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    if (throwConflict) {
      throw StaleRevisionException('Revision 1 is stale; current is 2');
    }
    return super.approveAndPublishProduct(
      productId,
      revision: revision,
      contentHash: contentHash,
      idempotencyKey: idempotencyKey,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('approval_workflow_test');
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

  group('Artisan Approval & Publishing Workflow', () {
    test('toBackendJson strictly forces status: draft and never publishes directly', () {
      final product = Product(
        id: 'p1',
        title: 'Terracotta Vase',
        description: 'Handmade vase',
        price: 450.0,
        photoPath: '/tmp/vase.jpg',
        category: 'Pottery',
        status: ProductStatus.live, // Even if client-side status is live
      );

      final backendPayload = product.toBackendJson(artisanId: 'artisan_1');
      expect(backendPayload['status'], 'draft',
          reason: 'Client mutations must strictly be drafts on backend boundary');
    });

    test('addProduct writes draft locally and calls createProduct', () async {
      final mockApi = FailingApiService();
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'p_test_1',
        title: 'Blue Pottery Plate',
        description: 'Authentic Jaipur blue pottery',
        price: 750.0,
        photoPath: '/tmp/plate.jpg',
        category: 'Blue Pottery',
      );

      final result = await repo.addProduct(product, isOnline: true);
      expect(result.status, ProductStatus.draft);

      final saved = repo.getProductById('p_test_1');
      expect(saved, isNotNull);
      expect(saved!.status, ProductStatus.draft);
    });

    test('approveAndPublishProduct publishes successfully when online', () async {
      final mockApi = FailingApiService();
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'p_publish_1',
        title: 'Brass Diya',
        description: 'Traditional etched diya',
        price: 350.0,
        photoPath: '/tmp/diya.jpg',
        category: 'Metal Craft',
        revision: 1,
        contentHash: 'hash_diya_123',
      );

      await repo.addProduct(product, isOnline: true);
      final published = await repo.approveAndPublishProduct(
        'p_publish_1',
        revision: 1,
        contentHash: 'hash_diya_123',
        isOnline: true,
      );

      expect(published.status, ProductStatus.published);
      expect(published.approvedRevision, 1);
      expect(published.approvedAt, isNotNull);
      expect(published.publishedAt, isNotNull);

      final pendingBox = Hive.box<String>('pending_sync_box');
      expect(pendingBox.containsKey('p_publish_1'), isFalse);
    });

    test('approveAndPublishProduct propagates StaleRevisionException on 409 conflict', () async {
      final mockApi = FailingApiService()..throwConflict = true;
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'p_conflict_1',
        title: 'Madhubani Painting',
        description: 'Folk art on handmade paper',
        price: 1200.0,
        photoPath: '/tmp/madhubani.jpg',
        category: 'Painting',
        revision: 1,
        contentHash: 'stale_hash',
      );

      await repo.addProduct(product, isOnline: true);

      expect(
        () async => await repo.approveAndPublishProduct(
          'p_conflict_1',
          revision: 1,
          contentHash: 'stale_hash',
          isOnline: true,
        ),
        throwsA(isA<StaleRevisionException>()),
      );
    });

    test('approveAndPublishProduct queues APPROVE_PUBLISH operation when offline', () async {
      final mockApi = FailingApiService();
      final repo = ProductRepository(apiService: mockApi);

      final product = Product(
        id: 'p_offline_pub',
        title: 'Wooden Elephant',
        description: 'Carved rosewood elephant',
        price: 850.0,
        photoPath: '/tmp/elephant.jpg',
        category: 'Woodcraft',
        revision: 1,
        contentHash: 'elephant_hash',
      );

      await repo.addProduct(product, isOnline: false);
      final approved = await repo.approveAndPublishProduct(
        'p_offline_pub',
        revision: 1,
        contentHash: 'elephant_hash',
        isOnline: false,
      );

      expect(approved.status, ProductStatus.pendingApprovalSync);
      expect(approved.approvedAt, isNull);
      expect(approved.publishedAt, isNull);
      expect(approved.approvedRevision, isNull);

      final ops = repo.getAllOperations().where((o) => o.productId == 'p_offline_pub').toList();
      expect(ops.isNotEmpty, isTrue);
      final pubOp = ops.firstWhere((o) => o.action == OfflineOperation.actionApprovePublish);
      expect(pubOp.action, OfflineOperation.actionApprovePublish);
      expect(pubOp.revision, 1);
      expect(pubOp.contentHash, 'elephant_hash');
    });
  });
}
