import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/offline_sync/offline_sync_service.dart';
import '../../core/utils/image_compressor.dart';

abstract class ImageEnhancerService {
  Future<String> enhanceImage(String inputPathOrUrl, {String? draftId});
  List<String> getSampleCraftImages();
}

/// Real HTTP client connecting to FastAPI backend `/api/v1/catalog/enhance-image`
/// with client-side compression, timeouts, retry logic, and offline sync queue fallback.
class HttpImageEnhancerService implements ImageEnhancerService {
  HttpImageEnhancerService({
    String? baseUrl,
    Dio? dio,
    this.maxRetries = 1,
    this.onFallbackQueue,
  }) : baseUrl = baseUrl ?? _defaultBaseUrl(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? _defaultBaseUrl(),
               connectTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(
                 minutes: 2,
               ), // Large payload over 2G/3G
               receiveTimeout: const Duration(minutes: 5),
               headers: {'Accept': 'application/json'},
             ),
           );

  final String baseUrl;
  final Dio _dio;
  final int maxRetries;
  final Future<void> Function(File file, String? draftId)? onFallbackQueue;

  static String _defaultBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) return configuredBaseUrl;

    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static const List<String> _sampleCrafts = [
    'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=800&q=80',
    'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?auto=format&fit=crop&w=800&q=80',
  ];

  @override
  Future<String> enhanceImage(String inputPathOrUrl, {String? draftId}) async {
    if (inputPathOrUrl.isEmpty) {
      return _sampleCrafts[0];
    }

    // If already a web URL, return directly
    if (inputPathOrUrl.startsWith('http://') ||
        inputPathOrUrl.startsWith('https://')) {
      return inputPathOrUrl;
    }

    final rawFile = File(inputPathOrUrl);
    if (!await rawFile.exists()) {
      return inputPathOrUrl;
    }

    // Step 1: Client-side compression before network transmission (optimized for rural 2G/3G)
    final compressedFile = await ImageCompressor.compressForUpload(rawFile);

    int attempts = 0;
    while (attempts <= maxRetries) {
      try {
        attempts++;
        debugPrint(
          '[ImageEnhancer] Attempt $attempts: POST $baseUrl/api/v1/catalog/enhance-image (${compressedFile.path})',
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
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          final enhancedPath =
              (data['enhanced_url'] ?? data['enhanced_image_url']) as String?;
          if (enhancedPath != null && enhancedPath.isNotEmpty) {
            String fullUrl;
            if (enhancedPath.startsWith('http://') ||
                enhancedPath.startsWith('https://')) {
              fullUrl = enhancedPath;
            } else {
              final cleanPrefix = baseUrl.endsWith('/')
                  ? baseUrl.substring(0, baseUrl.length - 1)
                  : baseUrl;
              final cleanPath = enhancedPath.startsWith('/')
                  ? enhancedPath
                  : '/$enhancedPath';
              fullUrl = '$cleanPrefix$cleanPath';
            }
            debugPrint('[ImageEnhancer] Success: $fullUrl');
            return fullUrl;
          }
        }
      } catch (e) {
        debugPrint('[ImageEnhancer] Attempt $attempts failed with error: $e');
        if (attempts > maxRetries) {
          // All retries exhausted -> Fallback to Offline Retry Queue
          await _fallbackToOfflineQueue(compressedFile, draftId);
          return inputPathOrUrl;
        }
        // Brief exponential backoff between retries
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }

    return inputPathOrUrl;
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
    } catch (_) {
      // Avoid failing the caller if offline queue persistence encounters an error
    }
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
  Future<String> enhanceImage(String inputPathOrUrl, {String? draftId}) async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (inputPathOrUrl.isEmpty) {
      return _sampleCrafts[0];
    }
    return inputPathOrUrl;
  }

  @override
  List<String> getSampleCraftImages() {
    return List.unmodifiable(_sampleCrafts);
  }
}
