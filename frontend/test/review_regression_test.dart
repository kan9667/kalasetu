import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/widgets/app_image.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/ai_operation_record.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/data/services/api_service.dart';
import 'package:kalasetu/data/services/pricing_service.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';

class AuthProbe extends AuthRepository {
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<String?> getUserId() async => 'artisan_review';
  @override
  Future<String?> getPhoneNumber() async => '9876543210';
}

class MemoryTokens extends SecureTokenStorage {
  String? token;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> saveToken(String value) async { token = value; }
  @override
  Future<void> clearToken() async { token = null; }
}

class PricingProbe extends MockPricingService {
  int calls = 0;
  @override
  Future<PriceSuggestion> suggestPrice({String? description, required String category, required List<String> tags, String? imageUrl, double? rawMaterialCost, double? laborHours, double? hourlyWage, String? idempotencyKey}) async {
    calls++;
    return const PriceSuggestion(minPrice: 100, maxPrice: 500, suggestedPrice: 300, floorPrice: 100, reasoning: 'probe', reasoningHi: 'probe');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kalasetu_review_fixture_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());
    await Hive.openBox('draft_box');
    final authBox = await Hive.openBox('auth_box');
    await authBox.put('is_authenticated', true);
    await authBox.put('user_id', 'artisan_review');
    await Hive.openBox<UserProfile>('user_profile_box');
    await Hive.openBox<String>(AiOperationStorage.boxName);
    await Hive.openBox<Product>('products_box');
    await Hive.openBox<String>('pending_sync_box');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('undecodable local file must not report successful image rendering', (tester) async {
    final file = File('${dir.path}/broken.jpg')..writeAsStringSync('this is not an image');
    var reportedSuccess = false;
    await tester.pumpWidget(MaterialApp(home: AppImage(
      imageUrl: file.path,
      onRenderSuccess: ({required assetIdentity, required sha256Checksum, sessionGeneration}) {
        reportedSuccess = true;
      },
    )));
    await tester.pump();
    expect(reportedSuccess, isFalse, reason: 'Unreadable image bytes cannot constitute artisan preview verification');
  });

