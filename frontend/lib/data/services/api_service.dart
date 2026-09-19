import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../models/product.dart';
import '../repositories/auth_repository.dart';

/// Exception thrown when publishing a draft fails due to an outdated revision or content mismatch.
class StaleRevisionException implements Exception {
  final String message;
  final int? serverRevision;
  StaleRevisionException(this.message, {this.serverRevision});

  @override
  String toString() => 'StaleRevisionException: $message';
}

/// Abstract API service contract
abstract class ApiService {
  Future<List<Product>> getProducts({String? artisanId, String? category});
  Future<Product> getProduct(String productId);
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey});
  Future<Product> updateProduct(Product product, {int? expectedRevision, String? idempotencyKey});
  Future<bool> deleteProduct(String id, {String? idempotencyKey});
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  });
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  });
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey});
}

/// Live HTTP implementation connecting to FastAPI `/api/v1/products`
class HttpApiService implements ApiService {
  final Dio _dio;
  final String? _explicitBaseUrl;

  HttpApiService({String? baseUrl, Dio? dio})
      : _explicitBaseUrl = baseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? ApiConfig.baseUrl,
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final authRepo = AuthRepository();
            final token = await authRepo.getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          } catch (_) {}
          return handler.next(options);
        },
      ),
    );
  }

  void _syncBaseUrl() {
    final activeUrl = _explicitBaseUrl ?? ApiConfig.baseUrl;
    _dio.options.baseUrl = activeUrl;
  }

  @override
  Future<List<Product>> getProducts({String? artisanId, String? category}) async {
    _syncBaseUrl();
    try {
      final queryParams = <String, dynamic>{
        if (artisanId != null && artisanId.isNotEmpty) 'artisan_id': artisanId,
        if (category != null && category.isNotEmpty) 'category': category,
        'limit': 100,
      };

      debugPrint('[HttpApiService] GET ${_dio.options.baseUrl}/api/v1/products');
      final response = await _dio.get(
        '/api/v1/products',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        final list = response.data as List<dynamic>;
        return list
            .map((item) => Product.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint('[HttpApiService] getProducts failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Product> getProduct(String productId) async {
    _syncBaseUrl();
    try {
      debugPrint('[HttpApiService] GET ${_dio.options.baseUrl}/api/v1/products/$productId');
      final response = await _dio.get('/api/v1/products/$productId');
      if (response.statusCode == 200 && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to get product: status ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('[HttpApiService] getProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    _syncBaseUrl();
    try {
      final payload = product.toBackendJson(artisanId: artisanId);
      final effectiveKey = idempotencyKey ??
          'idem_create_${product.id}_${DateTime.now().millisecondsSinceEpoch}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] POST ${_dio.options.baseUrl}/api/v1/products: ${product.title}');
      final response = await _dio.post('/api/v1/products', data: payload, options: options);

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to create product, status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('[HttpApiService] createProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Product> updateProduct(Product product, {int? expectedRevision, String? idempotencyKey}) async {
    _syncBaseUrl();
    try {
      final payload = product.toBackendUpdateJson(expectedRevision: expectedRevision);
      final effectiveKey = idempotencyKey ??
          'idem_update_${product.id}_${product.revision}_${DateTime.now().millisecondsSinceEpoch}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] PUT ${_dio.options.baseUrl}/api/v1/products/${product.id}');
      final response = await _dio.put('/api/v1/products/${product.id}', data: payload, options: options);

      if (response.statusCode == 200 && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to update product, status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final detail = e.response?.data is Map
            ? e.response?.data['detail']?.toString()
            : null;
        throw StaleRevisionException(
          detail ?? 'Revision conflict: draft was modified elsewhere.',
        );
      }
      debugPrint('[HttpApiService] updateProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<bool> deleteProduct(String id, {String? idempotencyKey}) async {
    _syncBaseUrl();
    try {
      final effectiveKey = idempotencyKey ??
          'idem_del_${id}_${DateTime.now().millisecondsSinceEpoch}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] DELETE ${_dio.options.baseUrl}/api/v1/products/$id');
      final response = await _dio.delete('/api/v1/products/$id', options: options);
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('[HttpApiService] deleteProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    _syncBaseUrl();
    try {
      final payload = {
        'revision': revision,
        'content_hash': contentHash,
      };
      final effectiveKey = idempotencyKey ??
          'idem_pub_${productId}_${revision}_${DateTime.now().millisecondsSinceEpoch}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] POST ${_dio.options.baseUrl}/api/v1/products/$productId/approve-and-publish');
      final response = await _dio.post(
        '/api/v1/products/$productId/approve-and-publish',
        data: payload,
        options: options,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to approve and publish: status ${response.statusCode}',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final detail = e.response?.data is Map
            ? e.response?.data['detail']?.toString()
            : null;
        throw StaleRevisionException(
          detail ?? 'Product draft was modified elsewhere. Please review latest content before publishing.',
        );
      }
      debugPrint('[HttpApiService] approveAndPublishProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    _syncBaseUrl();
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('File does not exist: $filePath');
      }
      final fileName = filePath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final effectiveKey = idempotencyKey ??
          'idem_upload_${DateTime.now().millisecondsSinceEpoch}_${filePath.hashCode.abs()}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] POST ${_dio.options.baseUrl}/api/v1/media/upload');
      final response = await _dio.post('/api/v1/media/upload', data: formData, options: options);
      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to upload media asset: status ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('[HttpApiService] uploadMediaFile failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    _syncBaseUrl();
    try {
      final effectiveKey = idempotencyKey ??
          'idem_unpub_${productId}_${DateTime.now().millisecondsSinceEpoch}';
      final options = Options(
        headers: {
          'Idempotency-Key': effectiveKey,
        },
      );
      debugPrint('[HttpApiService] POST ${_dio.options.baseUrl}/api/v1/products/$productId/unpublish');
      final response = await _dio.post(
        '/api/v1/products/$productId/unpublish',
        data: {
          'expected_revision': expectedRevision,
          'content_hash': contentHash,
        },
        options: options,
      );

      if (response.statusCode == 200 && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to unpublish product: status ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('[HttpApiService] unpublishProduct failed: ${e.message}');
      if (e.response?.statusCode == 409) {
        int? serverRev;
        final resData = e.response?.data;
        if (resData is Map && resData['detail'] is Map) {
          serverRev = (resData['detail'] as Map)['server_revision'] as int?;
        }
        throw StaleRevisionException(
          'Server rejected unpublish due to revision/hash conflict (HTTP 409)',
          serverRevision: serverRev,
        );
      }
      rethrow;
    }
  }
}

/// Mock API service simulating backend `/products` endpoints with network latency
class MockApiService implements ApiService {
  final List<Product> _remoteProducts = [];

  bool simulateNetworkFailure = false;

  @override
  Future<List<Product>> getProducts({String? artisanId, String? category}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to fetch products from backend');
    }
    return List.from(_remoteProducts);
  }

  @override
  Future<Product> createProduct(Product product, {String? artisanId, String? idempotencyKey}) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to create product');
    }
    final created = product.copyWith(
      id: product.id.isEmpty ? 'prod_${DateTime.now().millisecondsSinceEpoch}' : product.id,
      status: ProductStatus.draft,
      revision: 1,
    );
    _remoteProducts.removeWhere((p) => p.id == created.id);
    _remoteProducts.insert(0, created);
    return created;
  }

  @override
  Future<Product> updateProduct(Product product, {int? expectedRevision, String? idempotencyKey}) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to update product');
    }
    final index = _remoteProducts.indexWhere((p) => p.id == product.id);
    final currentRevision = index != -1 ? _remoteProducts[index].revision : product.revision;
    if (expectedRevision != null && expectedRevision != currentRevision) {
      throw StaleRevisionException(
        'Revision conflict: expected revision $expectedRevision but server revision is $currentRevision.',
      );
    }
    final updated = product.copyWith(
      revision: currentRevision + 1,
      status: product.status,
      contentHash: 'hash_${product.id}_${currentRevision + 1}',
    );
    if (index != -1) {
      _remoteProducts[index] = updated;
    } else {
      _remoteProducts.insert(0, updated);
    }
    return updated;
  }

  @override
  Future<bool> deleteProduct(String id, {String? idempotencyKey}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to delete product');
    }
    _remoteProducts.removeWhere((p) => p.id == id);
    return true;
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    required int revision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to publish product');
    }
    final index = _remoteProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final existing = _remoteProducts[index];
      final published = existing.copyWith(
        status: ProductStatus.published,
        approvedRevision: revision,
        approvedAt: DateTime.now(),
        publishedAt: DateTime.now(),
        contentHash: contentHash,
      );
      _remoteProducts[index] = published;
      return published;
    }
    throw Exception('Product $productId not found');
  }

  @override
  Future<Map<String, dynamic>> uploadMediaFile(String filePath, {String? idempotencyKey}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Media upload failed');
    }
    return {
      'media_id': 'mock_media_${DateTime.now().millisecondsSinceEpoch}',
      'status': 'ready',
      'filename': filePath.split('/').last,
      'content_type': 'image/jpeg',
      'byte_size': 10240,
      'sha256_checksum': 'mock_hash',
    };
  }

  @override
  Future<Product> getProduct(String productId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to fetch product');
    }
    final index = _remoteProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      return _remoteProducts[index];
    }
    throw Exception('Product $productId not found');
  }

  @override
  Future<Product> unpublishProduct(
    String productId, {
    required int expectedRevision,
    required String contentHash,
    String? idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to unpublish product');
    }
    final index = _remoteProducts.indexWhere((p) => p.id == productId);
    if (index != -1) {
      final existing = _remoteProducts[index];
      if (existing.revision != expectedRevision ||
          (existing.contentHash != null && existing.contentHash != contentHash)) {
        throw StaleRevisionException(
          'Stale revision or hash conflict during unpublish',
          serverRevision: existing.revision,
        );
      }
      final unpublished = existing.copyWith(
        status: ProductStatus.draft,
        revision: existing.revision + 1,
        publishedAt: null,
        approvedAt: null,
        approvedRevision: null,
      );
      _remoteProducts[index] = unpublished;
      return unpublished;
    }
    throw Exception('Product $productId not found');
  }
}
