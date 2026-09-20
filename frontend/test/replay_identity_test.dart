import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/models/ai_operation_record.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';
import 'package:kalasetu/data/services/image_enhancer_service.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';

class Tokens extends SecureTokenStorage {
  String? value;
  @override
  Future<String?> getToken() async => value;
  @override
  Future<void> saveToken(String token) async { value = token; }
  @override
  Future<void> clearToken() async { value = null; }
}

class AuthProbe extends AuthRepository {
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<String?> getUserId() async => 'artisan_review';
  @override
  Future<String?> getPhoneNumber() async => '9876543210';
}

class ImageProbe extends MockImageEnhancerService {
  int calls = 0;
  @override
  Future<EnhancedImageResult> enhanceImage(String inputPathOrUrl, {String? draftId, String? idempotencyKey}) async {
    calls++;
    return EnhancedImageResult(displayPath: inputPathOrUrl, mediaId: 'med_review');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kalasetu_review_fixture_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());
    await Hive.openBox('draft_box');
    await Hive.openBox('auth_box');
    await Hive.openBox<UserProfile>('user_profile_box');
    await Hive.openBox<String>(AiOperationStorage.boxName);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('simulation must not dispatch with retained artisan bearer token', () async {
    final tokens = Tokens();
    final repo = AuthRepository(tokenStorage: tokens);
    await repo.saveAuthData('artisan_review', '9876543210', token: 'FAKE_ARTISAN_TOKEN');
    final auth = AuthNotifier(repo);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await auth.signInWithCoordinator('ngo_review');
    String? observedAuthorization;
    final dio = AuthenticatedHttpClient.create(baseUrl: 'https://fixture.invalid', tokenStorage: tokens);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      observedAuthorization = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    try { await dio.get('/api/v1/products'); } on DioException { /* A local block is acceptable. */ }
    auth.dispose();
    dio.close();
    expect(observedAuthorization, isNull, reason: 'Simulation must not send requests under the preserved artisan identity');
  });

  test('changed image bytes must not replay under the old identity', () async {
    final file = File('${dir.path}/source.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'image_draft', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    final draft = AddProductDraft(draftId: 'image_draft', originalImagePath: file.path, imageInputGeneration: 1, imageEnhanceOpId: 'image_op');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(id: 'image_op', idempotencyKey: 'image_op', owner: 'artisan_review', backend: ApiConfig.baseUrl, operationType: 'image_enhance', draftId: 'image_draft', inputGeneration: 1, inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'image_draft'}, status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now));
    file.writeAsBytesSync([1, 2, 3, 4]); // Same path, different bytes after process death.
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container.read(addProductFlowProvider.notifier).resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 0, reason: 'Changed input must fail closed instead of dispatching with the old idempotency key');
  });

  test('unchanged image bytes replay succeeds and updates draft', () async {
    final file = File('${dir.path}/source_unchanged.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'draft_unchanged', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    final draft = AddProductDraft(draftId: 'draft_unchanged', originalImagePath: file.path, imageInputGeneration: 1, imageEnhanceOpId: 'op_unchanged');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'op_unchanged', idempotencyKey: 'op_unchanged', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'image_enhance', draftId: 'draft_unchanged', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'draft_unchanged'},
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container.read(addProductFlowProvider.notifier).resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final updatedOp = await AiOperationStorage.get('op_unchanged');
    final updatedDraftState = container.read(addProductFlowProvider);
    container.dispose();
    expect(probe.calls, 1, reason: 'Unchanged input must replay successfully');
    expect(updatedOp?.status, AiOperationRecord.statusCompleted);
    expect(updatedDraftState.mediaId, 'med_review');
  });

  test('missing image file fails closed and does not replay', () async {
    final file = File('${dir.path}/source_missing.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'draft_missing', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    final draft = AddProductDraft(draftId: 'draft_missing', originalImagePath: file.path, imageInputGeneration: 1, imageEnhanceOpId: 'op_missing');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'op_missing', idempotencyKey: 'op_missing', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'image_enhance', draftId: 'draft_missing', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'draft_missing'},
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    file.deleteSync(); // Delete the file before restart resume
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container.read(addProductFlowProvider.notifier).resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final updatedOp = await AiOperationStorage.get('op_missing');
    final updatedDraftState = container.read(addProductFlowProvider);
    container.dispose();
    expect(probe.calls, 0, reason: 'Missing file must not dispatch replay');
    expect(updatedOp?.status, AiOperationRecord.statusFailed);
    expect(updatedDraftState.isDegraded, isTrue);
  });

  test('duplicate resume calls do not fire duplicate image replay requests', () async {
    final file = File('${dir.path}/source_dup.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'draft_dup', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    final draft = AddProductDraft(draftId: 'draft_dup', originalImagePath: file.path, imageInputGeneration: 1, imageEnhanceOpId: 'op_dup');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'op_dup', idempotencyKey: 'op_dup', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'image_enhance', draftId: 'draft_dup', inputGeneration: 1,
      inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'draft_dup'},
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final notifier = container.read(addProductFlowProvider.notifier);
    notifier.resumeExistingDraft();
    notifier.resumeExistingDraft();
    notifier.resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 1, reason: 'Multiple resume calls must not trigger duplicate replays');
  });

  test('stale in-flight operation from superseded generation is not replayed', () async {
    final file = File('${dir.path}/source_stale.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'draft_stale', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    // Active draft has moved to generation 2
    final draft = AddProductDraft(draftId: 'draft_stale', originalImagePath: file.path, imageInputGeneration: 2, imageEnhanceOpId: 'op_new');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(
      id: 'op_stale', idempotencyKey: 'op_stale', owner: 'artisan_review', backend: ApiConfig.baseUrl,
      operationType: 'image_enhance', draftId: 'draft_stale', inputGeneration: 1, // generation 1 is stale
      inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'draft_stale'},
      status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now,
    ));
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container.read(addProductFlowProvider.notifier).resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 0, reason: 'Stale generation operation must not be dispatched');
  });
}