  test('legacy migration preserves media queue references and additional photos', () async {
    final box = Hive.box('draft_box');
    await box.putAll({
      'draft_id': 'legacy',
      'draft_image': '/saved/photo.jpg',
      'draft_image_queue_id': 'image_queue_1',
      'draft_voice_queue_id': 'voice_queue_1',
      'draft_image_queue_status': 0,
      'draft_voice_queue_status': 0,
      'draft_additional_images': ['/saved/detail.jpg'],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(addProductFlowProvider);
    for (var i = 0; i < 100 && box.containsKey('draft_id'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final migrated = jsonDecode(box.get(AddProductFlowNotifier.snapshotKey) as String) as Map;
    expect(migrated['image_queue_item_id'], 'image_queue_1', reason: 'Migration must not orphan a durable media job');
    expect(migrated['voice_queue_item_id'], 'voice_queue_1');
    expect(migrated['additional_image_paths'], ['/saved/detail.jpg']);
  });

  test('restart replays the persisted in-flight pricing operation', () async {
    final inputs = <String, dynamic>{'description': 'clay pot', 'category': 'Pottery', 'tags': <String>[]};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'pricing_suggest', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs);
    final draft = AddProductDraft(draftId: 'restart_draft', descriptionEn: 'clay pot', category: 'Pottery', pricingInputGeneration: 1, pricingOpId: 'pricing_op', pricingFingerprint: fingerprint);
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'pricing_op', idempotencyKey: 'pricing_op', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'pricing_suggest', draftId: 'restart_draft', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: inputs,
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = PricingProbe();
    final container = ProviderContainer(overrides: [pricingServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final flow = container.read(addProductFlowProvider.notifier);
    flow.resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 1, reason: 'Pending work must recover without another manual generation request');
  });

  test('NGO simulation must not restore as an authenticated non-simulation session', () async {
    final repo = AuthRepository(tokenStorage: MemoryTokens());
    final auth = AuthNotifier(repo);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await auth.signInWithCoordinator('coordinator_demo');
    auth.dispose();
    final restored = AuthNotifier(repo);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final restoredState = restored.state;
    restored.dispose();
    expect(restoredState.isAuthenticated && !restoredState.isNgoSimulation, isFalse,
      reason: 'A simulated token must never be restored as a genuine artisan session');
  });

  test('NGO simulation does not overwrite existing artisan bearer token in SecureTokenStorage', () async {
    final tokens = MemoryTokens();
    final repo = AuthRepository(tokenStorage: tokens);
    await repo.saveAuthData(
      'artisan_1',
      '9876543210',
      token: 'artisan_genuine_jwt_token',
    );
    final auth = AuthNotifier(repo);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(auth.state.isAuthenticated, isTrue);

    // Sign in as coordinator simulation
    await auth.signInWithCoordinator('coordinator_temp');
    expect(auth.state.isNgoSimulation, isTrue);
    expect(auth.state.isAuthenticated, isFalse);

    // Verify token storage was NOT overwritten
    expect(await tokens.getToken(), 'artisan_genuine_jwt_token');

    // Restore session after app restart
    auth.dispose();
    final restoredAuth = AuthNotifier(repo);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restoredAuth.state.isNgoSimulation, isTrue);
    expect(restoredAuth.state.isAuthenticated, isFalse);

    // Exit simulation (signOut clears simulation data)
    await restoredAuth.signOut();
    expect(restoredAuth.state.isNgoSimulation, isFalse);
    // Token is still intact
    expect(await tokens.getToken(), 'artisan_genuine_jwt_token');
    restoredAuth.dispose();
  });

  test('AiOperationStorage.updateResult does not revive superseded operation', () async {
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'superseded_op',
      idempotencyKey: 'superseded_op',
      owner: 'artisan_review',
      backend: ApiConfig.baseUrl,
      operationType: 'pricing_suggest',
      draftId: 'draft_superseded',
      inputGeneration: 1,
      inputFingerprint: 'fp1',
      requestSnapshot: const {},
      status: AiOperationRecord.statusSuperseded,
      createdAt: now,
      updatedAt: now,
    ));

    // Attempt to update result as completed from late callback
    await AiOperationStorage.updateResult(
      'superseded_op',
      status: AiOperationRecord.statusCompleted,
      resultData: {'floor_price': 50.0},
    );

    final updated = await AiOperationStorage.get('superseded_op');
    expect(updated?.status, AiOperationRecord.statusSuperseded,
      reason: 'Late results must never revive a superseded operation');
  });

  test('AddProductDraft.validateSnapshotSchema rejects missing required fields and non-integer version', () {
    expect(() => AddProductDraft.validateSnapshotSchema({'__version': 1}), throwsFormatException); // missing draft_id
    expect(() => AddProductDraft.validateSnapshotSchema({'draft_id': 'd1', '__version': '1'}), throwsFormatException); // non-int version
    expect(() => AddProductDraft.validateSnapshotSchema({'draft_id': 'd1', '__version': 1, 'tags': 'not a list'}), throwsFormatException); // bad tags
    expect(() => AddProductDraft.validateSnapshotSchema({'draft_id': 'd1', '__version': 1, 'additional_image_paths': 'not a list'}), throwsFormatException); // bad additional_image_paths
    expect(() => AddProductDraft.validateSnapshotSchema({'draft_id': 'd1', '__version': 1}), returnsNormally); // valid minimal snapshot
  });

  test('rapid duplicate resumeExistingDraft calls do not fire duplicate replay dispatches', () async {
    final inputs = <String, dynamic>{'description': 'clay pot', 'category': 'Pottery', 'tags': <String>[]};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'pricing_suggest', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs);
    final draft = AddProductDraft(draftId: 'single_flight_draft', descriptionEn: 'clay pot', category: 'Pottery', pricingInputGeneration: 1, pricingOpId: 'single_pricing_op', pricingFingerprint: fingerprint);
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'single_pricing_op', idempotencyKey: 'single_pricing_op', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'pricing_suggest', draftId: 'single_flight_draft', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: inputs,
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = PricingProbe();
    final container = ProviderContainer(overrides: [pricingServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final flow = container.read(addProductFlowProvider.notifier);
    // Trigger rapid duplicate calls
    flow.resumeExistingDraft();
    flow.resumeExistingDraft();
    flow.resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 1, reason: 'Duplicate resume calls must not trigger concurrent duplicate replay requests');
  });

  test('replay is skipped when account or backend switches', () async {
    final inputs = <String, dynamic>{'description': 'clay pot', 'category': 'Pottery', 'tags': <String>[]};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'pricing_suggest', owner: 'different_artisan', backend: ApiConfig.baseUrl, inputs: inputs);
    final draft = AddProductDraft(draftId: 'switched_draft', descriptionEn: 'clay pot', category: 'Pottery', pricingInputGeneration: 1, pricingOpId: 'switched_op', pricingFingerprint: fingerprint);
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'switched_op', idempotencyKey: 'switched_op', owner: 'different_artisan', backend: ApiConfig.baseUrl,
      operationType: 'pricing_suggest', draftId: 'switched_draft', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: inputs,
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = PricingProbe();
    // Container is logged in as 'artisan_review', NOT 'different_artisan'
    final container = ProviderContainer(overrides: [pricingServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final flow = container.read(addProductFlowProvider.notifier);
    flow.resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 0, reason: 'Replay must be skipped if owner does not match current authenticated user');
  });

  test('approveAndPublishProduct throws StateError when photo bytes on disk do not match reviewed checksum', () async {
    final repo = ProductRepository();
    await repo.initialize();

    final imageFile = File('${dir.path}/verified.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    const originalSha256 = '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a'; // sha256 of [1, 2, 3, 4]
    final p = Product(
      id: 'prod_tamper_check',
      title: 'Bowl',
      description: 'Handmade bowl',
      price: 200,
      photoPath: imageFile.path,
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: 1,
      contentHash: '1111111111111111111111111111111111111111111111111111111111111111',
      reviewedMediaChecksum: originalSha256,
    );
    await repo.addProduct(p);

    // Tamper with the image file on disk
    imageFile.writeAsBytesSync([9, 9, 9, 9]);

    // Online publish must fail closed with StateError
    expect(
      () => repo.approveAndPublishProduct('prod_tamper_check', isOnline: true),
      throwsA(isA<StateError>()),
      reason: 'Publishing tampered file must fail closed',
    );

    // Offline publish must also fail closed with StateError
    expect(
      () => repo.approveAndPublishProduct('prod_tamper_check', isOnline: false),
      throwsA(isA<StateError>()),
      reason: 'Offline queueing of tampered file must fail closed',
    );
  });

  test('approveAndPublishProduct throws StateError when server-returned media checksum mismatches reviewed checksum', () async {
    const originalSha256 = '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a'; // sha256 of [1, 2, 3, 4]
    final imageFile = File('${dir.path}/mismatch.jpg')..writeAsBytesSync([1, 2, 3, 4]);

    final mockApi = MismatchMockApiService('completely_different_server_sha256');
    final repo = ProductRepository(apiService: mockApi);
    await repo.initialize();

    final p = Product(
      id: 'prod_mismatch_check',
      title: 'Plate',
      description: 'Handmade plate',
      price: 250,
      photoPath: imageFile.path,
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: 1,
      contentHash: '2222222222222222222222222222222222222222222222222222222222222222',
      reviewedMediaChecksum: originalSha256,
    );
    await repo.addProduct(p);

    expect(
      () => repo.approveAndPublishProduct('prod_mismatch_check', isOnline: true),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('Server-returned media checksum does not match reviewed checksum'),
      )),
      reason: 'Mismatched server checksum must fail closed and prevent publication',
    );
  });

