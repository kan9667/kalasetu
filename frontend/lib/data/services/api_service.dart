import 'dart:async';
import '../models/product.dart';

/// Abstract API service contract
abstract class ApiService {
  Future<List<Product>> getProducts();
  Future<Product> createProduct(Product product);
  Future<Product> updateProduct(Product product);
  Future<bool> deleteProduct(String id);
}

/// Mock API service simulating backend `/products` endpoints with network latency
class MockApiService implements ApiService {
  final List<Product> _remoteProducts = [];

  bool simulateNetworkFailure = false;

  @override
  Future<List<Product>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (simulateNetworkFailure) {
      throw Exception('Simulated network error: Unable to fetch products from backend');
    }
    return List.from(_remoteProducts);
  }

  @override
  Future<Product> createProduct(Product product) async {
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
