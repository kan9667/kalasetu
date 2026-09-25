import 'package:dio/dio.dart';
import 'dart:io';
import '../../core/config/api_config.dart';
import '../../core/network/authenticated_http_client.dart';
import '../../core/network/request_session_context.dart';
import '../../core/network/session_expired_exception.dart';
import '../../core/storage/secure_token_storage.dart';
import '../models/social_draft.dart';

// ── Typed Exceptions ─────────────────────────────────────────────────────────

/// The AI returned an unexpected response after retry. Show "try again".
class SocialMediaGenerationException implements Exception {
  final String message;
  const SocialMediaGenerationException(this.message);
  @override
  String toString() => 'SocialMediaGenerationException: $message';
}

/// The user has hit the server-side rate limit for regenerations.
class SocialMediaRateLimitException implements Exception {
  final String message;
  const SocialMediaRateLimitException(this.message);
  @override
  String toString() => 'SocialMediaRateLimitException: $message';
}

/// Generic network / connectivity failure.
class SocialMediaNetworkException implements Exception {
  final String message;
  const SocialMediaNetworkException(this.message);
  @override
  String toString() => 'SocialMediaNetworkException: $message';
}

// ── Abstract Service ──────────────────────────────────────────────────────────

abstract class SocialMediaService {
  /// Generate a social media draft from an existing published listing.
  Future<SocialDraft> generateForListing({
    required String listingId,
    required String imageUrl,
    String title,
    String category,
    String description,
    List<String> materials,
    String tone,
    String locale,
    String source,
    String channel,
    String? idempotencyKey,
  });

  /// Generate a draft while still in the Add Product flow (before publish).
  Future<SocialDraft> generateForDraft({
    required String draftKey,
    required String imageUrl,
    String title,
    String category,
    String description,
    List<String> materials,
    String tone,
    String locale,
    String channel,
    String? idempotencyKey,
  });

  /// Persist the (possibly user-edited) draft.
  Future<SocialDraft> saveDraft({
    required String draftId,
    required String caption,
    required List<String> hashtags,
    bool editedByUser,
    String? idempotencyKey,
  });

  /// Reload a previously saved draft by its ID.
  Future<SocialDraft> loadDraft(String draftId);

  /// Find a saved draft for the current listing/draft image and channel.
  Future<SocialDraft?> loadDraftForImage({
    String? listingId,
    String? draftKey,
    required String imageUrl,
    String? channel,
  });

  Future<void> linkDraftsToListing({
    required String draftKey,
    required String listingId,
    String? idempotencyKey,
  });

  Future<String> uploadImage(String imagePath, {String? idempotencyKey});
}

// ── HTTP Implementation ───────────────────────────────────────────────────────

class HttpSocialMediaService implements SocialMediaService {
  HttpSocialMediaService({String? baseUrl, Dio? dio, SecureTokenStorage? tokenStorage})
      : _base = baseUrl ?? ApiConfig.baseUrl,
        _dio = dio ??
            AuthenticatedHttpClient.create(
              baseUrl: baseUrl ?? ApiConfig.baseUrl,
              tokenStorage: tokenStorage,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
            );

  final String _base;
  final Dio _dio;

  @override
  Future<SocialDraft> generateForListing({
    required String listingId,
    required String imageUrl,
    String title = '',
    String category = '',
    String description = '',
    List<String> materials = const [],
    String tone = 'warm and authentic',
    String locale = 'en-US',
    String source = 'catalogue',
    String channel = 'instagram',
    String? idempotencyKey,
  }) async {
    final body = {
      'image_url': imageUrl,
      'listing_id': listingId,
      'title': title,
      'category': category,
      'description': description,
      'materials': materials,
      'tone': tone,
      'locale': locale,
      'source': source,
      'channel': channel,
    };
    return _post('$_base/api/v1/social-drafts/generate', body, idempotencyKey: idempotencyKey);
  }

  @override
  Future<SocialDraft> generateForDraft({
    required String draftKey,
    required String imageUrl,
    String title = '',
    String category = '',
    String description = '',
    List<String> materials = const [],
    String tone = 'warm and authentic',
    String locale = 'en-US',
    String channel = 'instagram',
    String? idempotencyKey,
  }) async {
    final body = {
      'draft_key': draftKey,
      'image_url': imageUrl,
      'title': title,
      'category': category,
      'description': description,
      'materials': materials,
      'tone': tone,
      'locale': locale,
      'source': 'add_flow',
      'channel': channel,
    };
    return _post('$_base/api/v1/social-drafts/generate', body, idempotencyKey: idempotencyKey);
  }

