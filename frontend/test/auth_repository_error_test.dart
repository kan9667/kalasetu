import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/data/repositories/auth_repository.dart';

class _LoginResponseAdapter implements HttpClientAdapter {
  _LoginResponseAdapter(this.statusCode, this.detail);

  final int statusCode;
  final String detail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.method, 'POST');
    expect(options.path, '/api/v1/auth/login');
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'detail': detail})),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final acceptsClientErrorResponses in [true, false]) {
    test('login 404 identifies unregistered artisan '
        '(validateStatus accepts 4xx: $acceptsClientErrorResponses)', () async {
      final dio =
          Dio(
              BaseOptions(
                baseUrl: 'https://example.test',
                validateStatus: (status) =>
                    status != null &&
                    (acceptsClientErrorResponses ? status < 500 : status < 400),
              ),
            )
            ..httpClientAdapter = _LoginResponseAdapter(
              404,
              'No artisan registered with this phone number.',
            );

      final result = await AuthRepository(
        baseUrl: 'https://example.test',
        dio: dio,
      ).requestOtp('9876543210');

      expect(result, isA<RequestOtpFailure>());
      final failure = result as RequestOtpFailure;
      expect(failure.statusCode, 404);
      expect(failure.notFound, isTrue);
      expect(failure.message, 'Artisan not registered. Please register first.');
    });
  }

  test(
    'generic route 404 is not mislabeled as an unregistered artisan',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _LoginResponseAdapter(404, 'Not Found');

      final result = await AuthRepository(
        baseUrl: 'https://example.test',
        dio: dio,
      ).requestOtp('9876543210');

      expect(result, isA<RequestOtpFailure>());
      final failure = result as RequestOtpFailure;
      expect(failure.statusCode, 404);
      expect(failure.notFound, isFalse);
      expect(failure.message, 'Not Found');
    },
  );

  test(
    'gateway failure remains a service error, not a registration error',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = _LoginResponseAdapter(
          503,
          'SMS gateway unavailable',
        );

      final result = await AuthRepository(
        baseUrl: 'https://example.test',
        dio: dio,
      ).requestOtp('9876543210');

      expect(result, isA<RequestOtpFailure>());
      final failure = result as RequestOtpFailure;
      expect(failure.statusCode, 503);
      expect(failure.notFound, isFalse);
      expect(failure.message, 'SMS gateway unavailable');
    },
  );
}
