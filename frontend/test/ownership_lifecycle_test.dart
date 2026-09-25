import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

class ProbeApi extends MockApiService {
  int calls = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  bool delayFailure = false;
  bool delaySuccess = false;

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    calls++;
    if (delayFailure) {
      started.complete();
      await release.future;
      throw Exception('Simulated lost response');
    }
    if (delaySuccess) {
      started.complete();
      await release.future;
      return product.copyWith(status: ProductStatus.draft, revision: 1);
    }
    return product.copyWith(status: ProductStatus.draft, revision: 1);
  }
}

Product fixture() => Product(
      id: 'private_A',
      title: 'A private draft',
      titleHi: 'वस्तु',
      description: 'Private',
      photoPath: '/photo.jpg',
      category: 'craft',
      price: 400,
      status: ProductStatus.draft,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Box auth;
  late Box<String> pending;
  late Box<Product> products;
  late String originalUrl;

  setUp(() async {
    originalUrl = ApiConfig.baseUrl;
    dir = await Directory.systemTemp.createTemp('ownership_fixture_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    auth = await Hive.openBox('auth_box');
    await auth.putAll({'is_authenticated': true, 'user_id': 'artisan_A'});
    pending = await Hive.openBox<String>('pending_sync_box');
    products = await Hive.openBox<Product>('products_box');
  });

  tearDown(() async {
    ApiConfig.setBaseUrl(originalUrl);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('legacy ownerless operation cannot dispatch as new artisan', () async {
    final old = OfflineOperation(
      id: 'legacy_create',
      action: OfflineOperation.actionCreate,
      productId: 'private_A',
      idempotencyKey: 'old_key',
      payloadSnapshot: fixture().toJson(),
    );
    await pending.put(old.id, old.toPendingString());
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();
    final api = ProbeApi();
    await ProductRepository(apiService: api).syncPendingQueue();
    expect(api.calls, 0,
        reason: 'Unknown legacy ownership must be recovered or quarantined, never assumed to belong to current artisan');
    expect(pending.containsKey(old.id), isTrue);
  });

  test('online failure after account switch preserves original operation owner', () async {
    final api = ProbeApi()..delayFailure = true;
    final repo = ProductRepository(apiService: api);
    await repo.initialize();
    final adding = repo.addProduct(fixture());
    await api.started.future;
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();
    api.release.complete();
    await adding;
    final op = OfflineOperation.fromPendingString(pending.values.single, pending.keys.single as String);
    expect(op.owner, 'artisan_A',
        reason: 'A request started by A cannot become owned by B after a lost response');
  });

  test('queued operation cannot migrate to a different backend', () async {
    ApiConfig.setBaseUrl('https://backend-a.invalid');
    final api = ProbeApi();
    final repo = ProductRepository(apiService: api);
    await repo.addProduct(fixture(), isOnline: false);
    ApiConfig.setBaseUrl('https://backend-b.invalid');
    await repo.syncPendingQueue();
    expect(api.calls, 0,
        reason: 'Backend affinity must be persisted at enqueue time, not captured only when draining');
  });

  test('returning to correct account and backend safely resumes work', () async {
    ApiConfig.setBaseUrl('https://backend-a.invalid');
    final api = ProbeApi();
    final repo = ProductRepository(apiService: api);
    await repo.addProduct(fixture(), isOnline: false);

    // Switch account to artisan_B and backend to backend-b
    await auth.put('user_id', 'artisan_B');
    ApiConfig.setBaseUrl('https://backend-b.invalid');
    ActiveSessionManager.bumpSessionGeneration();

    // Sync under artisan_B on backend-b must skip artisan_A's operation
    await repo.syncPendingQueue();
    expect(api.calls, 0, reason: 'artisan_A operations on backend-a must not execute under artisan_B on backend-b');

    // Switch back to artisan_A and backend-a
    await auth.put('user_id', 'artisan_A');
    ApiConfig.setBaseUrl('https://backend-a.invalid');
    ActiveSessionManager.bumpSessionGeneration();

    // Now sync should successfully process the queued operation
    final synced = await repo.syncPendingQueue();
    expect(synced, 1, reason: 'Returning to initiating account and backend resumes work safely');
    expect(api.calls, 1);
  });

  test('migration preserves payloads, dependencies, and idempotency keys during provenance recovery', () async {
    const originalKey1 = 'idem_key_create_123';
    const originalKey2 = 'idem_key_upload_456';
    final createOp = OfflineOperation(
      id: 'op_legacy_root',
      action: OfflineOperation.actionCreate,
      productId: 'prod_tree',
      idempotencyKey: originalKey1,
      payloadSnapshot: {
        'id': 'prod_tree',
        'title': 'Carved Tree',
        'artisan_id': 'artisan_woodcraft',
      },
    );
    final uploadOp = OfflineOperation(
      id: 'op_legacy_dep',
      action: OfflineOperation.actionMediaUpload,
      productId: 'prod_tree',
      idempotencyKey: originalKey2,
      dependsOnOpId: createOp.id,
      mediaLocalId: '/path/photo.jpg',
      backend: 'https://backend-a.invalid',
    );

    await pending.put(createOp.id, createOp.toPendingString());
    await pending.put(uploadOp.id, uploadOp.toPendingString());

    final repo = ProductRepository(apiService: MockApiService());
    await repo.initialize();

    final recoveredCreateRaw = pending.get(createOp.id);
    final recoveredUploadRaw = pending.get(uploadOp.id);
    expect(recoveredCreateRaw, isNotNull);
    expect(recoveredUploadRaw, isNotNull);

    final recoveredCreate = OfflineOperation.fromPendingString(recoveredCreateRaw!, createOp.id);
    final recoveredUpload = OfflineOperation.fromPendingString(recoveredUploadRaw!, uploadOp.id);

    // Provenance recovery verified
    expect(recoveredCreate.owner, 'artisan_woodcraft', reason: 'Owner recovered from payloadSnapshot');
    expect(recoveredUpload.owner, 'artisan_woodcraft', reason: 'Owner propagated from parent');
    expect(recoveredCreate.backend, 'https://backend-a.invalid', reason: 'Backend propagated from child');

    // Invariants preserved: payload snapshots, dependency IDs, idempotency keys
    expect(recoveredCreate.idempotencyKey, originalKey1);
    expect(recoveredUpload.idempotencyKey, originalKey2);
    expect(recoveredUpload.dependsOnOpId, createOp.id);
    expect(recoveredCreate.payloadSnapshot?['title'], 'Carved Tree');
  });

  test('late successful responses do not contaminate replacement account local state', () async {
    final api = ProbeApi()..delaySuccess = true;
    final repo = ProductRepository(apiService: api);
    await repo.initialize();

    final addingFuture = repo.addProduct(fixture(), isOnline: true);
    await api.started.future;

    // Switch account to artisan_B while request is in-flight
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();

    // Release probe to return successful response
    api.release.complete();
    await addingFuture;

    // The returned product must NOT be committed to artisan_B's products_box
    expect(products.containsKey('private_A'), isFalse,
        reason: 'Late online success from prior session must not contaminate replacement account cache');
  });
}
