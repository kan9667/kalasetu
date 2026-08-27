import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ProductRepository {
  final ApiService _apiService;
  static const String _productsBoxName = 'products_box';
  static const String _pendingBoxName = 'pending_sync_box';

  ProductRepository({ApiService? apiService})
      : _apiService = apiService ?? MockApiService();

  Box<Product> _getProductsBox() {
    return Hive.box<Product>(_productsBoxName);
  }

  Box<String> _getPendingBox() {
    return Hive.box<String>(_pendingBoxName);
  }

  /// Get all products - Hive is the instant source of truth
  Future<List<Product>> getProducts({bool forceRefresh = false, bool isOnline = true}) async {
    final box = _getProductsBox();

    // If box is empty and online, populate with remote products
    if ((box.isEmpty || forceRefresh) && isOnline) {
      try {
        final remote = await _apiService.getProducts();
        for (var p in remote) {
          await box.put(p.id, p);
        }
      } catch (e) {
        debugPrint('ProductRepository: Remote fetch failed, using local cache: $e');
      }
    }

    // Return all local products sorted by creation time (newest first)
    final list = box.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Product? getProductById(String id) {
    return _getProductsBox().get(id);
  }

  /// Add product - Writes to Hive first, queues for sync if offline or sync fails
  Future<Product> addProduct(Product product, {bool isOnline = true}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    final id = product.id.isEmpty
        ? 'prod_${DateTime.now().millisecondsSinceEpoch}'
        : product.id;

    if (isOnline) {
      try {
        final onlineProduct = product.copyWith(id: id, status: ProductStatus.live);
        final created = await _apiService.createProduct(onlineProduct);
        await productsBox.put(created.id, created);
        await pendingBox.delete(created.id);
        return created;
      } catch (e) {
        debugPrint('ProductRepository: Online create failed, saving to pending queue: $e');
      }
    }

    // Offline mode or API failed: save locally with pendingSync status
    final localProduct = product.copyWith(
      id: id,
      status: ProductStatus.pendingSync,
    );
    await productsBox.put(localProduct.id, localProduct);
    await pendingBox.put(localProduct.id, 'CREATE');
    return localProduct;
  }

  /// Update product
  Future<Product> updateProduct(Product product, {bool isOnline = true}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    if (isOnline) {
      try {
        final updated = await _apiService.updateProduct(product);
        await productsBox.put(updated.id, updated.copyWith(status: ProductStatus.live));
        await pendingBox.delete(product.id);
        return updated;
      } catch (e) {
        debugPrint('ProductRepository: Online update failed, saving to pending queue: $e');
      }
    }

    final localProduct = product.copyWith(status: ProductStatus.pendingSync);
    await productsBox.put(localProduct.id, localProduct);
    await pendingBox.put(localProduct.id, 'UPDATE');
    return localProduct;
  }

  /// Delete product
  Future<void> deleteProduct(String id, {bool isOnline = true}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    await productsBox.delete(id);

    if (isOnline) {
      try {
        await _apiService.deleteProduct(id);
        await pendingBox.delete(id);
        return;
      } catch (e) {
        debugPrint('ProductRepository: Online delete failed: $e');
      }
    }

    await pendingBox.put(id, 'DELETE');
  }

  /// Drain pending offline queue and flip pendingSync -> live
  Future<int> syncPendingQueue() async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();
    final pendingIds = pendingBox.keys.cast<String>().toList();

    if (pendingIds.isEmpty) return 0;

    int syncedCount = 0;
    for (final id in pendingIds) {
      final action = pendingBox.get(id);
      try {
        if (action == 'DELETE') {
          await _apiService.deleteProduct(id);
          await pendingBox.delete(id);
          syncedCount++;
        } else {
          final product = productsBox.get(id);
          if (product != null) {
            if (action == 'CREATE') {
              final created = await _apiService.createProduct(product);
              await productsBox.put(id, created.copyWith(status: ProductStatus.live));
            } else {
              final updated = await _apiService.updateProduct(product);
              await productsBox.put(id, updated.copyWith(status: ProductStatus.live));
            }
            await pendingBox.delete(id);
            syncedCount++;
          }
        }
      } catch (e) {
        debugPrint('ProductRepository: Failed to sync pending item $id: $e');
      }
    }

    return syncedCount;
  }

  int getPendingCount() {
    return _getPendingBox().length;
  }

  List<String> getPendingIds() {
    return _getPendingBox().keys.cast<String>().toList();
  }
}