  @override
  Future<SocialDraft> saveDraft({
    required String draftId,
    required String caption,
    required List<String> hashtags,
    bool editedByUser = true,
    String? idempotencyKey,
  }) async {
    final sessionExtra = RequestSessionContext.capture().toExtra();
    final body = {
      'caption': caption,
      'hashtags': hashtags,
      'edited_by_user': editedByUser,
    };
    final operationKey = idempotencyKey ??
        'idem_socsave_${DateTime.now().microsecondsSinceEpoch}_${draftId.hashCode.abs()}';
    try {
      final response = await _dio.put(
        '$_base/api/v1/social-drafts/$draftId',
        data: body,
        options: Options(
          headers: {'Idempotency-Key': operationKey},
          extra: sessionExtra,
        ),
      );
      return SocialDraft.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<SocialDraft> loadDraft(String draftId) async {
    try {
      final response = await _dio.get('$_base/api/v1/social-drafts/$draftId');
      return SocialDraft.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<SocialDraft?> loadDraftForImage({
    String? listingId,
    String? draftKey,
    required String imageUrl,
    String? channel,
  }) async {
    try {
      final response = await _dio.get(
        '$_base/api/v1/social-drafts/lookup',
        queryParameters: {
          'image_url': imageUrl,
          'listing_id': ?listingId,
          'draft_key': ?draftKey,
          'channel': ?channel,
        },
      );
      return SocialDraft.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _mapDioError(e);
    }
  }

  @override
  Future<void> linkDraftsToListing({
    required String draftKey,
    required String listingId,
    String? idempotencyKey,
  }) async {
    final sessionExtra = RequestSessionContext.capture().toExtra();
    final operationKey = idempotencyKey ??
        'idem_soclink_${DateTime.now().microsecondsSinceEpoch}_${listingId.hashCode.abs()}';
    try {
      await _dio.post(
        '$_base/api/v1/social-drafts/link',
        queryParameters: {'draft_key': draftKey, 'listing_id': listingId},
        options: Options(
          headers: {'Idempotency-Key': operationKey},
          extra: sessionExtra,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<String> uploadImage(String imagePath, {String? idempotencyKey}) async {
    final sessionExtra = RequestSessionContext.capture().toExtra();
    final operationKey = idempotencyKey ??
        'idem_socup_${DateTime.now().microsecondsSinceEpoch}_${imagePath.hashCode.abs()}';
    try {
      final file = File(imagePath);
      final response = await _dio.post(
        '$_base/api/v1/catalog/upload-image',
        data: FormData.fromMap({
          'image': await MultipartFile.fromFile(
            file.path,
            filename: file.uri.pathSegments.last,
          ),
        }),
        options: Options(
          headers: {'Idempotency-Key': operationKey},
          extra: sessionExtra,
        ),
      );
      final imageUrl = (response.data as Map<String, dynamic>)['image_url'] as String;
      return imageUrl.startsWith('http') ? imageUrl : '$_base$imageUrl';
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<SocialDraft> _post(String url, Map<String, dynamic> body, {String? idempotencyKey}) async {
    final sessionExtra = RequestSessionContext.capture().toExtra();
    final operationKey = idempotencyKey ??
        'idem_soc_${DateTime.now().microsecondsSinceEpoch}_${url.hashCode.abs()}';
    try {
      final response = await _dio.post(
        url,
        data: body,
        options: Options(
          headers: {'Idempotency-Key': operationKey},
          extra: sessionExtra,
        ),
      );
      return SocialDraft.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Exception _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403 || e.error is SessionExpiredException) {
      return e.error is SessionExpiredException
          ? e.error as SessionExpiredException
          : SessionExpiredException(
              status == 403 ? 'Access forbidden (403).' : 'Session expired or unauthorized (401).',
              status,
            );
    }
    if (status == 429) {
      final detail = (e.response?.data is Map)
          ? (e.response!.data['detail'] as String? ?? 'Rate limit exceeded')
          : 'Too many requests. Try again in a while.';
      return SocialMediaRateLimitException(detail);
    }
    if (status == 502 || status == 503) {
      final detail = (e.response?.data is Map)
          ? (e.response!.data['detail'] as String? ?? 'AI service error')
          : 'AI generation failed. Please try again.';
      return SocialMediaGenerationException(detail);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const SocialMediaNetworkException(
        'No internet connection or the server is unreachable.',
      );
    }
    return SocialMediaNetworkException(e.message ?? 'Unknown error');
  }
}
