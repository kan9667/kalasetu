import 'package:dio/dio.dart';
import 'dart:io';
import '../../core/config/api_config.dart';
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

// ── Abstract Contract ─────────────────────────────────────────────────────────

abstract class SocialMediaService {
  /// Generate a caption + hashtag draft for a **saved** listing.
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
  });

  /// Generate a caption + hashtag draft for an **unsaved** add-flow draft.
  Future<SocialDraft> generateForDraft({
    required String draftKey,
    required String imageUrl,
    String title,
    String category,
    String description,
    List<String> materials,
    String tone,
    String locale,
  });

  /// Persist the (possibly user-edited) draft.
  Future<SocialDraft> saveDraft({
    required String draftId,
    required String caption,
    required List<String> hashtags,
    bool editedByUser,
  });

  /// Reload a previously saved draft by its ID.
  Future<SocialDraft> loadDraft(String draftId);

  /// Find a saved draft for the current listing/draft image.
  Future<SocialDraft?> loadDraftForImage({
    String? listingId,
    String? draftKey,
    required String imageUrl,
  });

  Future<void> linkDraftsToListing({
    required String draftKey,
    required String listingId,
  });

  Future<String> uploadImage(String imagePath);
}

// ── HTTP Implementation ───────────────────────────────────────────────────────

class HttpSocialMediaService implements SocialMediaService {
  HttpSocialMediaService({String? baseUrl, Dio? dio})
      : _base = baseUrl ?? ApiConfig.baseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'Accept': 'application/json'},
              ),
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
  }) async {
    final body = {
      'image_url': imageUrl,
      'title': title,
      'category': category,
      'description': description,
      'materials': materials,
      'tone': tone,
      'locale': locale,
      'source': source,
    };
    return _post('$_base/api/v1/listings/$listingId/social-draft', body);
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
    };
    return _post('$_base/api/v1/listings/unsaved/social-draft', body);
  }

  @override
  Future<SocialDraft> saveDraft({
    required String draftId,
    required String caption,
    required List<String> hashtags,
    bool editedByUser = true,
  }) async {
    final body = {
      'caption': caption,
      'hashtags': hashtags,
      'edited_by_user': editedByUser,
    };
    try {
      final response = await _dio.put(
        '$_base/api/v1/social-drafts/$draftId',
        data: body,
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
  }) async {
    try {
      final response = await _dio.get(
        '$_base/api/v1/social-drafts/lookup',
        queryParameters: {
          'image_url': imageUrl,
          if (listingId != null) 'listing_id': listingId,
          if (draftKey != null) 'draft_key': draftKey,
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
  }) async {
    try {
      await _dio.post(
        '$_base/api/v1/social-drafts/link',
        queryParameters: {'draft_key': draftKey, 'listing_id': listingId},
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<String> uploadImage(String imagePath) async {
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
      );
      final imageUrl = (response.data as Map<String, dynamic>)['image_url'] as String;
      return imageUrl.startsWith('http') ? imageUrl : '$_base$imageUrl';
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<SocialDraft> _post(String url, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post(url, data: body);
      return SocialDraft.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Exception _mapDioError(DioException e) {
    final status = e.response?.statusCode;
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
