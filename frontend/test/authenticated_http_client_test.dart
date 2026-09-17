import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auth_http_test_');
    Hive.init(tempDir.path);
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AuthenticatedHttpClient & AuthInterceptor', () {
    setUp(() {
      SecureTokenStorage.resetForTesting();
    });

    test('Injects Bearer token into request headers when available', () async {
      final tokenStorage = SecureTokenStorage();
      await tokenStorage.saveToken('jwt_valid_artisan_token_123');

      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://example.com',
        tokenStorage: tokenStorage,
      );

      // Intercept request to inspect options
      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: {}),
            );
          },
        ),
      );

      await dio.get('/test-endpoint');

      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], 'Bearer jwt_valid_artisan_token_123');
    });

    test('Preserves existing Idempotency-Key and sets Bearer token on mutating POST', () async {
      final tokenStorage = SecureTokenStorage();
      await tokenStorage.saveToken('jwt_artisan_abc');

      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://example.com',
        tokenStorage: tokenStorage,
      );

      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: {}),
            );
          },
        ),
      );

      await dio.post(
        '/mutate',
        data: {'name': 'test'},
        options: Options(
          headers: {'Idempotency-Key': 'my_preserved_stable_key_456'},
        ),
      );

      expect(captured, isNotNull);
      expect(captured!.headers['Idempotency-Key'], 'my_preserved_stable_key_456');
      expect(captured!.headers['Authorization'], 'Bearer jwt_artisan_abc');
    });

    test('Does NOT generate random Idempotency-Key inside AuthInterceptor when omitted (enforcing caller ownership)', () async {
      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://example.com',
      );

      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: {}),
            );
          },
        ),
      );

      await dio.post('/create-item', data: {});

      expect(captured, isNotNull);
      expect(captured!.headers['Idempotency-Key'], isNull);
    });

    test('Does NOT add Idempotency-Key on GET requests', () async {
      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'https://example.com',
      );

      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: {}),
            );
          },
        ),
      );

      await dio.get('/get-items');

      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('Idempotency-Key'), isFalse);
    });

    test('Triggers onUnauthorized callback on 401 status', () {
      bool unauthorizedCalled = false;
      final interceptor = AuthInterceptor(
        onUnauthorized: () => unauthorizedCalled = true,
      );

      final dioException = DioException(
        requestOptions: RequestOptions(path: '/protected'),
        response: Response(
          requestOptions: RequestOptions(path: '/protected'),
          statusCode: 401,
        ),
      );

      final handler = _TestErrorHandler();
      interceptor.onError(dioException, handler);
      expect(unauthorizedCalled, isTrue);
      expect(handler.passedError?.response?.statusCode, 401);
    });

    test('SecureTokenStorage migrates legacy unencrypted token from auth_box', () async {
      final legacyBox = await Hive.openBox('auth_box');
      await legacyBox.put('access_token', 'legacy_unencrypted_jwt_token_999');

      final tokenStorage = SecureTokenStorage();
      final migratedToken = await tokenStorage.getToken();

      expect(migratedToken, 'legacy_unencrypted_jwt_token_999');

      // Legacy key should be removed from plain Hive box
      expect(legacyBox.get('access_token'), isNull);
    });
  });
}

class _TestErrorHandler extends ErrorInterceptorHandler {
  DioException? passedError;

  @override
  void next(DioException err) {
    passedError = err;
  }

  @override
  void reject(DioException err, [bool callFollowingErrorInterceptor = false]) {
    passedError = err;
  }
}
