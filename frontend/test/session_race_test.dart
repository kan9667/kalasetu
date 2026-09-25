import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/network/authenticated_http_client.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';

class DelayedTokens extends SecureTokenStorage {
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> getToken() {
    started.complete();
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('simulation switch during token read cannot authorize request', () async {
    final dir = await Directory.systemTemp.createTemp('session_race_');
    Hive.init(dir.path);
    final box = await Hive.openBox('auth_box');
    await box.put('is_authenticated', true);
    await box.put('user_id', 'artisan_1');
    final tokens = DelayedTokens();
    final dio = AuthenticatedHttpClient.create(baseUrl: 'https://fixture.invalid', tokenStorage: tokens);
    String? authorization;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      authorization = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final request = dio.get('/api/v1/products');
    await tokens.started.future;
    await box.put('is_ngo_simulation', true);
    await box.put('is_authenticated', false);
    tokens.result.complete('FAKE_OLD_ARTISAN_TOKEN');
    try { await request; } on DioException { /* Local rejection is acceptable. */ }
    dio.close();
    await Hive.close();
    await dir.delete(recursive: true);
    expect(authorization, isNull, reason: 'Session mode must be rechecked after asynchronous token retrieval');
  });

  test('logout or account switch during token read suppresses stale authorization', () async {
    final dir = await Directory.systemTemp.createTemp('session_logout_race_');
    Hive.init(dir.path);
    final box = await Hive.openBox('auth_box');
    await box.put('is_authenticated', true);
    await box.put('user_id', 'artisan_1');
    final tokens = DelayedTokens();
    final dio = AuthenticatedHttpClient.create(baseUrl: 'https://fixture.invalid', tokenStorage: tokens);
    String? authorization;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      authorization = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final request = dio.get('/api/v1/products');
    await tokens.started.future;
    // Account switched / logged out during token read
    await box.put('user_id', 'artisan_2');
    tokens.result.complete('ARTISAN_1_TOKEN');
    try { await request; } on DioException { /* Local rejection is acceptable. */ }
    dio.close();
    await Hive.close();
    await dir.delete(recursive: true);
    expect(authorization, isNull, reason: 'Stale token from superseded account must be suppressed');
  });

  test('normal artisan request successfully attaches bearer token', () async {
    final dir = await Directory.systemTemp.createTemp('session_normal_');
    Hive.init(dir.path);
    final box = await Hive.openBox('auth_box');
    await box.put('is_authenticated', true);
    await box.put('user_id', 'artisan_normal');
    final tokens = DelayedTokens();
    final dio = AuthenticatedHttpClient.create(baseUrl: 'https://fixture.invalid', tokenStorage: tokens);
    String? authorization;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      authorization = options.headers['Authorization'] as String?;
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final request = dio.get('/api/v1/products');
    await tokens.started.future;
    tokens.result.complete('VALID_ARTISAN_TOKEN');
    await request;
    dio.close();
    await Hive.close();
    await dir.delete(recursive: true);
    expect(authorization, 'Bearer VALID_ARTISAN_TOKEN', reason: 'Normal artisan session must attach valid token');
  });

  test('stored drafts and credentials remain preserved during session transition checks', () async {
    final dir = await Directory.systemTemp.createTemp('session_preservation_');
    Hive.init(dir.path);
    final authBox = await Hive.openBox('auth_box');
    final draftBox = await Hive.openBox('draft_box');
    await authBox.put('is_authenticated', true);
    await authBox.put('user_id', 'artisan_preserve');
    await authBox.put('phone_number', '9876543210');
    await draftBox.put('active_draft_snapshot', '{"draft_id":"d_123","__version":1}');

    final tokens = DelayedTokens();
    final dio = AuthenticatedHttpClient.create(baseUrl: 'https://fixture.invalid', tokenStorage: tokens);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {}));
    }));
    final request = dio.get('/api/v1/products');
    await tokens.started.future;
    await authBox.put('is_ngo_simulation', true);
    tokens.result.complete('PRESERVED_TOKEN');
    try {
      await request;
    } on DioException {
      // Local rejection expected when session mode transitions to simulation
    }
    dio.close();

    // Verify offline draft and credentials are fully intact
    expect(draftBox.get('active_draft_snapshot'), '{"draft_id":"d_123","__version":1}');
    expect(authBox.get('user_id'), 'artisan_preserve');
    expect(authBox.get('phone_number'), '9876543210');

    await Hive.close();
    await dir.delete(recursive: true);
  });
}