  test('staged upload response-lost retry succeeds and publishes when server returns matching checksum', () async {
    const originalSha256 = '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a'; // sha256 of [1, 2, 3, 4]
    final imageFile = File('${dir.path}/retry_ok.jpg')..writeAsBytesSync([1, 2, 3, 4]);

    final mockApi = ResponseLostMockApiService(originalSha256);
    final repo = ProductRepository(apiService: mockApi);
    await repo.initialize();

    final p = Product(
      id: 'prod_retry_check',
      title: 'Cup',
      description: 'Handmade cup',
      price: 150,
      photoPath: imageFile.path,
      category: 'Pottery',
      status: ProductStatus.draft,
      revision: 1,
      contentHash: '3333333333333333333333333333333333333333333333333333333333333333',
      reviewedMediaChecksum: originalSha256,
    );
    await repo.addProduct(p);

    // First attempt fails during upload; safely transitions to pendingApprovalSync without corrupting state
    final firstResult = await repo.approveAndPublishProduct('prod_retry_check', isOnline: true);
    expect(firstResult.status, ProductStatus.pendingApprovalSync);
    expect(firstResult.approvedRevision, isNull);

    // Second attempt (retry) via syncPendingQueue replays outbox with matching checksum and publishes
    await repo.syncPendingQueue();
    final published = (await repo.getProducts()).firstWhere((p) => p.id == 'prod_retry_check');
    expect(published.status, ProductStatus.published);
    expect(published.mediaId, 'med_recovered');
    expect(mockApi.attempts, 2);
  });
}

class MismatchMockApiService extends MockApiService {
  final String returnedChecksum;
  MismatchMockApiService(this.returnedChecksum);

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    return {
      'media_id': 'med_mismatch',
      'status': 'ready',
      'filename': filePath.split('/').last,
      'content_type': 'image/jpeg',
      'byte_size': 1024,
      'sha256_checksum': returnedChecksum,
    };
  }
}

class ResponseLostMockApiService extends MockApiService {
  int attempts = 0;
  final String matchingChecksum;
  ResponseLostMockApiService(this.matchingChecksum);

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    attempts++;
    if (attempts == 1) {
      throw const SocketException('Connection reset by peer after upload was received');
    }
    return {
      'media_id': 'med_recovered',
      'status': 'ready',
      'filename': filePath.split('/').last,
      'content_type': 'image/jpeg',
      'byte_size': 1024,
      'sha256_checksum': matchingChecksum,
    };
  }
}
