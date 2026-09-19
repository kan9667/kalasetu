import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
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
  });
}
