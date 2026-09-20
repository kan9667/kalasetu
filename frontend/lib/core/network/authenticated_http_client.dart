import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../storage/secure_token_storage.dart';
import 'active_session_manager.dart';
import 'session_expired_exception.dart';

/// Dio interceptor providing automatic Bearer authentication and request idempotency.
class AuthInterceptor extends Interceptor {
  final SecureTokenStorage _tokenStorage;
  final VoidCallback? _onUnauthorized;

  AuthInterceptor({
    SecureTokenStorage? tokenStorage,
    this._onUnauthorized,
  }) : _tokenStorage = tokenStorage ?? SecureTokenStorage();

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['Accept'] = 'application/json';

    // Invariant: Fail closed when session initialization is incomplete
    if (!ActiveSessionManager.isSessionReady()) {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: StateError('Session initialization is incomplete (auth_box not initialized).'),
        ),
      );
    }

    final modeBefore = ActiveSessionManager.getActiveSessionModeSync();
    final userIdBefore = ActiveSessionManager.getCurrentUserIdSync();

    if (modeBefore == ActiveSessionMode.ngoSimulation) {
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    if (modeBefore == ActiveSessionMode.unauthenticated) {
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    // modeBefore == ActiveSessionMode.artisan
    final token = await _tokenStorage.getToken();

    // Invariant: Re-check session state AFTER the async boundary before attaching credentials
    if (!ActiveSessionManager.isSessionReady()) {
      options.headers.remove('Authorization');
      return handler.reject(
        DioException(
          requestOptions: options,
          error: StateError('Session storage invalidated during token retrieval.'),
        ),
      );
    }

    final modeAfter = ActiveSessionManager.getActiveSessionModeSync();
    final userIdAfter = ActiveSessionManager.getCurrentUserIdSync();

    if (modeAfter == ActiveSessionMode.ngoSimulation) {
      // Switched into NGO simulation during token retrieval: MUST NOT attach artisan token!
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    if (modeAfter != ActiveSessionMode.artisan || userIdAfter != userIdBefore) {
      // Switched account or logged out during token retrieval: fail closed
      options.headers.remove('Authorization');
      return handler.reject(
        DioException(
          requestOptions: options,
          error: SessionExpiredException('Session invalidated during token retrieval.', 401),
        ),
      );
    }

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      debugPrint('[AuthInterceptor] Received $statusCode Unauthorized/Forbidden for ${err.requestOptions.path}');
      _onUnauthorized?.call();
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: err.type,
          error: SessionExpiredException(
            statusCode == 403
                ? 'Access forbidden (403).'
                : 'Session expired or unauthorized (401).',
            statusCode,
          ),
        ),
      );
    }
    return handler.next(err);
  }
}

/// Factory for pre-configured, authenticated [Dio] instances.
class AuthenticatedHttpClient {
  static Dio create({
    String? baseUrl,
    SecureTokenStorage? tokenStorage,
    VoidCallback? onUnauthorized,
    Duration connectTimeout = const Duration(seconds: 15),
    Duration receiveTimeout = const Duration(seconds: 30),
    Duration sendTimeout = const Duration(seconds: 30),
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onUnauthorized: onUnauthorized,
      ),
    );

    return dio;
  }
}
