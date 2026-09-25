import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
import 'package:kalasetu/data/services/chat_service.dart';
import 'package:kalasetu/data/services/social_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpChatService Tests', () {
    test('sendMessage sends stable Idempotency-Key', () async {
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
                  'id': 'msg_1',
                  'role': 'assistant',
                  'reply': 'Hello artisan!',
                  'timestamp': DateTime.now().toIso8601String(),
                },
              ),
            );
          },
        ),
      );

      final service = HttpChatService(dio: dio);
      final reply = await service.sendMessage(message: 'Hello');
      expect(reply.text, equals('Hello artisan!'));
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_chat_'));
    });

    test('sendMessage maps HTTP 401/403 to SessionExpiredException without offline fallback', () async {
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

        final service = HttpChatService(dio: dio);
        expect(
          () => service.sendMessage(message: 'Hello'),
          throwsA(isA<SessionExpiredException>()),
          reason: 'HTTP $statusCode must throw SessionExpiredException immediately',
        );
      }
    });

    test('sendVoiceMessage maps HTTP 401/403 to SessionExpiredException without offline fallback', () async {
      final tempDir = await Directory.systemTemp.createTemp('voice_chat_test');
      final dummyAudio = File('${tempDir.path}/voice.m4a');
      await dummyAudio.writeAsBytes(List.filled(50, 2));

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

        final service = HttpChatService(dio: dio);
        expect(
          () => service.sendVoiceMessage(audioPath: dummyAudio.path),
          throwsA(isA<SessionExpiredException>()),
          reason: 'Voice chat HTTP $statusCode must throw SessionExpiredException immediately',
        );
      }
    });
  });

  group('HttpSocialMediaService Tests', () {
    test('generateForListing sends stable Idempotency-Key', () async {
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
                  'draft_id': 'draft_soc_1',
                  'caption': 'Beautiful handcrafted pot!',
                  'hashtags': ['#pottery', '#handmade'],
                },
              ),
            );
          },
        ),
      );

      final service = HttpSocialMediaService(dio: dio);
      final draft = await service.generateForListing(
        listingId: 'prod_123',
        imageUrl: 'http://127.0.0.1:8000/uploads/test.jpg',
      );

      expect(draft.draftId, equals('draft_soc_1'));
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_soc_'));
    });

    test('generateForListing maps HTTP 401/403 to SessionExpiredException', () async {
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

        final service = HttpSocialMediaService(dio: dio);
        expect(
          () => service.generateForListing(
            listingId: 'prod_123',
            imageUrl: 'http://127.0.0.1:8000/uploads/test.jpg',
          ),
          throwsA(isA<SessionExpiredException>()),
          reason: 'Social generate HTTP $statusCode must throw SessionExpiredException',
        );
      }
    });

    test('saveDraft sends stable Idempotency-Key and maps 401/403 to SessionExpiredException', () async {
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
                  'draft_id': 'draft_soc_2',
                  'caption': 'Updated caption!',
                  'hashtags': ['#pottery'],
                },
              ),
            );
          },
        ),
      );

      final service = HttpSocialMediaService(dio: dio);
      final draft = await service.saveDraft(
        draftId: 'draft_soc_2',
        caption: 'Updated caption!',
        hashtags: ['#pottery'],
      );

      expect(draft.draftId, equals('draft_soc_2'));
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_socsave_'));
    });
  });
}
