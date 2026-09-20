import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';

import 'dart:math';

/// Generates a high ephemeral TCP port.
int getUnusedPort() {
  return 48000 + Random().nextInt(10000);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  HttpOverrides.global = null;

  late Directory tempDir;
  late String tempDbPath;
  late String tempUploadDir;
  late int serverPort;
  late String baseUrl;
  late Process serverProcess;
  late Dio dioClient;
  late String artisanToken;
  final serverLogs = StringBuffer();

  // Minimal valid 1x1 JPEG image bytes for magic byte validation and SHA-256 calculation
  final validJpegBytes = <int>[
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
    0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
    0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
    0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
    0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
    0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
    0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
    0x00, 0x7F, 0x00, 0xFF, 0xD9,
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('kalasetu_http_outbox_e2e_');
    tempDbPath = '${tempDir.path}/test_kalasetu.db';
    tempUploadDir = '${tempDir.path}/uploads';
    await Directory(tempUploadDir).create(recursive: true);

    // 1. Run Alembic migrations against the fresh test database
    final alembicRes = await Process.run(
      '/Library/Frameworks/Python.framework/Versions/3.14/bin/python3',
      ['-m', 'alembic', '-c', 'backend/alembic.ini', 'upgrade', 'head'],
      workingDirectory: '/Users/kanishka/Developer/kalasetu',
      environment: {
        ...Platform.environment,
        'DATABASE_URL': 'sqlite:///$tempDbPath',
        'PYTHONPATH': '.',
      },
    );
    if (alembicRes.exitCode != 0) {
      throw Exception('Alembic migration failed: ${alembicRes.stderr}\n${alembicRes.stdout}');
    }

    // 2. Select port and launch FastAPI via Uvicorn
    serverPort = getUnusedPort();
    baseUrl = 'http://127.0.0.1:$serverPort';

    serverProcess = await Process.start(
      '/Library/Frameworks/Python.framework/Versions/3.14/bin/python3',
      [
        '-m',
        'uvicorn',
        'backend.main:app',
        '--host',
        '127.0.0.1',
        '--port',
        '$serverPort',
        '--log-level',
        'info',
      ],
      workingDirectory: '/Users/kanishka/Developer/kalasetu',
      environment: {
        ...Platform.environment,
        'ENVIRONMENT': 'test',
        'DATABASE_URL': 'sqlite:///$tempDbPath',
        'JWT_SECRET_KEY': 'real_http_integration_test_secret_key_32_bytes',
        'ALLOW_DEMO_OTP': 'true',
        'SMS_PROVIDER': 'mock',
        'UPLOAD_DIR': tempUploadDir,
        'PYTHONPATH': '.',
      },
    );

    // Pipe server stdout/stderr for debuggability
    serverProcess.stdout.transform(utf8.decoder).listen((line) {
      serverLogs.writeln('[SERVER STDOUT] $line');
    });
    serverProcess.stderr.transform(utf8.decoder).listen((line) {
      serverLogs.writeln('[SERVER STDERR] $line');
    });

    // 3. Poll /api/v1/health until server is ready
    dioClient = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 4),
      ),
    );

    bool isHealthy = false;
    for (int i = 0; i < 50; i++) {
      try {
        final res = await dioClient.get('/api/v1/health');
        if (res.statusCode == 200) {
          isHealthy = true;
          break;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    if (!isHealthy) {
      serverProcess.kill();
      throw Exception('FastAPI server did not become healthy in time on $baseUrl.\nServer Logs:\n$serverLogs');
    }

    // 4. Initialize Hive
    Hive.init('${tempDir.path}/hive');
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());

    await Hive.openBox('auth_box');
    await Hive.openBox<Product>('products_box');
    await Hive.openBox<String>('pending_sync_box');

    // 5. Authenticate via real OTP challenge lifecycle
    // In demo mode with ALLOW_DEMO_OTP=true, OTP for 9876543210 is 123456
    final loginRes = await dioClient.post('/api/v1/auth/login', data: {'phone': '9876543210'});
    expect(loginRes.statusCode, 200);

    final verifyRes = await dioClient.post(
      '/api/v1/auth/verify-otp',
      data: {'phone': '9876543210', 'otp': '123456'},
    );
    expect(verifyRes.statusCode, 200);
    artisanToken = verifyRes.data['access_token'] as String;
    expect(artisanToken, isNotEmpty);

    // Persist token in AuthRepository's Hive box for HttpApiService interceptor
    final authRepo = AuthRepository(baseUrl: baseUrl);
    await authRepo.saveAuthData('artisan_01', '9876543210', token: artisanToken);
  });

  tearDownAll(() async {
    try {
      serverProcess.kill(ProcessSignal.sigterm);
    } catch (_) {}
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

  test('Real HTTP Wire Test: Outbox dependency chain, atomic media upload, and approval publish against live FastAPI', () async {
    // Write real JPEG file for upload
    final testImageFile = File('${tempDir.path}/pottery_pot.jpg');
    await testImageFile.writeAsBytes(validJpegBytes);

    final httpApiService = HttpApiService(baseUrl: baseUrl);
    final repo = ProductRepository(apiService: httpApiService);
    final productsBox = Hive.box<Product>('products_box');

    final draft = Product(
      id: 'prod_wire_pottery_001',
      title: 'Terracotta Cooking Handi',
      titleHi: 'मिट्टी की हांडी',
      description: 'Earthen pot for slow cooking',
      descriptionHi: 'पारंपरिक मिट्टी की हांडी',
      price: 520.0,
      photoPath: testImageFile.path,
      category: 'Pottery',
      materialsCost: 100.0,
      laborHours: 2.5,
      hourlyRate: 100.0,
      transportCost: 50.0,
      otherOverhead: 20.0,
    );

    // 1. Capture offline
    await repo.addProduct(draft, isOnline: false);
    await repo.approveAndPublishProduct(draft.id, isOnline: false);

    // Verify local offline status invariant: pendingApprovalSync with null metadata
    final localDraft = productsBox.get(draft.id);
    expect(localDraft, isNotNull);
    expect(localDraft!.status, ProductStatus.pendingApprovalSync);
    expect(localDraft.approvedAt, isNull);
    expect(localDraft.publishedAt, isNull);
    expect(localDraft.approvedRevision, isNull);

    // Verify local append-only outbox structure: 4 operations keyed by unique op.id
    final pendingOps = repo.getAllOperations();
    expect(pendingOps.length, 4);

    final createOp = pendingOps.firstWhere((o) => o.action == OfflineOperation.actionCreate);
    final mediaOp = pendingOps.firstWhere((o) => o.action == OfflineOperation.actionMediaUpload);
    final attachOp = pendingOps.firstWhere((o) => o.action == OfflineOperation.actionAttachMedia);
    final publishOp = pendingOps.firstWhere((o) => o.action == OfflineOperation.actionApprovePublish);

    expect(mediaOp.dependsOnOpId, createOp.id);
    expect(attachOp.dependsOnOpId, mediaOp.id);
    expect(attachOp.mediaIdFromOpId, mediaOp.id);
    expect(publishOp.dependsOnOpId, attachOp.id);

    // 2. Synchronize outbox over real HTTP wire
    final syncedCount = await repo.syncPendingQueue();
    expect(syncedCount, 4);
    expect(repo.getPendingCount(), 0);

    // 3. Inspect resulting product directly on the live FastAPI backend
    final remoteGetRes = await dioClient.get(
      '/api/v1/products/${draft.id}',
      options: Options(headers: {'Authorization': 'Bearer $artisanToken'}),
    );
    expect(remoteGetRes.statusCode, 200);

    final serverData = remoteGetRes.data as Map<String, dynamic>;
    expect(serverData['id'], draft.id);
    expect(serverData['status'], 'published');
    expect(serverData['revision'], 2); // 1 on create + 1 on attach_media
    expect(serverData['approved_revision'], 2);
    expect(serverData['approved_by_artisan_id'], 'artisan_01');
    expect(serverData['approved_at'], isNotNull);
    expect(serverData['published_at'], isNotNull);
    expect(serverData['media_id'], startsWith('med_'));
    expect(serverData['content_hash'], isNotEmpty);

    // 4. Verify Server Idempotency Replay over HTTP wire:
    // Replaying the exact CREATE operation with the same Idempotency-Key returns HTTP 200/201
    // without creating duplicate rows or failing.
    final replayOp = OfflineOperation(
      id: 'op_replay_test_create',
      action: OfflineOperation.actionCreate,
      productId: draft.id,
      idempotencyKey: createOp.idempotencyKey,
      payloadSnapshot: createOp.payloadSnapshot,
      owner: createOp.owner,
      backend: createOp.backend,
    );
    final pendingBox = Hive.box<String>('pending_sync_box');
    await pendingBox.put(replayOp.id, replayOp.toPendingString());

    final replaySynced = await repo.syncPendingQueue();
    expect(replaySynced, 1);
    expect(repo.getPendingCount(), 0);

    // 5. Verify Optimistic Locking: Attempting to publish with stale revision 1 is rejected with 409
    try {
      await dioClient.post(
        '/api/v1/products/${draft.id}/approve-and-publish',
        data: {
          'revision': 1,
          'content_hash': '0000000000000000000000000000000000000000000000000000000000000001',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $artisanToken',
            'Idempotency-Key': 'idem_stale_attempt_test_key',
          },
        ),
      );
      fail('Server should have rejected stale revision with 409 Conflict');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 409);
      expect(e.response?.data['detail']?.toString().toLowerCase(), contains('stale'));
    }
  });
}
