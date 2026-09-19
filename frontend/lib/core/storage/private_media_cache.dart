import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import 'secure_token_storage.dart';

class MediaExceedsSizeLimitException implements Exception {
  final int bytesRead;
  final int maxBytes;
  MediaExceedsSizeLimitException(this.bytesRead, this.maxBytes);

  @override
  String toString() =>
      'MediaExceedsSizeLimitException: Download exceeded max limit of $maxBytes bytes (received $bytesRead bytes)';
}

class SessionChangedException implements Exception {
  final String message;
  SessionChangedException(this.message);

  @override
  String toString() => 'SessionChangedException: $message';
}

/// Durable, authenticated private-media cache.
///
/// Enforces:
/// 1. Bounded download size (default: 15 MB).
/// 2. Downloads into temporary staging file before atomic rename.
/// 3. Never treats partial or interrupted downloads as valid cached assets.
/// 4. Sanitizes logging: never logs authorization headers or bearer tokens.
/// 5. Automatically purges abandoned staging files on failure and startup.
/// 6. Path traversal protection on mediaId.
/// 7. Scoped caching and in-flight download tracking by account and backend.
/// 8. Strict origin and redirect validation for bearer credentials.
/// 9. Deduplication of overlapping in-flight downloads for the same media asset.
/// 10. Verification of authenticated session identity before promoting downloads.
class PrivateMediaCache {
  static const int defaultMaxBytes = 15 * 1024 * 1024; // 15 MB
  static final RegExp _mediaIdPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');

  static PrivateMediaCache? _instance;
  static PrivateMediaCache get instance => _instance ??= PrivateMediaCache();
  @visibleForTesting
  static set instance(PrivateMediaCache? val) => _instance = val;

  final Directory? _customCacheDir;
  final SecureTokenStorage _tokenStorage;
  final Dio? _customDio;
  final Map<String, CancelToken> _inFlightDownloads = {};
  final Map<String, Future<File>> _inFlightFutures = {};

  String? _activeAccountId;
  String? _activeBackendOrigin;
  int _sessionGeneration = 0;

  int get sessionGeneration => _sessionGeneration;
  String? get activeAccountId => _activeAccountId;

  PrivateMediaCache({
    Directory? cacheDir,
    SecureTokenStorage? tokenStorage,
    Dio? dio,
  })  : _customCacheDir = cacheDir,
        _tokenStorage = tokenStorage ?? SecureTokenStorage(),
        _customDio = dio;

  /// Validate mediaId to eliminate path traversal vulnerabilities.
  static void validateMediaId(String mediaId) {
    if (mediaId.isEmpty || !_mediaIdPattern.hasMatch(mediaId)) {
      throw ArgumentError(
        'Invalid mediaId: "$mediaId". Media IDs must contain only alphanumeric characters, underscores, and hyphens.',
      );
    }
  }

