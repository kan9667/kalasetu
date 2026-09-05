import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Centralized API configuration that dynamically resolves the working backend URL.
/// Works seamlessly across physical Android phones on Wi-Fi (e.g., SM-M346B),
/// Android Emulators (10.0.2.2), adb reverse tunnels, and desktop.
class ApiConfig {
  static String? _cachedBaseUrl;

  /// Default fallback Wi-Fi IP of the host machine
  static const String hostLanIp = '192.168.1.5';

  static String get baseUrl {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;
    return _resolveInitialBaseUrl();
  }

  static void setBaseUrl(String url) {
    _cachedBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    debugPrint('[ApiConfig] Base URL manually set to: $_cachedBaseUrl');
  }

  static String _resolveInitialBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) return configuredBaseUrl;

    if (Platform.isAndroid) {
      // Default to LAN IP for physical device connectivity;
      // discoverWorkingUrl() will verify and update during app init.
      return 'http://$hostLanIp:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Quickly tests candidate URLs against `/api/v1/health` and locks onto the first responsive backend.
  static Future<String> discoverWorkingUrl() async {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      _cachedBaseUrl = configuredBaseUrl.endsWith('/')
          ? configuredBaseUrl.substring(0, configuredBaseUrl.length - 1)
          : configuredBaseUrl;
      return _cachedBaseUrl!;
    }

    final candidates = <String>[
      'http://$hostLanIp:8000',
      if (Platform.isAndroid) 'http://10.0.2.2:8000',
      'http://127.0.0.1:8000',
      'http://localhost:8000',
    ];

    for (final candidate in candidates) {
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(milliseconds: 1500),
            receiveTimeout: const Duration(milliseconds: 1500),
          ),
        );
        final response = await dio.get('$candidate/api/v1/health');
        if (response.statusCode == 200) {
          debugPrint('[ApiConfig] Discovered active backend at: $candidate');
          _cachedBaseUrl = candidate;
          return candidate;
        }
      } catch (_) {
        // Continue to next candidate
      }
    }

    _cachedBaseUrl = _resolveInitialBaseUrl();
    debugPrint('[ApiConfig] Using default base URL: $_cachedBaseUrl');
    return _cachedBaseUrl!;
  }
}
