import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/data/services/image_enhancer_service.dart';

class MockSuccessInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.contains('/enhance-image')) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'original_url': '/uploads/raw/sample.jpg',
            'enhanced_url': '/uploads/enhanced/sample_enhanced.jpg',
            'status': 'success',
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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    callCount++;
    handler.reject(
      DioException(
        requestOptions: options,
        error: 'Connection refused / Network unreachable',
        type: DioExceptionType.connectionError,
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
    test('Successful enhancement returns full URL', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(MockSuccessInterceptor());

      final service = HttpImageEnhancerService(
        baseUrl: 'http://127.0.0.1:8000',
        dio: dio,
      );

      final result = await service.enhanceImage(testImageFile.path, draftId: 'draft_101');
      expect(result, equals('http://127.0.0.1:8000/uploads/enhanced/sample_enhanced.jpg'));
    });

    test('Network failure triggers retry and lands in offline retry queue', () async {
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

      // 2. Must NOT silently return without adding to offline queue
      expect(queuedFile, isNotNull,
          reason: 'Image job MUST land in the offline retry queue');
      expect(queuedDraftId, equals('draft_offline_42'),
          reason: 'Enqueued item must retain the product draft ID');

      // 3. Fallback returns local path to keep user UI unblocked
      expect(result, equals(testImageFile.path));
    });
  });
}
