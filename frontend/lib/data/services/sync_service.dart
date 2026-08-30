import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../repositories/product_repository.dart';

enum SyncState { idle, syncing, completed, error }

class SyncService {
  final ProductRepository productRepository;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  final ValueNotifier<SyncState> syncState = ValueNotifier(SyncState.idle);
  final ValueNotifier<bool> isOnline = ValueNotifier(true);
  bool _isSyncing = false;

  SyncService({
    required this.productRepository,
    Connectivity? connectivity,
  })  : _connectivity = connectivity ?? Connectivity() {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivity.checkConnectivity().then((results) async {
      _updateConnectionStatus(results);
      if (isOnline.value) {
        await triggerSync();
      }
    });
    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final previousOnline = isOnline.value;
    isOnline.value = online;

    // If connection was restored, drain the pending queue automatically
    if (online && !previousOnline) {
      triggerSync();
    }
  }

  Future<int> triggerSync() async {
    if (!isOnline.value || _isSyncing) return 0;

    _isSyncing = true;
    syncState.value = SyncState.syncing;
    try {
      final count = await productRepository.syncPendingQueue();
      syncState.value = SyncState.completed;
      Future.delayed(const Duration(seconds: 3), () {
        syncState.value = SyncState.idle;
      });
      return count;
    } catch (e) {
      debugPrint('SyncService error during drain: $e');
      syncState.value = SyncState.error;
      return 0;
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    syncState.dispose();
    isOnline.dispose();
  }
}
