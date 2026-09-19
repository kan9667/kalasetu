import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
import 'package:kalasetu/data/services/image_enhancer_service.dart';

class MockSuccessInterceptor extends Interceptor {
  String? capturedAuthHeader;
  String? capturedIdempotencyKey;
  int callCount = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    callCount++;
    capturedAuthHeader = options.headers['Authorization'] as String?;
    capturedIdempotencyKey = options.headers['Idempotency-Key'] as String?;

    if (options.path.contains('/enhance-image')) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'original_url': '/uploads/raw/sample.jpg',
            'enhanced_url': '/uploads/enhanced/sample_enhanced.jpg',
            'media_id': 'med_test_123',
            'original_media_id': 'med_raw_123',
            'sha256_checksum': 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
            'is_degraded': false,
            'degraded_reason': null,
            'status': 'ready',
          },
        ),
      );
      return;
    }
    super.onRequest(options, handler);
  }
}

class MockFailureInterceptor extends Interceptor {
  int callCount = 0;
  final List<String?> observedKeys = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    callCount++;
    observedKeys.add(options.headers['Idempotency-Key'] as String?);
    handler.reject(
      DioException(
        requestOptions: options,
        error: 'Connection refused / Network unreachable',
        type: DioExceptionType.connectionError,
      ),
    );
  }
}

class MockAuthErrorInterceptor extends Interceptor {
  final int statusCode;
  MockAuthErrorInterceptor(this.statusCode);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: statusCode,
          data: {'detail': 'Invalid or expired token'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File testImageFile;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('enhancer_test');
    testImageFile = File('${tempDir.path}/test_pot.png');
    // Write a dummy 100-byte file
    await testImageFile.writeAsBytes(List.filled(100, 42));
  });

  group('HttpImageEnhancerService Tests', () {
    test('Successful enhancement returns typed EnhancedImageResult with lineage', () async {
      final successInterceptor = MockSuccessInterceptor();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(successInterceptor);

      final service = HttpImageEnhancerService(
        baseUrl: 'http://127.0.0.1:8000',
        dio: dio,
      );

      final result = await service.enhanceImage(testImageFile.path, draftId: 'draft_101');
      expect(result.displayPath, equals('http://127.0.0.1:8000/uploads/enhanced/sample_enhanced.jpg'));
      expect(result.mediaId, equals('med_test_123'));
      expect(result.originalMediaId, equals('med_raw_123'));
      expect(result.sha256Checksum, equals('a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'));
      expect(result.isDegraded, isFalse);
      expect(result.status, equals('ready'));
      expect(successInterceptor.capturedIdempotencyKey, isNotNull);
      expect(successInterceptor.capturedIdempotencyKey, startsWith('idem_img_'));
    });

    test('Network failure preserves stable Idempotency-Key across retries and lands in offline queue', () async {
      final failureInterceptor = MockFailureInterceptor();
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(failureInterceptor);

      File? queuedFile;
      String? queuedDraftId;

      final service = HttpImageEnhancerService(
        baseUrl: 'http://127.0.0.1:8000',
        dio: dio,
        maxRetries: 1,
        onFallbackQueue: (file, draftId) async {
          queuedFile = file;
          queuedDraftId = draftId;
        },
      );

      final result = await service.enhanceImage(testImageFile.path, draftId: 'draft_offline_42');

      // 1. Should have retried at least once (initial attempt + 1 retry = 2 calls)
      expect(failureInterceptor.callCount, greaterThanOrEqualTo(2),
          reason: 'Service must retry at least once before falling back');

      // 2. Stable Idempotency-Key preserved across retries
      expect(failureInterceptor.observedKeys.length, equals(2));
      expect(failureInterceptor.observedKeys[0], isNotNull);
      expect(failureInterceptor.observedKeys[0], equals(failureInterceptor.observedKeys[1]),
          reason: 'Idempotency key must be preserved across retry attempts');

      // 3. Must NOT silently return without adding to offline queue
      expect(queuedFile, isNotNull,
          reason: 'Image job MUST land in the offline retry queue');
      expect(queuedDraftId, equals('draft_offline_42'),
          reason: 'Enqueued item must retain the product draft ID');

      // 4. Fallback returns local path to keep user UI unblocked
      expect(result.displayPath, equals(testImageFile.path));
      expect(result.isDegraded, isTrue);
      expect(result.status, equals('offline_queued'));
    });

    test('HTTP 401/403 maps to SessionExpiredException and NEVER queues offline fallback', () async {
      for (final statusCode in [401, 403]) {
        final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
        dio.interceptors.add(MockAuthErrorInterceptor(statusCode));

        bool fallbackCalled = false;
        final service = HttpImageEnhancerService(
          baseUrl: 'http://127.0.0.1:8000',
          dio: dio,
          maxRetries: 2,
          onFallbackQueue: (file, draftId) async {
            fallbackCalled = true;
          },
        );

        expect(
          () => service.enhanceImage(testImageFile.path, draftId: 'draft_auth_err'),
          throwsA(isA<SessionExpiredException>()),
          reason: 'HTTP $statusCode must throw SessionExpiredException immediately',
        );

        expect(fallbackCalled, isFalse,
            reason: 'Auth errors must never be treated as offline fallback');
      }
    });
  });
}
