import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/queue_item.dart';

/// Result of the initial upload call.
class UploadResult {
  UploadResult({
    required this.jobId,
    this.immediatelyCompleted = false,
    this.resultPayload,
  });

  final String jobId;

  /// True if the backend processed synchronously and there's nothing
  /// left to poll for (rare — most AI steps here are async).
  final bool immediatelyCompleted;

  final Map<String, dynamic>? resultPayload;
}

/// Result of polling an in-progress job.
class JobStatusResult {
  JobStatusResult({
    required this.isComplete,
    this.isFailed = false,
    this.resultPayload,
    this.errorMessage,
  });

  final bool isComplete;
  final bool isFailed;
  final Map<String, dynamic>? resultPayload;
  final String? errorMessage;
}

/// Abstraction over "however the backend actually works", so the sync
/// engine can be built and fully tested before the real API exists.
/// Swap [MockUploadApi] for [RealUploadApi] on integration day — nothing
/// else in the app needs to change.
abstract class UploadApi {
  Future<UploadResult> uploadImage({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
  });

  Future<UploadResult> uploadVoiceNote({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
  });

  Future<JobStatusResult> checkStatus(String jobId);
}

/// In-memory fake backend. Simulates network latency, occasional flaky
/// failures, and async job processing — enough to exercise every branch
/// of the sync engine (retry, backoff, polling) without a real server.
class MockUploadApi implements UploadApi {
  MockUploadApi({
    this.failureRate = 0.25,
    this.processingDelay = const Duration(seconds: 4),
  });

  final double failureRate;
  final Duration processingDelay;
  final _rng = Random();
  final Map<String, DateTime> _jobStartedAt = {};
  final Map<String, QueueItemType> _jobTypes = {};

  @override
  Future<UploadResult> uploadImage({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
    }) =>
      _fakeUpload(idempotencyKey, QueueItemType.imageEnhance);

  @override
  Future<UploadResult> uploadVoiceNote({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
    }) =>
      _fakeUpload(idempotencyKey, QueueItemType.voiceCatalog);

    Future<UploadResult> _fakeUpload(String idempotencyKey, QueueItemType type) async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (_rng.nextDouble() < failureRate) {
      throw DioException(
        requestOptions: RequestOptions(path: '/mock'),
        message: 'Simulated flaky network failure',
      );
    }

    final jobId = 'mock-job-$idempotencyKey';
    _jobStartedAt[jobId] = DateTime.now();
    _jobTypes[jobId] = type;

    // The image enhancer module is not implemented yet, so do not fake a
    // completed enhancement result. Keep the job in processing/pending UI state
    // until the real AI module is connected.
    return UploadResult(
      jobId: jobId,
      immediatelyCompleted: type == QueueItemType.voiceCatalog,
      resultPayload: type == QueueItemType.voiceCatalog
          ? {
              'transcript': 'This is a handcrafted terracotta floral vase made from natural river clay.',
              'titleEn': 'Handcrafted Terracotta Floral Vase',
              'titleHi': 'हस्तनिर्मित मिट्टी का फूलदान',
              'descriptionEn': 'A traditional terracotta vase shaped by hand from natural clay.',
              'descriptionHi': 'प्राकृतिक मिट्टी से हाथ से बनाया गया पारंपरिक मिट्टी का फूलदान।',
              'category': 'Pottery',
              'tags': ['terracotta', 'pottery', 'handcrafted'],
            }
          : null,
    );
  }

  @override
  Future<JobStatusResult> checkStatus(String jobId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final startedAt = _jobStartedAt[jobId];
    if (startedAt == null) {
      return JobStatusResult(isComplete: false, isFailed: true, errorMessage: 'Unknown job');
    }

    final elapsed = DateTime.now().difference(startedAt);
    final type = _jobTypes[jobId];

    // Image enhancement is intentionally left pending until the real module is
    // wired up. The UI will show a placeholder state until then.
    if (type == QueueItemType.imageEnhance) {
      return JobStatusResult(isComplete: false);
    }

    if (elapsed < processingDelay) {
      return JobStatusResult(isComplete: false);
    }

    return JobStatusResult(
      isComplete: true,
      resultPayload: {
        'transcript': 'This is a handcrafted terracotta floral vase made from natural river clay.',
        'titleEn': 'Handcrafted Terracotta Floral Vase',
        'titleHi': 'हस्तनिर्मित मिट्टी का फूलदान',
        'descriptionEn': 'A traditional terracotta vase shaped by hand from natural clay.',
        'descriptionHi': 'प्राकृतिक मिट्टी से हाथ से बनाया गया पारंपरिक मिट्टी का फूलदान।',
        'category': 'Pottery',
        'tags': ['terracotta', 'pottery', 'handcrafted'],
      },
    );
  }
}

/// Talks to the actual backend once it exists. Swap this in for
/// [MockUploadApi] with zero changes anywhere else in the app.
class RealUploadApi implements UploadApi {
  RealUploadApi({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(minutes: 2), // large images on slow uplinks
              receiveTimeout: const Duration(minutes: 3),
            ));

  final String baseUrl;
  final Dio _dio;

  @override
  Future<UploadResult> uploadImage({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path),
      'idempotency_key': idempotencyKey,
      'product_draft_id': productDraftId,
    });

    final response = await _dio.post('/api/v1/catalog/enhance-image', data: formData);
    final data = response.data as Map<String, dynamic>;
    final enhancedUrl = data['enhanced_url'] as String? ?? data['enhanced_image_url'] as String?;

    final cleanPrefix = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final resolvedUrl = (enhancedUrl != null && !enhancedUrl.startsWith('http'))
        ? '$cleanPrefix${enhancedUrl.startsWith('/') ? enhancedUrl : '/$enhancedUrl'}'
        : (enhancedUrl ?? file.path);

    return UploadResult(
      jobId: idempotencyKey,
      immediatelyCompleted: true,
      resultPayload: {
        'enhancedImageUrl': resolvedUrl,
        'originalImageUrl': data['original_url'],
      },
    );
  }

  @override
  Future<UploadResult> uploadVoiceNote({
    required File file,
    required String idempotencyKey,
    required String productDraftId,
  }) =>
      _upload('/v1/uploads/voice', file, idempotencyKey, productDraftId);

  Future<UploadResult> _upload(
    String path,
    File file,
    String idempotencyKey,
    String productDraftId,
  ) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
      'idempotency_key': idempotencyKey,
      'product_draft_id': productDraftId,
    });

    final response = await _dio.post(path, data: formData);
    final data = response.data as Map<String, dynamic>;

    return UploadResult(
      jobId: (data['job_id'] ?? idempotencyKey) as String,
      immediatelyCompleted: data['status'] == 'completed',
      resultPayload: data['result'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<JobStatusResult> checkStatus(String jobId) async {
    final response = await _dio.get('/v1/jobs/$jobId');
    final data = response.data as Map<String, dynamic>;
    final status = data['status'] as String;

    return JobStatusResult(
      isComplete: status == 'completed',
      isFailed: status == 'failed',
      resultPayload: data['result'] as Map<String, dynamic>?,
      errorMessage: data['error'] as String?,
    );
  }
}
