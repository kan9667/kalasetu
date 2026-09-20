import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../storage/private_media_cache.dart';
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

    // Allow unauthenticated registration/login public flows without requiring initialized session
    final bool isPublicEndpoint = options.extra['is_public'] == true ||
        options.path.contains('/api/v1/auth/');
    if (isPublicEndpoint) {
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    // Invariant: Fail closed when session initialization is incomplete
    if (!ActiveSessionManager.isSessionReady()) {
      options.headers.remove('Authorization');
      return handler.reject(
        DioException(
          requestOptions: options,
          error: StateError('Session initialization is incomplete (auth_box not initialized).'),
        ),
      );
    }

    final modeBefore = ActiveSessionManager.getActiveSessionModeSync();
    final userIdBefore = ActiveSessionManager.getCurrentUserIdSync();
    final genBefore = ActiveSessionManager.sessionGeneration;

    // Operation identity carried into request boundary
    final expectedUserId = options.extra['expected_user_id'] as String?;
    final expectedSessionGen = options.extra['expected_session_gen'] as int?;
    final expectedBackend = options.extra['expected_backend_origin'] as String?;

    if (expectedUserId != null && expectedUserId.isNotEmpty) {
      // Bound operation must run strictly under initialized artisan session matching initiating identity
      if (modeBefore != ActiveSessionMode.artisan) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            error: SessionExpiredException(
              'Protected operation requires active artisan session, but current mode is $modeBefore.',
              401,
            ),
          ),
        );
      }
      if (userIdBefore != expectedUserId) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            error: SessionExpiredException(
              'Operation owner mismatch before dispatch (expected $expectedUserId, active is $userIdBefore).',
              401,
            ),
          ),
        );
      }
      if (expectedSessionGen != null && genBefore != expectedSessionGen) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            error: SessionExpiredException(
              'Session generation mismatch before dispatch (expected $expectedSessionGen, active is $genBefore).',
              401,
            ),
          ),
        );
      }
      if (expectedBackend != null && expectedBackend.isNotEmpty) {
        final activeBackend = ApiConfig.baseUrl;
        if (PrivateMediaCache.normalizeBackendOrigin(activeBackend) !=
            PrivateMediaCache.normalizeBackendOrigin(expectedBackend)) {
          options.headers.remove('Authorization');
          return handler.reject(
            DioException(
              requestOptions: options,
              error: SessionExpiredException(
                'Backend origin mismatch before dispatch (expected $expectedBackend, active is $activeBackend).',
                401,
              ),
            ),
          );
        }
      }
    }

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
    final genAfter = ActiveSessionManager.sessionGeneration;

    if (modeAfter == ActiveSessionMode.ngoSimulation) {
      // Switched into NGO simulation during token retrieval: MUST NOT attach artisan token!
      options.headers.remove('Authorization');
      return handler.next(options);
    }

    if (expectedUserId != null && expectedUserId.isNotEmpty) {
      if (modeAfter != ActiveSessionMode.artisan ||
          userIdAfter != expectedUserId ||
          userIdAfter != userIdBefore) {
        // Switched account or logged out during token retrieval: fail closed
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Session invalidated or account changed during token retrieval (expected $expectedUserId, active is $userIdAfter).',
              401,
            ),
          ),
        );
      }
      if (expectedSessionGen != null && genAfter != expectedSessionGen) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Session generation bumped during token retrieval (expected $expectedSessionGen, active is $genAfter).',
              401,
            ),
          ),
        );
      }
      if (expectedBackend != null && expectedBackend.isNotEmpty) {
        final activeBackend = ApiConfig.baseUrl;
        if (PrivateMediaCache.normalizeBackendOrigin(activeBackend) !=
            PrivateMediaCache.normalizeBackendOrigin(expectedBackend)) {
          options.headers.remove('Authorization');
          return handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
              type: DioExceptionType.badResponse,
              error: SessionExpiredException(
                'Backend origin changed during token retrieval.',
                401,
              ),
            ),
          );
        }
      }
    } else {
      if (modeAfter != ActiveSessionMode.artisan || userIdAfter != userIdBefore) {
        // Switched account or logged out during token retrieval: fail closed
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException('Session invalidated during token retrieval.', 401),
          ),
        );
      }
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
