import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/authenticated_http_client.dart';
import '../../core/network/request_session_context.dart';
import '../../core/network/session_expired_exception.dart';
import '../../core/offline_sync/offline_sync_service.dart';
import '../../core/storage/secure_token_storage.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/config/api_config.dart';
import '../../core/storage/private_media_cache.dart';

/// Strongly-typed result of an image enhancement operation preserving
/// server-returned media identity, lineage, and degradation metadata.
class EnhancedImageResult {
  final String displayPath;
  final String? mediaId;
  final String? originalMediaId;
  final String? sha256Checksum;
  final bool isDegraded;
  final String? degradedReason;
  final String status;

  const EnhancedImageResult({
    required this.displayPath,
    this.mediaId,
    this.originalMediaId,
    this.sha256Checksum,
    this.isDegraded = false,
    this.degradedReason,
    this.status = 'ready',
  });

  Map<String, dynamic> toJson() => {
    'display_path': displayPath,
    'media_id': mediaId,
    'original_media_id': originalMediaId,
    'sha256_checksum': sha256Checksum,
    'is_degraded': isDegraded,
    'degraded_reason': degradedReason,
    'status': status,
  };

  factory EnhancedImageResult.fromJson(Map<String, dynamic> json) => EnhancedImageResult(
    displayPath: json['display_path'] as String? ?? json['displayPath'] as String? ?? '',
    mediaId: json['media_id'] as String? ?? json['mediaId'] as String?,
    originalMediaId: json['original_media_id'] as String? ?? json['originalMediaId'] as String?,
    sha256Checksum: json['sha256_checksum'] as String? ?? json['sha256Checksum'] as String?,
    isDegraded: json['is_degraded'] as bool? ?? json['isDegraded'] as bool? ?? false,
    degradedReason: json['degraded_reason'] as String? ?? json['degradedReason'] as String?,
    status: json['status'] as String? ?? 'ready',
  );
}

abstract class ImageEnhancerService {
  Future<EnhancedImageResult> enhanceImage(
    String inputPathOrUrl, {
    String? draftId,
    String? idempotencyKey,
  });
  List<String> getSampleCraftImages();
}

/// Real HTTP client connecting to FastAPI backend `/api/v1/catalog/enhance-image`
/// with Bearer authentication, stable idempotency keys, client-side compression,
/// session expiration mapping, and offline sync queue fallback.
class HttpImageEnhancerService implements ImageEnhancerService {
  HttpImageEnhancerService({
    String? baseUrl,
    Dio? dio,
    SecureTokenStorage? tokenStorage,
    this.maxRetries = 1,
    this.onFallbackQueue,
  }) : baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _dio =
           dio ??
           AuthenticatedHttpClient.create(
             baseUrl: baseUrl ?? ApiConfig.baseUrl,
             tokenStorage: tokenStorage,
             connectTimeout: const Duration(seconds: 20),
             sendTimeout: const Duration(minutes: 2),
             receiveTimeout: const Duration(minutes: 5),
           );

  final String baseUrl;
  final Dio _dio;
  final int maxRetries;
  final Future<void> Function(File file, String? draftId)? onFallbackQueue;

  static const List<String> _sampleCrafts = [
    'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?auto=format&fit=crop&w=800&q=80',
  ];

