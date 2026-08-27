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
  final List<Product> _remoteProducts = [
    Product(
      id: 'prod_1',
      title: 'Handcrafted Terracotta Chai Kulhad (Set of 6)',
      titleHi: 'हस्तनिर्मित मिट्टी के चाय कुल्हड़ (6 का सेट)',
      description: 'Pure natural clay tea cups made on traditional potter\'s wheel, wood-fired for authentic earthy aroma. 100% biodegradable and chemical-free.',
      descriptionHi: 'पारंपरिक चाक पर शुद्ध प्राकृतिक मिट्टी से बने चाय के कुल्हड़, लकड़ी की भट्टी में पके हुए। पूर्णतः जैविक व रसायन मुक्त।',
      price: 450.0,
      imageUrl: 'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=600&q=80',
      category: 'Pottery',
      tags: ['terracotta', 'eco-friendly', 'pottery', 'kitchenware'],
      status: ProductStatus.live,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Product(
      id: 'prod_2',
      title: 'Hand-woven Chanderi Silk Cotton Dupatta',
      titleHi: 'हाथ से बुना चंदेरी सिल्क कॉटन दुपट्टा',
      description: 'Lightweight handloom dupatta with traditional zari border, crafted by master weavers using natural vegetable dyes.',
      descriptionHi: 'पारंपरिक ज़री बॉर्डर और प्राकृतिक वनस्पति रंगों से तैयार हल्का हथकरघा दुपट्टा।',
      price: 1850.0,
      imageUrl: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=600&q=80',
      category: 'Textiles',
      tags: ['handloom', 'chanderi', 'silk', 'traditional'],
      status: ProductStatus.live,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

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