  /// Normalizes backend origin by scheme, lowercase host, and explicit port.
  static String normalizeBackendOrigin(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      final int defaultPort = scheme == 'https' ? 443 : 80;
      final int port = uri.hasPort ? uri.port : defaultPort;
      return '$scheme://$host:$port';
    } catch (_) {
      return url.trim().toLowerCase();
    }
  }

  /// Verifies if a target URI strictly matches the configured API origin (scheme, host, and port).
  static bool isConfiguredApiOrigin(Uri uri) {
    try {
      final baseUri = Uri.parse(ApiConfig.baseUrl);
      final targetPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final basePort = baseUri.hasPort ? baseUri.port : (baseUri.scheme == 'https' ? 443 : 80);
      return uri.scheme.toLowerCase() == baseUri.scheme.toLowerCase() &&
          uri.host.toLowerCase() == baseUri.host.toLowerCase() &&
          targetPort == basePort;
    } catch (_) {
      return false;
    }
  }

  /// Updates authenticated session identity and backend origin.
  /// Cancels in-flight requests and increments session generation on account/origin change.
  /// Preserves cached state and in-flight operations if token renewal occurs for the same account.
  void updateSession({required String? accountId, String? backendUrl}) {
    final effectiveBackend = backendUrl ?? ApiConfig.baseUrl;
    final newOrigin = normalizeBackendOrigin(effectiveBackend);
    final bool accountChanged = accountId != _activeAccountId;
    final bool originChanged = _activeBackendOrigin != null && _activeBackendOrigin != newOrigin;

    if (accountChanged || originChanged) {
      deactivateAccount();
      _activeAccountId = accountId;
      _activeBackendOrigin = newOrigin;
    } else {
      _activeAccountId = accountId;
      _activeBackendOrigin = newOrigin;
    }
  }

  String _getAccountScope([String? accountId]) {
    final id = accountId ?? _activeAccountId;
    if (id == null || id.isEmpty) return 'unauthenticated';
    final bytes = utf8.encode(id);
    final digest = sha256.convert(bytes);
    return 'acc_${digest.toString().substring(0, 16)}';
  }

  String _getBackendScope([String? origin]) {
    final rawOrigin = origin ?? _activeBackendOrigin ?? ApiConfig.baseUrl;
    final normalized = normalizeBackendOrigin(rawOrigin);
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    return 'srv_${digest.toString().substring(0, 8)}';
  }

  Future<Directory> get _baseDir async {
    if (_customCacheDir != null) {
      if (!await _customCacheDir.exists()) {
        await _customCacheDir.create(recursive: true);
      }
      return _customCacheDir;
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/private_media_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getScopedCacheDir([String? accountId, String? origin]) async {
    final base = await _baseDir;
    final backendScope = _getBackendScope(origin);
    final accountScope = _getAccountScope(accountId);
    final scoped = Directory('${base.path}/$backendScope/$accountScope');
    if (!await scoped.exists()) {
      await scoped.create(recursive: true);
    }
    return scoped;
  }

  Future<Directory> get _stagingDir async {
    final base = await _baseDir;
    final staging = Directory('${base.path}/staging');
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }
    return staging;
  }

  /// Cleans up any orphaned staging files left by interrupted downloads or prior app runs.
  Future<int> cleanStagingFiles() async {
    int deletedCount = 0;
    try {
      final staging = await _stagingDir;
      if (await staging.exists()) {
        final entities = staging.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            try {
              entity.deleteSync();
              deletedCount++;
            } catch (e) {
              debugPrint('[PrivateMediaCache] Failed to delete staging file: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PrivateMediaCache] Error cleaning staging files: $e');
    }
    return deletedCount;
  }

  /// Cancels in-flight requests and deactivates cached context for an account upon logout or switch.
  void deactivateAccount([String? specificAccountScope]) {
    _sessionGeneration++;
    if (specificAccountScope != null) {
      final toRemove = <String>[];
      for (final entry in _inFlightDownloads.entries) {
        if (entry.key.startsWith(specificAccountScope)) {
          entry.value.cancel('Account deactivated or switched');
          toRemove.add(entry.key);
        }
      }
      for (final key in toRemove) {
        _inFlightDownloads.remove(key);
        _inFlightFutures.remove(key);
      }
    } else {
      for (final cancelToken in _inFlightDownloads.values) {
        cancelToken.cancel('Account deactivated or switched');
      }
      _inFlightDownloads.clear();
      _inFlightFutures.clear();
      _activeAccountId = null;
    }
    debugPrint('[PrivateMediaCache] In-flight media requests deactivated (gen: $_sessionGeneration).');
  }

  Future<String?> _resolveEffectiveAccountId() async {
    if (_activeAccountId != null && _activeAccountId!.isNotEmpty) {
      return _activeAccountId;
    }
    final token = await _tokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }
    return null;
  }

  /// Get the cached file if it already exists in the current account's scope and is non-empty.
  Future<File?> getCachedFile(String mediaId) async {
    validateMediaId(mediaId);
    final accountId = await _resolveEffectiveAccountId();
    final scopedDir = await _getScopedCacheDir(accountId);
    final cached = File('${scopedDir.path}/media_$mediaId.cached');
    if (await cached.exists() && (await cached.length()) > 0) {
      return cached;
    }
    return null;
  }

  /// Returns true if the given media asset exists and is cached for the active account.
  Future<bool> isCached(String mediaId) async {
    return (await getCachedFile(mediaId)) != null;
  }

  /// Download and cache private media asset securely.
  /// Deduplicates overlapping requests for the same media ID within the active account scope.
  Future<File> downloadAndCacheMedia({
    required String mediaId,
    String? downloadUrl,
    int maxBytes = defaultMaxBytes,
  }) async {
    validateMediaId(mediaId);

    final startSessionGen = _sessionGeneration;
    final startAccountId = _activeAccountId;
    final startBackendOrigin = _getBackendScope();

    final accountId = _activeAccountId ?? await _resolveEffectiveAccountId();
    final accountScope = _getAccountScope(accountId);
    final inFlightKey = '${accountScope}_$mediaId';

    // Deduplicate overlapping downloads synchronously before any async gap
    final existingFuture = _inFlightFutures[inFlightKey];
    if (existingFuture != null) {
      debugPrint('[PrivateMediaCache] Reusing in-flight download future for $inFlightKey');
      return await existingFuture;
    }

    final completer = Completer<File>();
    // Ignore unhandled error on the completer future itself if the operation errors
    // without concurrent listeners.
    completer.future.ignore();
    _inFlightFutures[inFlightKey] = completer.future;

    try {
      final existing = await getCachedFile(mediaId);
      if (existing != null) {
        completer.complete(existing);
        return existing;
      }

      if (_sessionGeneration != startSessionGen ||
          _activeAccountId != startAccountId ||
          _getBackendScope() != startBackendOrigin) {
        throw SessionChangedException(
          'Session or backend origin changed during download of media $mediaId; promotion aborted.',
        );
      }

      final file = await _executeDownload(
        mediaId: mediaId,
        downloadUrl: downloadUrl,
        maxBytes: maxBytes,
        accountId: accountId,
        accountScope: accountScope,
        inFlightKey: inFlightKey,
        startSessionGen: startSessionGen,
        startAccountId: startAccountId,
        startBackendOrigin: startBackendOrigin,
      );
      completer.complete(file);
      return file;
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
      rethrow;
    } finally {
      _inFlightFutures.remove(inFlightKey);
    }
  }

  Future<File> _executeDownload({
    required String mediaId,
    String? downloadUrl,
    required int maxBytes,
    required String? accountId,
    required String accountScope,
    required String inFlightKey,
    required int startSessionGen,
    required String? startAccountId,
    required String startBackendOrigin,
  }) async {

    final token = await _tokenStorage.getToken();
    final scopedDir = await _getScopedCacheDir(accountId);
    final staging = await _stagingDir;
    final stagedPath =
        '${staging.path}/staging_${mediaId}_${DateTime.now().microsecondsSinceEpoch}.tmp';
    final stagedFile = File(stagedPath);
    final finalFile = File('${scopedDir.path}/media_$mediaId.cached');

    final targetUrl = downloadUrl ?? '${ApiConfig.baseUrl}/api/v1/media/$mediaId';
    final targetUri = Uri.parse(targetUrl);
    final isTargetConfigured = isConfiguredApiOrigin(targetUri);
    final isPrivateMediaPath = targetUri.path.contains('/api/v1/media/') || targetUri.path.contains('/media/');

    // Security invariant: NEVER attach bearer credentials to arbitrary external origins!
    final headers = <String, dynamic>{
      'Accept': '*/*',
      if (isTargetConfigured && isPrivateMediaPath && token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token',
    };

    final cancelToken = CancelToken();
    _inFlightDownloads[inFlightKey] = cancelToken;

    IOSink? sink;
    try {
      sink = stagedFile.openWrite();
      int totalBytesRead = 0;

      final dio = _customDio ?? Dio();
      debugPrint('[PrivateMediaCache] Initiating bounded download for media $mediaId from $targetUrl (max: $maxBytes bytes)');

      // Fetch stream with manual redirect handling to prevent credential leaks on cross-origin redirects
      var currentUrl = targetUrl;
      var currentHeaders = Map<String, dynamic>.from(headers);
      ResponseBody? responseBody;

      for (int redirectCount = 0; redirectCount < 5; redirectCount++) {
        final currentUri = Uri.parse(currentUrl);
        final currentIsConfigured = isConfiguredApiOrigin(currentUri);
        if (!currentIsConfigured) {
          currentHeaders.remove('Authorization');
        }

        final response = await dio.get<ResponseBody>(
          currentUrl,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: currentHeaders,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        final statusCode = response.statusCode ?? 200;
        if (statusCode >= 300 && statusCode < 400) {
          final location = response.headers.value('location');
          if (location == null || location.isEmpty) {
            throw Exception('Redirect response missing location header for media $mediaId');
          }
          currentUrl = currentUri.resolve(location).toString();
          continue;
        }

        responseBody = response.data;
        break;
      }

      final stream = responseBody?.stream;
      if (stream == null) {
        throw Exception('No response stream received for media $mediaId');
      }

      final activeSink = sink;
      await for (final chunk in stream) {
        totalBytesRead += chunk.length;
        if (totalBytesRead > maxBytes) {
          debugPrint('[PrivateMediaCache] Media $mediaId exceeded max byte limit ($totalBytesRead > $maxBytes). Aborting.');
          await activeSink.flush();
          await activeSink.close();
          sink = null;
          if (await stagedFile.exists()) {
            await stagedFile.delete();
          }
          throw MediaExceedsSizeLimitException(totalBytesRead, maxBytes);
        }
        activeSink.add(chunk);
      }

      await activeSink.flush();
      await activeSink.close();
      sink = null;

      // Verify file was written and is not empty
      if (!await stagedFile.exists() || await stagedFile.length() == 0) {
        if (await stagedFile.exists()) await stagedFile.delete();
        throw Exception('Download finished with empty file for media $mediaId');
      }

      // Recheck session identity before promoting the download
      if (_sessionGeneration != startSessionGen ||
          _activeAccountId != startAccountId ||
          _getBackendScope() != startBackendOrigin) {
        if (await stagedFile.exists()) {
          await stagedFile.delete();
        }
        throw SessionChangedException(
          'Session or backend origin changed during download of media $mediaId; promotion aborted.',
        );
      }

      // Atomic rename to final cache destination
      await stagedFile.rename(finalFile.path);
      debugPrint('[PrivateMediaCache] Successfully downloaded and cached media $mediaId ($totalBytesRead bytes)');
      return finalFile;
    } catch (e) {
      debugPrint('[PrivateMediaCache] Failed to download media $mediaId: $e');
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
      if (await stagedFile.exists()) {
        try {
          await stagedFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _inFlightDownloads.remove(inFlightKey);
    }
  }
}