  @override
  Future<EnhancedImageResult> enhanceImage(
    String inputPathOrUrl, {
    String? draftId,
    String? idempotencyKey,
  }) async {
    if (inputPathOrUrl.isEmpty) {
      return EnhancedImageResult(
        displayPath: _sampleCrafts[0],
        status: 'ready',
      );
    }

    final sessionExtra = RequestSessionContext.capture().toExtra();

    // If already a web URL, return directly
    if (inputPathOrUrl.startsWith('http://') ||
        inputPathOrUrl.startsWith('https://')) {
      return EnhancedImageResult(
        displayPath: inputPathOrUrl,
        status: 'ready',
      );
    }

    final rawFile = File(inputPathOrUrl);
    if (!await rawFile.exists()) {
      return EnhancedImageResult(
        displayPath: inputPathOrUrl,
        isDegraded: true,
        degradedReason: 'Input raw photo file does not exist on disk.',
        status: 'failed',
      );
    }

    // Step 1: Client-side compression before network transmission
    final compressedFile = await ImageCompressor.compressForUpload(rawFile);

    // Stable idempotency key created once per logical operation and preserved across retries
    final operationKey = idempotencyKey ??
        (draftId != null && draftId.isNotEmpty
            ? 'idem_img_${draftId}_${compressedFile.path.hashCode.abs()}'
            : 'idem_img_${compressedFile.path.hashCode.abs()}');

    int attempts = 0;
    while (attempts <= maxRetries) {
      try {
        attempts++;
        final activeUrl = baseUrl.isNotEmpty ? baseUrl : ApiConfig.baseUrl;
        _dio.options.baseUrl = activeUrl;

        debugPrint(
          '[ImageEnhancer] Attempt $attempts: POST $activeUrl/api/v1/catalog/enhance-image (${compressedFile.path}) [Idempotency-Key: $operationKey]',
        );
        final formData = FormData.fromMap({
          'image': await MultipartFile.fromFile(
            compressedFile.path,
            filename: compressedFile.path.split('/').last,
          ),
        });

        final response = await _dio.post(
          '/api/v1/catalog/enhance-image',
          data: formData,
          options: Options(
            headers: {'Idempotency-Key': operationKey},
            extra: sessionExtra,
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          final mediaId = data['media_id'] as String?;
          final originalMediaId = data['original_media_id'] as String?;
          final sha256Checksum = data['sha256_checksum'] as String?;
          final isDegraded = data['is_degraded'] as bool? ?? false;
          final degradedReason = data['degraded_reason'] as String?;
          final status = data['status'] as String? ?? 'ready';

          final enhancedPath =
              (data['enhanced_url'] ?? data['enhanced_image_url']) as String?;
          String finalDisplayPath = inputPathOrUrl;
          if (enhancedPath != null && enhancedPath.isNotEmpty) {
            String fullUrl;
            if (enhancedPath.startsWith('http://') ||
                enhancedPath.startsWith('https://')) {
              fullUrl = enhancedPath;
            } else {
              final cleanPrefix = activeUrl.endsWith('/')
                  ? activeUrl.substring(0, activeUrl.length - 1)
                  : activeUrl;
              final cleanPath = enhancedPath.startsWith('/')
                  ? enhancedPath
                  : '/$enhancedPath';
              fullUrl = '$cleanPrefix$cleanPath';
            }
            finalDisplayPath = fullUrl;

            try {
              if (mediaId != null && mediaId.isNotEmpty) {
                final cachedFile = await PrivateMediaCache.instance.downloadAndCacheMedia(
                  mediaId: mediaId,
                  downloadUrl: fullUrl,
                );
                finalDisplayPath = cachedFile.path;
              }
            } catch (dlErr) {
              debugPrint('[ImageEnhancer] PrivateMediaCache download fallback: $dlErr');
            }
          }

          return EnhancedImageResult(
            displayPath: finalDisplayPath,
            mediaId: mediaId,
            originalMediaId: originalMediaId,
            sha256Checksum: sha256Checksum,
            isDegraded: isDegraded,
            degradedReason: degradedReason,
            status: status,
          );
        }
      } on DioException catch (e) {
        if (e.error is SessionExpiredException ||
            e.response?.statusCode == 401 ||
            e.response?.statusCode == 403) {
          throw e.error is SessionExpiredException
              ? e.error as SessionExpiredException
              : SessionExpiredException(
                  'Session expired (${e.response?.statusCode})',
                  e.response?.statusCode,
                );
        }
        final statusCode = e.response?.statusCode;
        if (statusCode == 409 || statusCode == 413 || statusCode == 422) {
          final msg = e.response?.data is Map ? e.response?.data['detail']?.toString() : e.message;
          throw DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: DioExceptionType.badResponse,
            error: 'Validation error ($statusCode): $msg',
          );
        }
        debugPrint('[ImageEnhancer] Attempt $attempts failed with DioException: $e');
        if (attempts > maxRetries) {
          await _fallbackToOfflineQueue(compressedFile, draftId);
          return EnhancedImageResult(
            displayPath: inputPathOrUrl,
            isDegraded: true,
            degradedReason: 'Network timeout/offline. Queued for offline processing.',
            status: 'offline_queued',
          );
        }
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      } catch (e) {
        if (e is SessionExpiredException) rethrow;
        debugPrint('[ImageEnhancer] Attempt $attempts failed with error: $e');
        if (attempts > maxRetries) {
          await _fallbackToOfflineQueue(compressedFile, draftId);
          return EnhancedImageResult(
            displayPath: inputPathOrUrl,
            isDegraded: true,
            degradedReason: 'Enhancement failed: $e',
            status: 'failed',
          );
        }
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }

    await _fallbackToOfflineQueue(compressedFile, draftId);
    return EnhancedImageResult(
      displayPath: inputPathOrUrl,
      isDegraded: true,
      degradedReason: 'Offline: Image queued for background enhancement.',
      status: 'offline_queued',
    );
  }

  Future<void> _fallbackToOfflineQueue(File file, String? draftId) async {
    try {
      if (onFallbackQueue != null) {
        await onFallbackQueue!(file, draftId);
        return;
      }
      if (OfflineSyncService.instance.isInitialized) {
        await OfflineSyncService.instance.enqueueImage(
          imageFile: file,
          productDraftId:
              draftId ?? 'draft_${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } catch (_) {}
  }

  @override
  List<String> getSampleCraftImages() {
    return List.unmodifiable(_sampleCrafts);
  }
}

class MockImageEnhancerService implements ImageEnhancerService {
  static const List<String> _sampleCrafts = [
    'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?auto=format&fit=crop&w=800&q=80',
  ];

  @override
  Future<EnhancedImageResult> enhanceImage(
    String inputPathOrUrl, {
    String? draftId,
    String? idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (inputPathOrUrl.isEmpty) {
      return EnhancedImageResult(
        displayPath: _sampleCrafts[0],
        status: 'ready',
      );
    }
    return EnhancedImageResult(
      displayPath: inputPathOrUrl,
      isDegraded: false,
      status: 'ready',
    );
  }

  @override
  List<String> getSampleCraftImages() {
    return List.unmodifiable(_sampleCrafts);
  }
}
