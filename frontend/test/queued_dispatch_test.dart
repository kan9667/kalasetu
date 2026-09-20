import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/network/request_session_context.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

class ControlledTokenStorage extends SecureTokenStorage {
  Completer<void> entered = Completer<void>();
  Completer<void> release = Completer<void>();
  final String tokenToReturn;

  ControlledTokenStorage({this.tokenToReturn = 'TOKEN_A'});

  void reset() {
    entered = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<String?> getToken() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return tokenToReturn;
  }
}

class TrackingHttpAdapter implements HttpClientAdapter {
  int dispatchedCalls = 0;
  final List<RequestOptions> executedRequests = [];
  ResponseBody Function(RequestOptions options)? responseHandler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    dispatchedCalls++;
    executedRequests.add(options);
    if (responseHandler != null) {
      return responseHandler!(options);
    }
    final jsonBytes = utf8.encode(jsonEncode({
      'id': 'prod_test',
      'title': 'Test Item',
      'title_hi': 'परीक्षण',
      'description': 'Description',
      'category': 'Pottery',
      'price': 500,
      'status': 'draft',
      'revision': 1,
      'content_hash': 'a' * 64,
      'media_id': 'med_123',
      'original_media_id': 'med_orig_123',
      'sha256_checksum': 'c' * 64,
    }));
    return ResponseBody.fromBytes(
      jsonBytes,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class PausingInterceptor extends Interceptor {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    handler.next(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box authBox;
  late Box<Product> productsBox;
  late Box<String> pendingBox;
  const backendA = 'http://127.0.0.1:8000';
  const backendB = 'http://127.0.0.1:9000';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('queued_dispatch_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());

    authBox = await Hive.openBox('auth_box');
    productsBox = await Hive.openBox<Product>('products_box');
    pendingBox = await Hive.openBox<String>('pending_sync_box');

    await authBox.putAll({
      'is_authenticated': true,
      'user_id': 'artisan_A',
      'phone_number': '+919876543210',
    });
    SecureTokenStorage.resetForTesting();
    ApiConfig.setBaseUrl(backendA);
  });

  tearDown(() async {
    SecureTokenStorage.resetForTesting();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Queued Dispatch Boundary & Zero Transport Dispatch Regressions', () {
    test('transition before AuthInterceptor starts blocks dispatch with zero wire calls', () async {
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      // Queue an operation belonging to artisan_A
      final op = OfflineOperation(
        id: 'op_create_a',
        productId: 'prod_a',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'idem_op_a',
        payloadSnapshot: {
          'id': 'prod_a',
          'title': 'Vase A',
          'description': 'Desc A',
          'price': 500,
          'status': 'draft',
          'category': 'Pottery',
          'materials_cost': 100,
          'labor_hours': 2,
          'hourly_rate': 100,
          'packaging_cost': 50,
          'platform_fee_percent': 5,
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Switch active session to artisan_B BEFORE sync starts
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      final synced = await repo.syncPendingQueue();
      expect(synced, 0);
      expect(adapter.dispatchedCalls, 0, reason: 'Zero wire calls must be dispatched for mismatched owner');

      // Operation remains safely pending under artisan_A without retryCount bump
      final rawOp = pendingBox.get('op_create_a');
      expect(rawOp, isNotNull);
      final savedOp = OfflineOperation.fromPendingString(rawOp!, 'op_create_a');
      expect(savedOp.owner, 'artisan_A');
      expect(savedOp.status, OfflineOperation.statusPending);
      expect(savedOp.retryCount, 0);
    });

    test('transition during token retrieval rejects mutation with zero transport dispatch', () async {
      final controlledStorage = ControlledTokenStorage();
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        tokenStorage: controlledStorage,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      final op = OfflineOperation(
        id: 'op_token_race',
        productId: 'prod_race',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'idem_token_race',
        payloadSnapshot: {
          'id': 'prod_race',
          'title': 'Pot',
          'description': 'Handmade',
          'price': 600,
          'status': 'draft',
          'category': 'Pottery',
          'materials_cost': 100,
          'labor_hours': 2,
          'hourly_rate': 100,
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Start queue sync in background
      final syncFuture = repo.syncPendingQueue();

      // Wait until interceptor enters token retrieval
      await controlledStorage.entered.future;

      // While token retrieval is paused, transition to NGO simulation
      await authBox.put('is_ngo_simulation', true);
      await authBox.put('is_authenticated', false);

      // Release token retrieval
      controlledStorage.release.complete();

      final synced = await syncFuture;
      expect(synced, 0);
      expect(adapter.dispatchedCalls, 0, reason: 'Zero wire calls must be dispatched when session transitions during token retrieval');

      // Invariant: operation lease reverted to statusPending, retryCount not incremented, payload preserved
      final savedOp = OfflineOperation.fromPendingString(pendingBox.get('op_token_race')!, 'op_token_race');
      expect(savedOp.status, OfflineOperation.statusPending);
      expect(savedOp.retryCount, 0);
      expect(savedOp.idempotencyKey, 'idem_token_race');
      expect(savedOp.payloadSnapshot, isNotNull);
    });

    test('account change during token retrieval rejects with zero transport dispatch', () async {
      final controlledStorage = ControlledTokenStorage();
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        tokenStorage: controlledStorage,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      final op = OfflineOperation(
        id: 'op_account_switch',
        productId: 'prod_acc',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'idem_acc_switch',
        payloadSnapshot: {
          'id': 'prod_acc',
          'title': 'Bowl',
          'description': 'Clay',
          'price': 300,
          'status': 'draft',
          'category': 'Pottery',
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      final syncFuture = repo.syncPendingQueue();
      await controlledStorage.entered.future;

      // Switch account to artisan_C and bump generation
      await authBox.put('user_id', 'artisan_C');
      ActiveSessionManager.bumpSessionGeneration();

      controlledStorage.release.complete();

      final synced = await syncFuture;
      expect(synced, 0);
      expect(adapter.dispatchedCalls, 0);

      final savedOp = OfflineOperation.fromPendingString(pendingBox.get('op_account_switch')!, 'op_account_switch');
      expect(savedOp.status, OfflineOperation.statusPending);
      expect(savedOp.retryCount, 0);
    });

    test('protected mutation without identity context fails closed before transport', () async {
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );

      // Attempt protected POST directly without extra session context
      expect(
        () => dio.post('/api/v1/products', data: {'title': 'Direct Test'}),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<SessionExpiredException>(),
        )),
      );

      expect(adapter.dispatchedCalls, 0, reason: 'Protected mutation without context must never hit transport');
    });

    test('outgoing request URI origin mismatch against expected backend is rejected before transport', () async {
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );

      // Try sending request targeting backendB when operation expected backendA
      expect(
        () => dio.post(
          '$backendB/api/v1/products',
          data: {'title': 'Cross Origin Test'},
          options: Options(
            extra: {
              'expected_user_id': 'artisan_A',
              'expected_session_gen': 0,
              'expected_backend_origin': backendA,
            },
          ),
        ),
        throwsA(isA<DioException>().having(
          (e) => e.error,
          'error',
          isA<SessionExpiredException>(),
        )),
      );

      expect(adapter.dispatchedCalls, 0, reason: 'Origin mismatch must reject before transport');
    });

    test('conflict recovery race: session invalidation halts before getProduct and preserves operation', () async {
      final adapter = TrackingHttpAdapter();
      bool throwConflictOnce = true;
      adapter.responseHandler = (options) {
        if (throwConflictOnce && options.method == 'PUT' && options.path.contains('/api/v1/products/prod_conflict')) {
          throwConflictOnce = false;
          final errBody = utf8.encode(jsonEncode({'detail': 'Revision conflict: current is 3'}));
          return ResponseBody.fromBytes(
            errBody,
            409,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        final jsonBytes = utf8.encode(jsonEncode({
          'id': 'prod_conflict',
          'title': 'Refreshed Item',
          'description': 'Refreshed Desc',
          'price': 500,
          'status': 'draft',
          'revision': 3,
          'content_hash': 'f' * 64,
        }));
        return ResponseBody.fromBytes(
          jsonBytes,
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      };

      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      final product = Product(
        id: 'prod_conflict',
        title: 'Conflict Item',
        description: 'Desc',
        price: 500,
        photoPath: '',
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 2,
      );
      await productsBox.put(product.id, product);

      final op = OfflineOperation(
        id: 'op_conflict',
        productId: product.id,
        action: OfflineOperation.actionUpdate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'idem_conflict_op',
        payloadSnapshot: product.toJson(),
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Let update fail with 409, but before getProduct runs, invalidate session
      dio.interceptors.add(InterceptorsWrapper(
        onError: (err, handler) {
          if (err.response?.statusCode == 409) {
            // Session transitions to unauthenticated right upon conflict detection
            authBox.put('is_authenticated', false);
          }
          handler.next(err);
        },
      ));

      final synced = await repo.syncPendingQueue();
      expect(synced, 0);

      // The queued operation must be preserved without incrementing retryCount
      final savedOp = OfflineOperation.fromPendingString(pendingBox.get('op_conflict')!, 'op_conflict');
      expect(savedOp.status, OfflineOperation.statusPending);
      expect(savedOp.retryCount, 0, reason: 'Session invalidation during conflict recovery must not bump retryCount');

      // Local products cache must NOT have been updated with replacement data
      final localProd = productsBox.get('prod_conflict');
      expect(localProd?.revision, 2, reason: 'Cache must not be mutated under invalidated session');
    });

    test('all 7 queued mutation types execute and dispatch with bound identity context', () async {
      final adapter = TrackingHttpAdapter();
      final capturedExtras = <String, Map<String, dynamic>>{};

      // Create dummy file for media upload
      final mediaFile = File('${tempDir.path}/test_media.jpg');
      final dummyBytes = [1, 2, 3, 4, 5];
      mediaFile.writeAsBytesSync(dummyBytes);
      final dummyChecksum = sha256.convert(dummyBytes).toString();

      adapter.responseHandler = (options) {
        capturedExtras[options.path] = Map<String, dynamic>.from(options.extra);
        final jsonBytes = utf8.encode(jsonEncode({
          'id': 'prod_all_types',
          'title': 'All Types Item',
          'description': 'Desc',
          'price': 700,
          'status': 'draft',
          'revision': 2,
          'content_hash': 'e' * 64,
          'media_id': 'med_all_789',
          'original_media_id': 'med_all_orig_789',
          'sha256_checksum': dummyChecksum,
        }));
        return ResponseBody.fromBytes(
          jsonBytes,
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      };

      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      // Seed a product
      final product = Product(
        id: 'prod_all_types',
        title: 'All Types',
        description: 'Desc',
        price: 700,
        photoPath: mediaFile.path,
        category: 'Pottery',
        status: ProductStatus.draft,
        revision: 1,
        contentHash: 'e' * 64,
      );
      await productsBox.put(product.id, product);

      // Queue all 7 mutation types with explicit provenance
      final actions = [
        OfflineOperation(
          id: 'op_1_create',
          productId: 'prod_all_types',
          action: OfflineOperation.actionCreate,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_create_7',
          payloadSnapshot: product.toJson(),
        ),
        OfflineOperation(
          id: 'op_2_upload',
          productId: 'prod_all_types',
          action: OfflineOperation.actionMediaUpload,
          mediaLocalId: mediaFile.path,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_upload_7',
          payloadSnapshot: {'media_sha256': dummyChecksum},
        ),
        OfflineOperation(
          id: 'op_3_attach',
          productId: 'prod_all_types',
          action: OfflineOperation.actionAttachMedia,
          mediaId: 'med_all_789',
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_attach_7',
        ),
        OfflineOperation(
          id: 'op_4_update',
          productId: 'prod_all_types',
          action: OfflineOperation.actionUpdate,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_update_7',
          payloadSnapshot: product.toJson(),
        ),
        OfflineOperation(
          id: 'op_5_approve',
          productId: 'prod_all_types',
          action: OfflineOperation.actionApprovePublish,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_approve_7',
          revision: 2,
          contentHash: 'e' * 64,
        ),
        OfflineOperation(
          id: 'op_6_unpub',
          productId: 'prod_all_types',
          action: OfflineOperation.actionUnpublish,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_unpub_7',
          revision: 2,
          contentHash: 'e' * 64,
        ),
        OfflineOperation(
          id: 'op_7_del',
          productId: 'prod_all_types',
          action: OfflineOperation.actionDelete,
          owner: 'artisan_A',
          backend: backendA,
          idempotencyKey: 'idem_del_7',
        ),
      ];

      for (final op in actions) {
        await pendingBox.put(op.id, op.toPendingString());
      }

      final synced = await repo.syncPendingQueue();
      expect(synced, 7);

      // Verify that every single dispatched request carried expected identity context
      expect(capturedExtras.isNotEmpty, isTrue);
      for (final entry in capturedExtras.entries) {
        final extra = entry.value;
        expect(extra['expected_user_id'], 'artisan_A', reason: 'Context in ${entry.key} must carry artisan_A');
        expect(extra['expected_backend_origin'], backendA, reason: 'Context in ${entry.key} must carry backendA');
      }
    });

    test('successful replay after restoring original account and backend', () async {
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      final op = OfflineOperation(
        id: 'op_replay_a',
        productId: 'prod_replay',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'idem_replay_a',
        payloadSnapshot: {
          'id': 'prod_replay',
          'title': 'Replay Item',
          'description': 'Replay Desc',
          'price': 450,
          'status': 'draft',
          'category': 'Pottery',
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Switch to artisan_B -> queue sync blocks op
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      var synced = await repo.syncPendingQueue();
      expect(synced, 0);
      expect(adapter.dispatchedCalls, 0);

      // Restore session to artisan_A on backendA
      await authBox.put('user_id', 'artisan_A');
      ActiveSessionManager.bumpSessionGeneration();

      synced = await repo.syncPendingQueue();
      expect(synced, 1);
      expect(adapter.dispatchedCalls, 1);

      // Completed operation without dependents is purged according to outbox purge policy
      expect(pendingBox.get('op_replay_a'), isNull);
    });

    test('backend switch during token read must prevent transport', () async {
      final storage = ControlledTokenStorage();
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(baseUrl: backendA, tokenStorage: storage, adapter: adapter);
      addTearDown(() => dio.close(force: true));
      final ctx = RequestSessionContext.capture();
      final result = dio.post('/api/v1/products', data: {'title': 'A draft'},
        options: Options(extra: ctx.toExtra())).then<Object?>((r) => r, onError: (Object e) => e);
      await storage.entered.future;
      ApiConfig.setBaseUrl(backendB);
      storage.release.complete();
      await result;
      expect(adapter.dispatchedCalls, 0, reason: 'Active backend changed; stale request must not dispatch');
    });

    test('explicit client URL must not override queued backend provenance', () async {
      final storage = ControlledTokenStorage();
      storage.release.complete();
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(baseUrl: backendB, tokenStorage: storage, adapter: adapter);
      addTearDown(() => dio.close(force: true));
      final repo = ProductRepository(apiService: HttpApiService(baseUrl: backendB, dio: dio));
      final op = OfflineOperation(
        id: 'queued_a',
        productId: 'draft_a',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'original_key',
        payloadSnapshot: {
          'id': 'draft_a',
          'title': 'A only',
          'description': 'private',
          'price': 500,
          'status': 'draft',
          'category': 'Pottery',
        },
      );
      await pendingBox.put(op.id, op.toPendingString());
      await repo.syncPendingQueue();
      expect(adapter.dispatchedCalls, 0, reason: 'A operation must not be redirected to explicit backend B');
      expect(pendingBox.containsKey(op.id), isTrue);
    });

    test('account-switch race: pause after repository session check but before AuthInterceptor starts', () async {
      final pauser = PausingInterceptor();
      final adapter = TrackingHttpAdapter();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: backendA,
        adapter: adapter,
      );
      dio.interceptors.insert(0, pauser);
      addTearDown(() => dio.close(force: true));
      final apiService = HttpApiService(baseUrl: backendA, dio: dio);
      final repo = ProductRepository(apiService: apiService);

      final op = OfflineOperation(
        id: 'op_race_1',
        productId: 'prod_race_1',
        action: OfflineOperation.actionCreate,
        owner: 'artisan_A',
        backend: backendA,
        idempotencyKey: 'key_race_123',
        payloadSnapshot: {
          'id': 'prod_race_1',
          'title': 'Race Item',
          'description': 'Race Desc',
          'price': 500,
          'status': 'draft',
          'category': 'Pottery',
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Start queue sync in background
      final syncFuture = repo.syncPendingQueue();

      // Wait until repository session check passes and PausingInterceptor halts execution
      await pauser.entered.future;

      // Switch account before AuthInterceptor starts
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      // Release PausingInterceptor to allow request into AuthInterceptor
      pauser.release.complete();

      final synced = await syncFuture;
      expect(synced, 0);

      // Assert zero transport requests
      expect(adapter.dispatchedCalls, 0, reason: 'Zero transport calls must occur after account switch');

      // Assert unchanged queued identity, backend, and idempotency key
      final rawPreserved = pendingBox.get(op.id);
      expect(rawPreserved, isNotNull);
      final preservedOp = OfflineOperation.fromPendingString(rawPreserved!, op.id);
      expect(preservedOp.owner, 'artisan_A');
      expect(preservedOp.backend, backendA);
      expect(preservedOp.idempotencyKey, 'key_race_123');
      expect(preservedOp.retryCount, 0);
      expect(preservedOp.status, OfflineOperation.statusPending);
    });
  });
}
