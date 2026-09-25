import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/storage/private_media_cache.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

class DelayedTokens extends SecureTokenStorage {
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> getToken() {
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
  }
}

class InterceptableApiService extends MockApiService {
  final List<String?> receivedIdempotencyKeys = [];
  final List<String> receivedPublishCalls = [];
  void Function()? onBeforeCreateReturn;
  void Function()? onBeforePublishReturn;

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    receivedIdempotencyKeys.add(idempotencyKey);
    final created = product.copyWith(
      id: product.id.isEmpty ? 'prod_created' : product.id,
      status: ProductStatus.draft,
      revision: 1,
    );
    onBeforeCreateReturn?.call();
    return created;
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    receivedIdempotencyKeys.add(idempotencyKey);
    receivedPublishCalls.add(productId);
    final published = Product(
      id: productId,
      title: 'Published Item',
      titleHi: 'प्रकाशित वस्तु',
      description: 'Desc',
      photoPath: '/mock.jpg',
      category: 'craft',
      price: 500,
      status: ProductStatus.live,
      revision: revision,
      contentHash: contentHash,
      approvedRevision: revision,
      publishedAt: DateTime.now(),
      approvedAt: DateTime.now(),
      approvedByArtisanId: 'artisan_test',
    );
    onBeforePublishReturn?.call();
    return published;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_boundary_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Deterministic Session Boundary Regressions', () {
    test('1. Uninitialized session: no protected dispatch', () async {
      // Invariant: Fail closed when session initialization is incomplete (auth_box unopened)
      expect(ActiveSessionManager.isSessionReady(), isFalse);

      final tokens = DelayedTokens();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://fixture.invalid',
        tokenStorage: tokens,
      );

      bool handlerExecuted = false;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handlerExecuted = true;
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
      }));

      DioException? capturedException;
      try {
        await dio.get('/api/v1/products');
      } on DioException catch (e) {
        capturedException = e;
      }

      dio.close();
      expect(handlerExecuted, isFalse, reason: 'Request must never dispatch when session is uninitialized');
      expect(capturedException, isNotNull);
      expect(capturedException!.error, isA<StateError>());
      expect((capturedException.error as StateError).message, contains('auth_box not initialized'));
    });

    test('2. Simulation/logout during token retrieval suppresses authorization', () async {
      final box = await Hive.openBox('auth_box');
      await box.put('is_authenticated', true);
      await box.put('user_id', 'artisan_orig');

      final tokens = DelayedTokens();
      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://fixture.invalid',
        tokenStorage: tokens,
      );

      String? authorizationHeader;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        authorizationHeader = options.headers['Authorization'] as String?;
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
      }));

      final request = dio.get('/api/v1/products');
      await tokens.started.future;

      // User switches to NGO simulation during asynchronous token retrieval
      await box.put('is_ngo_simulation', true);
      await box.put('is_authenticated', false);
      ActiveSessionManager.bumpSessionGeneration();

      tokens.result.complete('RETAINED_ARTISAN_TOKEN');

      try {
        await request;
      } on DioException {
        // Local rejection acceptable
      }

      dio.close();
      expect(
        authorizationHeader,
        isNull,
        reason: 'Bearer credentials must be completely stripped if session switched to simulation during token read',
      );
    });

    test('3. Artisan A -> artisan B during queue execution halts and preserves Artisan A work', () async {
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_A');

      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      final productsBox = await Hive.openBox<Product>('products_box');

      // Create a queued create operation owned by Artisan A
      final opA = OfflineOperation(
        id: 'op_artisan_A_create',
        action: OfflineOperation.actionCreate,
        productId: 'prod_A_1',
        owner: 'artisan_A',
        backend: ApiConfig.baseUrl,
        idempotencyKey: 'idemp_A_1',
        status: OfflineOperation.statusPending,
        payloadSnapshot: {
          'id': 'prod_A_1',
          'title': 'Artisan A Item',
          'title_hi': 'कारीगर ए वस्तु',
          'description': 'Desc',
          'photo_path': '/photo.jpg',
          'category': 'craft',
          'price': 400.0,
          'status': 'draft',
          'revision': 0,
        },
      );
      await pendingBox.put(opA.id, opA.toPendingString());

      // Active session switches to Artisan B before queue drain runs
      await authBox.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();

      final apiService = InterceptableApiService();
      final repo = ProductRepository(apiService: apiService);
      await repo.initialize();

      // Drain queue under Artisan B session
      final synced = await repo.syncPendingQueue();

      expect(synced, 0, reason: 'Artisan B must not execute Artisan A queued operations');
      expect(apiService.receivedIdempotencyKeys, isEmpty);
      expect(productsBox.isEmpty, isTrue, reason: 'Products box must remain empty for Artisan B');

      // Verify Artisan A's operation is preserved intact
      final rawOp = pendingBox.get('op_artisan_A_create');
      expect(rawOp, isNotNull);
      final preservedOp = OfflineOperation.fromPendingString(rawOp.toString(), 'op_artisan_A_create');
      expect(preservedOp.status, OfflineOperation.statusPending);
      expect(preservedOp.owner, 'artisan_A');
    });

    test('4. Session change between server success and local response application halts and preserves op', () async {
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_flaky_session');

      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      final productsBox = await Hive.openBox<Product>('products_box');

      final op = OfflineOperation(
        id: 'op_flaky_session_create',
        action: OfflineOperation.actionCreate,
        productId: 'prod_flaky_1',
        owner: 'artisan_flaky_session',
        backend: ApiConfig.baseUrl,
        idempotencyKey: 'idemp_flaky_1',
        status: OfflineOperation.statusPending,
        payloadSnapshot: {
          'id': 'prod_flaky_1',
          'title': 'Flaky Session Item',
          'title_hi': 'कारीगर वस्तु',
          'description': 'Desc',
          'photo_path': '/photo.jpg',
          'category': 'craft',
          'price': 300.0,
          'status': 'draft',
          'revision': 0,
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      final apiService = InterceptableApiService();
      // Right before createProduct returns its response, simulate session change (e.g. logout)
      apiService.onBeforeCreateReturn = () {
        ActiveSessionManager.bumpSessionGeneration();
      };

      final repo = ProductRepository(apiService: apiService);
      await repo.initialize();

      final synced = await repo.syncPendingQueue();

      expect(synced, 0, reason: 'Response application must abort when session generation changes');
      expect(productsBox.containsKey('prod_flaky_1'), isFalse, reason: 'Local state must not be committed for invalidated session');

      // Operation must be preserved as statusPending with lease cleared for safe replay
      final rawOp = pendingBox.get('op_flaky_session_create');
      final preservedOp = OfflineOperation.fromPendingString(rawOp.toString(), 'op_flaky_session_create');
      expect(preservedOp.status, OfflineOperation.statusPending);
      expect(preservedOp.leaseExpiresAt, isNull);
    });

    test('5. Session change during media streaming aborts download and cleans up staging file', () async {
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_streamer');

      final tokens = DelayedTokens();
      tokens.result.complete('STREAM_TOKEN');

      final cacheDir = Directory('${tempDir.path}/media_cache');
      await cacheDir.create(recursive: true);

      // Create a mock Dio that returns a 2-chunk stream with session mutation between chunks
      final mockDio = Dio();
      final streamController = StreamController<Uint8List>();

      mockDio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final responseBody = ResponseBody(
          streamController.stream,
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: responseBody,
        ));
      }));

      final cache = PrivateMediaCache(
        cacheDir: cacheDir,
        tokenStorage: tokens,
        dio: mockDio,
      );
      cache.updateSession(accountId: 'artisan_streamer');

      // Initiate download
      final downloadFuture = cache.downloadAndCacheMedia(mediaId: 'stream_media_1');

      // Push chunk 1
      streamController.add(Uint8List.fromList([1, 2, 3, 4]));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Bump session generation mid-stream
      ActiveSessionManager.bumpSessionGeneration();

      // Push chunk 2
      streamController.add(Uint8List.fromList([5, 6, 7, 8]));
      await streamController.close();

      Object? capturedException;
      try {
        await downloadFuture;
      } catch (e) {
        capturedException = e;
      }

      expect(capturedException, isA<SessionChangedException>());
      expect(
        (capturedException as SessionChangedException).message,
        contains('Session changed during streaming'),
      );

      // Verify staging directory is clean (staging file deleted)
      final stagingDir = Directory('${cacheDir.path}/staging');
      if (stagingDir.existsSync()) {
        final stagingFiles = stagingDir.listSync().where((e) => e.path.endsWith('.tmp')).toList();
        expect(stagingFiles, isEmpty, reason: 'Staging file must be cleaned up on session change');
      }

      // Verify final cache does not have partial/corrupted media
      final isCached = await cache.isCached('stream_media_1');
      expect(isCached, isFalse);
    });

    test('6. Restart/retry preserves outbox idempotency key without duplicate publication', () async {
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_idemp');

      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      final productsBox = await Hive.openBox<Product>('products_box');

      const fixedIdempotencyKey = 'idemp_key_deterministic_publish_999';
      const prodId = 'prod_publish_deterministic';

      final product = Product(
        id: prodId,
        title: 'Deterministic Item',
        titleHi: 'वस्तु',
        description: 'Desc',
        photoPath: '/photo.jpg',
        category: 'craft',
        price: 500,
        status: ProductStatus.pendingApprovalSync,
        revision: 2,
        contentHash: 'a' * 64,
      );
      await productsBox.put(prodId, product);

      final op = OfflineOperation(
        id: 'op_publish_deterministic',
        action: OfflineOperation.actionApprovePublish,
        productId: prodId,
        owner: 'artisan_idemp',
        backend: ApiConfig.baseUrl,
        idempotencyKey: fixedIdempotencyKey,
        status: OfflineOperation.statusPending,
        revision: 2,
        contentHash: 'a' * 64,
        // Expired lease simulating prior app crash during execution
        leaseExpiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        payloadSnapshot: {
          'revision': 2,
          'content_hash': 'a' * 64,
        },
      );
      await pendingBox.put(op.id, op.toPendingString());

      // Simulate app startup / restart: initialize repository
      final apiService = InterceptableApiService();
      final repo = ProductRepository(apiService: apiService);
      await repo.initialize();

      // Drain queue
      final synced = await repo.syncPendingQueue();

      expect(synced, 1);
      expect(apiService.receivedIdempotencyKeys, [fixedIdempotencyKey],
          reason: 'Retry must send the exact persisted idempotency key');
      expect(apiService.receivedPublishCalls, [prodId]);

      // Verify product is updated to live locally
      final updatedProduct = productsBox.get(prodId);
      expect(updatedProduct?.status, ProductStatus.live);

      // Verify operation is marked completed and has no lingering lease
      final rawOp = pendingBox.get('op_publish_deterministic');
      if (rawOp != null) {
        final finishedOp = OfflineOperation.fromPendingString(rawOp.toString(), 'op_publish_deterministic');
        expect(finishedOp.status, OfflineOperation.statusCompleted);
        expect(finishedOp.leaseExpiresAt, isNull);
      }
    });
  });
}
