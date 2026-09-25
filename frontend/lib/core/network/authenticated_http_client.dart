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
          response: Response(requestOptions: options, statusCode: 401),
          type: DioExceptionType.badResponse,
          error: StateError(
            'Session initialization is incomplete (auth_box not initialized).',
          ),
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

    final method = options.method.toUpperCase();
    final bool isMutation = method == 'POST' || method == 'PUT' || method == 'DELETE' || method == 'PATCH';

    // Requirement 1: Protected mutations MUST have explicit, non-empty session context.
    // Never manufacture missing context from the current account inside the interceptor.
    if (isMutation) {
      if (expectedUserId == null ||
          expectedUserId.trim().isEmpty ||
          expectedSessionGen == null ||
          expectedSessionGen < 0 ||
          expectedBackend == null ||
          expectedBackend.trim().isEmpty) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Missing required session context for protected mutation ($method ${options.path}).',
              401,
            ),
          ),
        );
      }
    }

    // Requirement 2: Validate the actual outgoing request URI's origin against the operation's expected backend
    if (expectedBackend != null && expectedBackend.isNotEmpty) {
      String? expectedNormalized;
      try {
        expectedNormalized = PrivateMediaCache.normalizeBackendOrigin(expectedBackend);
      } catch (_) {
        expectedNormalized = null;
      }
      if (expectedNormalized == null || expectedNormalized.isEmpty) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Malformed expected backend origin: $expectedBackend',
              401,
            ),
          ),
        );
      }

      // 1) Validate actual outgoing request URI origin
      String? requestOrigin;
      try {
        requestOrigin = PrivateMediaCache.normalizeBackendOrigin(options.uri.toString());
      } catch (_) {
        requestOrigin = null;
      }
      if (requestOrigin == null || requestOrigin != expectedNormalized) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Request URI origin ($requestOrigin) does not match expected backend ($expectedNormalized).',
              401,
            ),
          ),
        );
      }

      // 2) Validate currently active backend origin
      String? activeBackendOrigin;
      try {
        activeBackendOrigin = PrivateMediaCache.normalizeBackendOrigin(ApiConfig.baseUrl);
      } catch (_) {
        activeBackendOrigin = null;
      }
      if (activeBackendOrigin == null || activeBackendOrigin != expectedNormalized) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Currently active backend ($activeBackendOrigin) does not match expected backend ($expectedNormalized).',
              401,
            ),
          ),
        );
      }
    }

    // Requirement 3: On logout, account/backend/generation changes, or entry into NGO simulation,
    // reject bound operations completely. Merely removing Authorization and forwarding the request is insufficient.
    if (expectedUserId != null && expectedUserId.isNotEmpty) {
      if (modeBefore != ActiveSessionMode.artisan) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Bound operation requires active artisan session, but current mode is $modeBefore.',
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
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
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
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Session generation mismatch before dispatch (expected $expectedSessionGen, active is $genBefore).',
              401,
            ),
          ),
        );
      }
    } else {
      // Unbound request (e.g. read-only GET without explicit context)
      if (modeBefore == ActiveSessionMode.ngoSimulation) {
        options.headers.remove('Authorization');
        return handler.next(options);
      }

      if (modeBefore == ActiveSessionMode.unauthenticated) {
        options.headers.remove('Authorization');
        return handler.next(options);
      }
    }

    // modeBefore == ActiveSessionMode.artisan
    final token = await _tokenStorage.getToken();

    // Invariant: Re-check session state AFTER the async boundary before attaching credentials
    if (!ActiveSessionManager.isSessionReady()) {
      options.headers.remove('Authorization');
      return handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
          type: DioExceptionType.badResponse,
          error: SessionExpiredException('Session storage invalidated during token retrieval.', 401),
        ),
      );
    }

    final modeAfter = ActiveSessionManager.getActiveSessionModeSync();
    final userIdAfter = ActiveSessionManager.getCurrentUserIdSync();
    final genAfter = ActiveSessionManager.sessionGeneration;

    // Re-verify after async token retrieval:
    if (expectedUserId != null && expectedUserId.isNotEmpty) {
      if (modeAfter != ActiveSessionMode.artisan) {
        options.headers.remove('Authorization');
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 401),
            type: DioExceptionType.badResponse,
            error: SessionExpiredException(
              'Session transitioned to $modeAfter during token retrieval for bound operation.',
              401,
            ),
          ),
        );
      }
      if (userIdAfter != expectedUserId || userIdAfter != userIdBefore) {
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
        final expectedNorm = PrivateMediaCache.normalizeBackendOrigin(expectedBackend);
        final reqBackend = PrivateMediaCache.normalizeBackendOrigin(options.uri.toString());
        if (reqBackend != expectedNorm) {
          options.headers.remove('Authorization');
          return handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
              type: DioExceptionType.badResponse,
              error: SessionExpiredException(
                'Request URI origin changed during token retrieval ($reqBackend != $expectedNorm).',
                401,
              ),
            ),
          );
        }
        final activeBackendAfter = PrivateMediaCache.normalizeBackendOrigin(ApiConfig.baseUrl);
        if (activeBackendAfter != expectedNorm) {
          options.headers.remove('Authorization');
          return handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401),
              type: DioExceptionType.badResponse,
              error: SessionExpiredException(
                'Active backend origin changed during token retrieval ($activeBackendAfter != $expectedNorm).',
                401,
              ),
            ),
          );
        }
      }
    } else {
      if (modeAfter == ActiveSessionMode.ngoSimulation) {
        options.headers.remove('Authorization');
        return handler.next(options);
      }
      if (modeAfter != ActiveSessionMode.artisan || userIdAfter != userIdBefore || genAfter != genBefore) {
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
    HttpClientAdapter? adapter,
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

    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }

    dio.interceptors.add(
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onUnauthorized: onUnauthorized,
      ),
    );

    return dio;
  }
}
