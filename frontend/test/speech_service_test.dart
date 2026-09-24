import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/network/request_session_context.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/data/services/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File testAudioFile;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('speech_test');
    testAudioFile = File('${tempDir.path}/test_audio.m4a');
    await testAudioFile.writeAsBytes(List.filled(100, 1));
  });

  group('HttpSpeechService Tests', () {
    test('transcribeAudio sends stable Idempotency-Key and parses response', () async {
      String? capturedKey;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedKey = options.headers['Idempotency-Key'] as String?;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'transcript': 'हाथ से बना मिट्टी का घड़ा'},
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      final result = await service.transcribeAudio(
        audioPath: testAudioFile.path,
        languageCode: 'hi',
      );

      expect(result.transcript, equals('हाथ से बना मिट्टी का घड़ा'));
      expect(result.confidence, equals(0.95));
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_stt_'));
    });

    test('transcribeAudio maps HTTP 401/403 to SessionExpiredException without fallback', () async {
      for (final statusCode in [401, 403]) {
        final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: statusCode,
                    data: {'detail': 'Invalid token'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final service = HttpSpeechService(dio: dio);
        expect(
          () => service.transcribeAudio(
            audioPath: testAudioFile.path,
            languageCode: 'hi',
          ),
          throwsA(isA<SessionExpiredException>()),
          reason: 'HTTP $statusCode must throw SessionExpiredException immediately',
        );
      }
    });

    test('generateListingFromTranscript sends stable Idempotency-Key', () async {
      String? capturedKey;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedKey = options.headers['Idempotency-Key'] as String?;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'title_en': 'Clay Pot',
                  'title_hi': 'मिट्टी का घड़ा',
                  'description_en': 'Handmade clay pot',
                  'description_hi': 'हाथ से बना घड़ा',
                  'category': 'Pottery',
                  'tags': ['clay', 'pottery'],
                  'cost_inputs': {
                    'materials': 100.0,
                    'labor_hours': 2.0,
                    'hourly_rate': 150.0,
                  },
                },
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      final result = await service.generateListingFromTranscript(
        transcript: 'हाथ से बना मिट्टी का घड़ा',
        languageCode: 'hi',
      );

      expect(result.titleEn, equals('Clay Pot'));
      expect(result.category, equals('Pottery'));
      expect(result.floorPrice, equals(400.0)); // 100 + 2*150
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_listing_'));
    });

    test('generateListingFromTranscript maps HTTP 401/403 to SessionExpiredException without fallback', () async {
      for (final statusCode in [401, 403]) {
        final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: statusCode,
                    data: {'detail': 'Invalid token'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final service = HttpSpeechService(dio: dio);
        expect(
          () => service.generateListingFromTranscript(
            transcript: 'हाथ से बना मिट्टी का घड़ा',
            languageCode: 'hi',
          ),
          throwsA(isA<SessionExpiredException>()),
          reason: 'HTTP $statusCode must throw SessionExpiredException immediately',
        );
      }
    });

    test('transcribeAudio returns noSpeech on status="no_speech"', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'no_speech',
                  'transcript': '',
                  'is_fallback': true,
                  'fallback_reason': 'no_speech',
                },
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      final result = await service.transcribeAudio(
        audioPath: testAudioFile.path,
        languageCode: 'hi',
      );

      expect(result.statusCode, equals(TranscriptionStatusCode.noSpeech));
      expect(result.transcript, isEmpty);
      expect(result.isDegraded, isTrue);
    });

    test('transcribeAudio throws serviceUnavailable when HTTP 200 has empty transcript without no_speech', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'completed',
                  'transcript': '',
                },
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      expect(
        () => service.transcribeAudio(
          audioPath: testAudioFile.path,
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.serviceUnavailable),
          ),
        ),
      );
    });

    test('transcribeAudio throws serviceUnavailable on HTTP 503', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 503,
                  data: {'detail': {'code': 'SERVICE_UNAVAILABLE'}},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      expect(
        () => service.transcribeAudio(
          audioPath: testAudioFile.path,
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.serviceUnavailable),
          ),
        ),
      );
    });

    test('transcribeAudio throws invalidAudio on HTTP 422', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 422,
                  data: {'detail': 'Invalid audio format'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      expect(
        () => service.transcribeAudio(
          audioPath: testAudioFile.path,
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.invalidAudio),
          ),
        ),
      );
    });

    test('transcribeAudio throws invalidAudio when file does not exist', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      final service = HttpSpeechService(dio: dio);
      expect(
        () => service.transcribeAudio(
          audioPath: '/non/existent/path/recording.m4a',
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.invalidAudio),
          ),
        ),
      );
    });

    test('transcribeAudio throws invalidAudio on unsupported extension', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      final service = HttpSpeechService(dio: dio);
      final badFile = File('${testAudioFile.parent.path}/bad.xyz');
      await badFile.writeAsBytes([1, 2, 3]);

      expect(
        () => service.transcribeAudio(
          audioPath: badFile.path,
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.invalidAudio),
          ),
        ),
      );
    });

    test('transcribeAudio throws timedOut on connection timeout', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      expect(
        () => service.transcribeAudio(
          audioPath: testAudioFile.path,
          languageCode: 'hi',
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.statusCode,
            'statusCode',
            equals(TranscriptionStatusCode.timedOut),
          ),
        ),
      );
    });

    test('HttpSpeechService with AuthInterceptor injects Bearer token and forwards session context', () async {
      final tempDir = await Directory.systemTemp.createTemp('auth_test_');
      Hive.init(tempDir.path);
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_speech_123');

      final currentGen = ActiveSessionManager.sessionGeneration;

      final tokenStorage = SecureTokenStorage();
      await tokenStorage.saveToken('valid_jwt_speech_token');

      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'title_en': 'Earthen Pitcher',
                  'title_hi': 'मिट्टी का घड़ा',
                  'description_en': 'Clay pot',
                  'description_hi': 'मिट्टी का बर्तन',
                  'category': 'Pottery',
                  'tags': ['clay'],
                  'raw_material_cost': 50.0,
                  'labor_hours': 1.0,
                  'hourly_rate': 40.0,
                  'floor_price': 90.0,
                },
              ),
            );
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      final sessionContext = RequestSessionContext.explicit(
        userId: 'artisan_speech_123',
        sessionGeneration: currentGen,
        backendOrigin: 'http://127.0.0.1:8000',
      );

      final res = await service.generateListingFromTranscript(
        transcript: 'मिट्टी का घड़ा',
        languageCode: 'hi',
        sessionContext: sessionContext,
      );

      expect(res.titleEn, 'Earthen Pitcher');
      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], 'Bearer valid_jwt_speech_token');
      expect(captured!.extra['expected_user_id'], 'artisan_speech_123');
      expect(captured!.extra['expected_session_gen'], currentGen);
      expect(captured!.extra['expected_backend_origin'], 'http://127.0.0.1:8000');

      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('HttpSpeechService with AuthInterceptor rejects when session generation mismatches before dispatch', () async {
      final tempDir = await Directory.systemTemp.createTemp('auth_test_mismatch_');
      Hive.init(tempDir.path);
      final authBox = await Hive.openBox('auth_box');
      await authBox.put('is_authenticated', true);
      await authBox.put('user_id', 'artisan_speech_123');

      final staleGen = ActiveSessionManager.sessionGeneration;
      ActiveSessionManager.bumpSessionGeneration(); // Bump generation in memory

      final tokenStorage = SecureTokenStorage();
      await tokenStorage.saveToken('valid_jwt_speech_token');

      final dio = AuthenticatedHttpClient.create(
        baseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      var wireCalls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            wireCalls++;
            handler.next(options);
          },
        ),
      );

      final service = HttpSpeechService(dio: dio);
      // Context captured earlier when generation was staleGen
      final staleContext = RequestSessionContext.explicit(
        userId: 'artisan_speech_123',
        sessionGeneration: staleGen,
        backendOrigin: 'http://127.0.0.1:8000',
      );

      expect(
        () => service.generateListingFromTranscript(
          transcript: 'पुराना अनुरोध',
          languageCode: 'hi',
          sessionContext: staleContext,
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(wireCalls, 0, reason: 'Mismatched session must be rejected before wire dispatch');

      await Hive.close();
      await tempDir.delete(recursive: true);
    });
  });
}
