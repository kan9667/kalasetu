import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../models/product.dart';

/// Abstract API service contract
abstract class ApiService {
  Future<List<Product>> getProducts({String? artisanId, String? category});
  Future<Product> createProduct(Product product, {String? artisanId});
  Future<Product> updateProduct(Product product);
  Future<bool> deleteProduct(String id);
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
            );

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
  Future<Product> createProduct(Product product, {String? artisanId}) async {
    _syncBaseUrl();
    try {
      final payload = product.toBackendJson(artisanId: artisanId);
      debugPrint('[HttpApiService] POST ${_dio.options.baseUrl}/api/v1/products: ${product.title}');
      final response = await _dio.post('/api/v1/products', data: payload);

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
  Future<Product> updateProduct(Product product) async {
    _syncBaseUrl();
    try {
      final payload = product.toBackendJson();
      debugPrint('[HttpApiService] PUT ${_dio.options.baseUrl}/api/v1/products/${product.id}');
      final response = await _dio.put('/api/v1/products/${product.id}', data: payload);

      if (response.statusCode == 200 && response.data != null) {
        return Product.fromJson(Map<String, dynamic>.from(response.data as Map));
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Failed to update product, status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint('[HttpApiService] updateProduct failed: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<bool> deleteProduct(String id) async {
    _syncBaseUrl();
    try {
      debugPrint('[HttpApiService] DELETE ${_dio.options.baseUrl}/api/v1/products/$id');
      final response = await _dio.delete('/api/v1/products/$id');
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint('[HttpApiService] deleteProduct failed: ${e.message}');
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
  Future<Product> createProduct(Product product, {String? artisanId}) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to create product');
    }
    final created = product.copyWith(
      id: product.id.isEmpty ? 'prod_${DateTime.now().millisecondsSinceEpoch}' : product.id,
      status: ProductStatus.live,
    );
    _remoteProducts.removeWhere((p) => p.id == created.id);
    _remoteProducts.insert(0, created);
    return created;
  }

  @override
  Future<Product> updateProduct(Product product) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to update product');
    }
    final index = _remoteProducts.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _remoteProducts[index] = product;
    } else {
      _remoteProducts.insert(0, product);
    }
    return product;
  }

  @override
  Future<bool> deleteProduct(String id) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to delete product');
    }
    _remoteProducts.removeWhere((p) => p.id == id);
    return true;
  }
}
