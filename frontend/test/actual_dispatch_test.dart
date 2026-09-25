import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';

class Probe extends MockApiService {
  int creates = 0;
  @override
  Future<Product> createProduct(Product p, {String? artisanId, String? idempotencyKey}) async {
    creates++;
    return p.copyWith(revision: 1);
  }
}

class InitializationGate extends ProductRepository {
  final entered = Completer<void>();
  final release = Completer<void>();
  InitializationGate(ApiService api) : super(apiService: api);
  @override
  Future<void> initialize({DateTime? now}) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.initialize(now: now);
  }
}

class ControlledTokenStorage extends SecureTokenStorage {
  final entered = Completer<void>();
  final release = Completer<void>();
  final String tokenToReturn;

  ControlledTokenStorage({this.tokenToReturn = 'FIXTURE_TOKEN'});

  @override
  Future<String?> getToken() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return tokenToReturn;
  }
}

class MultiStageProbeApi extends MockApiService {
  int uploads = 0;
  int publishes = 0;
  void Function()? onUploadFinished;

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    uploads++;
    onUploadFinished?.call();
    final bytes = File(filePath).readAsBytesSync();
    final checksum = sha256.convert(bytes).toString();
    return {
      'media_id': 'med_valid_123',
      'sha256_checksum': checksum,
    };
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    publishes++;
    return Product(
      id: productId,
      title: 'Published item',
      titleHi: 'प्रकाशित वस्तु',
      description: 'Desc',
      photoPath: '/photo.jpg',
      category: 'craft',
      price: 500,
      status: ProductStatus.published,
      revision: revision,
      contentHash: contentHash,
    );
  }

  @override
  Future<Product> createProduct(Product p, {String? artisanId, String? idempotencyKey}) async {
    return p.copyWith(revision: 1, contentHash: 'b' * 64);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Box auth;
  late Box<Product> productsBox;
  late Box<String> pendingBox;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('actual_dispatch_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    auth = await Hive.openBox('auth_box');
    productsBox = await Hive.openBox<Product>('products_box');
    pendingBox = await Hive.openBox<String>('pending_sync_box');
    await auth.putAll({'is_authenticated': true, 'user_id': 'artisan_A'});
    SecureTokenStorage.resetForTesting();
    ApiConfig.setBaseUrl('http://127.0.0.1:8000');
  });

  tearDown(() async {
    SecureTokenStorage.resetForTesting();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('real product API client cannot use retained artisan token in simulation', () async {
    SecureTokenStorage.setForceMigrationFailureForTesting(true);
    await auth.putAll({'access_token': 'FIXTURE_ARTISAN_TOKEN', 'is_ngo_simulation': true, 'is_authenticated': false});
    final dio = Dio();
    final api = HttpApiService(baseUrl: 'https://fixture.invalid', dio: dio);
    String? authorization;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      authorization = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: []));
    }));
    try { await api.getProducts(); } on DioException { /* Safe local rejection allowed. */ }
    dio.close();
    expect(authorization, isNull, reason: 'HttpApiService must use the same simulation guard as the shared HTTP client');
  });

  test('account switch during repository initialization blocks online create dispatch', () async {
    final api = Probe();
    final repo = InitializationGate(api);
    final adding = repo.addProduct(Product(
      id: 'a_private',
      title: 'A draft',
      titleHi: 'वस्तु',
      description: 'Private',
      photoPath: '/photo.jpg',
      category: 'craft',
      price: 400,
      status: ProductStatus.draft,
    ));
    await repo.entered.future;
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();
    repo.release.complete();
    try { await adding; } catch (_) { /* Safe local rejection allowed. */ }
    expect(api.creates, 0, reason: 'Checking after the server response is too late to prevent dispatch under a changed session');

    // Operation must be preserved under original artisan_A identity
    final pendingOps = pendingBox.values.map((s) => OfflineOperation.fromPendingString(s, '')).toList();
    expect(pendingOps.length, 1);
    expect(pendingOps.first.owner, 'artisan_A');
  });

  test('account/backend change during token retrieval fails closed on HttpApiService', () async {
    final controlledStorage = ControlledTokenStorage(tokenToReturn: 'SECRET_ARTISAN_TOKEN');
    final dio = Dio();
    final api = HttpApiService(
      baseUrl: 'https://fixture.invalid',
      dio: dio,
      tokenStorage: controlledStorage,
    );

    String? dispatchedAuth;
    bool requestReachedTransport = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requestReachedTransport = true;
      dispatchedAuth = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: []));
    }));

    // Start request as artisan_A
    final requestFuture = api.getProducts();

    // Wait for token retrieval to enter
    await controlledStorage.entered.future;

    // While token retrieval is waiting, switch account to artisan_B
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();

    // Now release token retrieval
    controlledStorage.release.complete();

    // The request should fail closed with a SessionExpiredException / 401 DioException
    // and must not dispatch artisan_A's request with artisan_B's session
    expect(
      () async => await requestFuture,
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401)),
    );

    expect(requestReachedTransport, isFalse, reason: 'Request should be rejected before transport when session changes during token retrieval');
    expect(dispatchedAuth, isNull);
    dio.close();
  });

  test('session change between upload, attachment and publication preserves recoverable work under original identity', () async {
    final api = MultiStageProbeApi();
    final repo = ProductRepository(apiService: api);
    await repo.initialize();

    // Create a local dummy photo file
    final tempImageFile = File('${dir.path}/test_photo.jpg');
    final testBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46];
    await tempImageFile.writeAsBytes(testBytes);
    final expectedChecksum = sha256.convert(testBytes).toString();

    // When upload finishes, switch session to artisan_B
    api.onUploadFinished = () {
      auth.put('user_id', 'artisan_B');
      ActiveSessionManager.bumpSessionGeneration();
    };

    final product = Product(
      id: 'prod_multi_stage',
      title: 'Multi Stage',
      titleHi: 'बहु चरण',
      description: 'Description',
      photoPath: tempImageFile.path,
      category: 'craft',
      price: 500,
      status: ProductStatus.draft,
      reviewedMediaChecksum: expectedChecksum,
    );
    await productsBox.put(product.id, product);

    // Attempt approve and publish
    final result = await repo.approveAndPublishProduct(
      product.id,
      reviewedChecksum: expectedChecksum,
      isOnline: true,
    );

    // Online upload happened, but publish must have halted because session changed
    expect(api.uploads, 1);
    expect(api.publishes, 0, reason: 'Publish must not execute online after session changed');

    // Local result must be pendingApprovalSync with null approval metadata
    expect(result.status, ProductStatus.pendingApprovalSync);
    expect(result.approvedAt, isNull);
    expect(result.publishedAt, isNull);

    // Offline operations must be safely recorded under original artisan_A
    final ops = pendingBox.values.map((s) => OfflineOperation.fromPendingString(s, '')).toList();
    expect(ops.isNotEmpty, isTrue);
    for (final op in ops) {
      expect(op.owner, 'artisan_A', reason: 'All staged operations must retain initiating owner artisan_A');
    }
  });

  test('normal authenticated operation and safe recovery under original identity', () async {
    final api = MultiStageProbeApi();
    final repo = ProductRepository(apiService: api);
    await repo.initialize();

    // 1. Normal authenticated create
    final product = Product(
      id: 'prod_normal',
      title: 'Normal Item',
      titleHi: 'सामान्य वस्तु',
      description: 'Description',
      photoPath: '/photo.jpg',
      category: 'craft',
      price: 500,
      status: ProductStatus.draft,
    );

    final created = await repo.addProduct(product, isOnline: true);
    expect(created.revision, 1);

    // 2. Offline queued work for artisan_A
    final offlineProduct = product.copyWith(id: 'prod_offline_a', title: 'Offline draft');
    final offlineOp = OfflineOperation(
      action: OfflineOperation.actionCreate,
      productId: 'prod_offline_a',
      owner: 'artisan_A',
      backend: 'http://127.0.0.1:8000',
      idempotencyKey: 'idem_offline_a_123',
      payloadSnapshot: offlineProduct.toJson(),
    );
    await pendingBox.put(offlineOp.id, offlineOp.toPendingString());

    // Switch to artisan_B and sync queue -> should skip artisan_A's work
    await auth.put('user_id', 'artisan_B');
    ActiveSessionManager.bumpSessionGeneration();

    final syncedUnderB = await repo.syncPendingQueue();
    expect(syncedUnderB, 0, reason: 'artisan_B session must not execute artisan_A operations');

    final remainingOp = OfflineOperation.fromPendingString(pendingBox.get(offlineOp.id)!, offlineOp.id);
    expect(remainingOp.status, OfflineOperation.statusPending);
    expect(remainingOp.owner, 'artisan_A');

    // Switch back to artisan_A and sync queue -> should execute and succeed
    await auth.put('user_id', 'artisan_A');
    ActiveSessionManager.bumpSessionGeneration();

    final syncedUnderA = await repo.syncPendingQueue();
    expect(syncedUnderA, 1, reason: 'Original artisan_A session should successfully drain its own work');

    // With no dependent operations, completed operation is purged from queue
    expect(pendingBox.containsKey(offlineOp.id), isFalse);
    final localSaved = productsBox.get('prod_offline_a');
    expect(localSaved, isNotNull);
    expect(localSaved!.revision, 1);
  });

  test('unauthenticated registration and login endpoints dispatch without artisan session', () async {
    await auth.putAll({'is_authenticated': false, 'user_id': null});
    final dio = Dio();
    HttpApiService(baseUrl: 'https://fixture.invalid', dio: dio);

    bool dispatched = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      dispatched = true;
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {'success': true, 'otp_sent': true},
      ));
    }));

    final options = Options(extra: {'is_public': true});
    final res = await dio.post('https://fixture.invalid/api/v1/auth/otp/request', options: options);
    expect(res.statusCode, 200);
    expect(dispatched, isTrue);
    dio.close();
  });
}
