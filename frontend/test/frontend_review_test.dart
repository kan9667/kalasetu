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

  test('restart replays in-flight image enhancement from its durable record', () async {
    final file = File('${dir.path}/source.png')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII='));
    final inputs = <String, dynamic>{'draft_id': 'image_draft', 'generation': 1};
    final fingerprint = await AiOperationRecord.computeFingerprint(operationType: 'image_enhance', owner: 'artisan_review', backend: ApiConfig.baseUrl, inputs: inputs, files: [file]);
    final draft = AddProductDraft(draftId: 'image_draft', originalImagePath: file.path, imageInputGeneration: 1, imageEnhanceOpId: 'image_op');
    await Hive.box('draft_box').put(AddProductFlowNotifier.snapshotKey, jsonEncode({...draft.toJson(), '__version': 1}));
    final now = DateTime.now();
    await AiOperationStorage.save(AiOperationRecord(id: 'image_op', idempotencyKey: 'image_op', owner: 'artisan_review', backend: ApiConfig.baseUrl, operationType: 'image_enhance', draftId: 'image_draft', inputGeneration: 1, inputFingerprint: fingerprint, requestSnapshot: {'image_path': file.path, 'draft_id': 'image_draft'}, status: AiOperationRecord.statusInFlight, createdAt: now, updatedAt: now));
    final probe = ImageProbe();
    final container = ProviderContainer(overrides: [imageEnhancerServiceProvider.overrideWithValue(probe), authRepositoryProvider.overrideWithValue(AuthProbe())]);
    container.read(authStateProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container.read(addProductFlowProvider.notifier).resumeExistingDraft();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    container.dispose();
    expect(probe.calls, 1, reason: 'Direct image operations with no Drift job must resume after process death');
  });
}
