import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Wraps `connectivity_plus` with a real reachability check.
///
/// A phone can report "connected" (Wi-Fi/mobile radio is on) while the
/// actual network is dead — extremely common on rural/patchy connections.
/// We treat "online" as "radio on AND our backend actually answers".
class ConnectivityService {
  ConnectivityService({
    required this.healthCheckUrl,
    Dio? dio,
    this.pingTimeout = const Duration(seconds: 5),
  }) : _pingDio = dio ??
            Dio(BaseOptions(
              connectTimeout: pingTimeout,
              receiveTimeout: pingTimeout,
              sendTimeout: pingTimeout,
            ));

  final String? healthCheckUrl;
  final Duration pingTimeout;
  final Dio _pingDio;
  final Connectivity _connectivity = Connectivity();

  /// Emits `true`/`false` whenever the device's radio connectivity
  /// changes. Each event is followed by a real reachability check, so
  /// this stream only fires `true` when the internet is actually usable.
  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.asyncMap((_) => hasRealInternet());

  bool _hasRadio(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);

  /// True only if the radio is on AND a lightweight request to our own
  /// backend actually succeeds. Cheap enough to call before every batch.
  Future<bool> hasRealInternet() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_hasRadio(results)) return false;
    } catch (_) {
      // Some platforms occasionally throw here; fall through and let the
      // ping attempt be the source of truth.
    }

    if (healthCheckUrl == null) return true;

    try {
      final response = await _pingDio.get(healthCheckUrl!);
      final code = response.statusCode ?? 0;
      return code >= 200 && code < 500; // 4xx still proves reachability
    } catch (_) {
      return false;
    }
  }
}
