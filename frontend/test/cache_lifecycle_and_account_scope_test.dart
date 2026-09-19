import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalasetu/core/storage/private_media_cache.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_lifecycle_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PrivateMediaCache Lifecycle, Origin Normalization & Account Scope', () {
    test('Normalized origin handles scheme, host case, and default/custom ports', () {
      expect(
        PrivateMediaCache.normalizeBackendOrigin('https://API.KalaSetu.Org'),
        equals('https://api.kalasetu.org:443'),
      );
      expect(
        PrivateMediaCache.normalizeBackendOrigin('http://api.kalasetu.org'),
        equals('http://api.kalasetu.org:80'),
      );
      expect(
        PrivateMediaCache.normalizeBackendOrigin('http://127.0.0.1:8000/'),
        equals('http://127.0.0.1:8000'),
      );
    });

    test('Token renewal for same account preserves session generation and active cache', () {
      final cache = PrivateMediaCache(cacheDir: tempDir);
      cache.updateSession(accountId: 'user_artisan_42', backendUrl: 'https://api.kalasetu.org');

      final initialGen = cache.sessionGeneration;
      expect(cache.activeAccountId, equals('user_artisan_42'));

      // Token renewal: same account, same backend
      cache.updateSession(accountId: 'user_artisan_42', backendUrl: 'https://api.kalasetu.org');

      expect(cache.sessionGeneration, equals(initialGen), reason: 'Token renewal must not increment session generation');
      expect(cache.activeAccountId, equals('user_artisan_42'));

      // Switching accounts must increment session generation and deactivate
      cache.updateSession(accountId: 'user_artisan_99', backendUrl: 'https://api.kalasetu.org');
      expect(cache.sessionGeneration, isNot(equals(initialGen)));
      expect(cache.activeAccountId, equals('user_artisan_99'));
    });

    test('Overlapping concurrent downloads for same mediaId are deduplicated', () async {
      int networkRequestCount = 0;
      final dio = Dio();
      dio.httpClientAdapter = _MockDelayedHttpAdapter((options) async {
        networkRequestCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return ResponseBody.fromBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
          200,
          headers: {
            Headers.contentLengthHeader: ['6'],
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });

      final storage = SecureTokenStorage();
      await storage.saveToken('mock_bearer_jwt');

      final cache = PrivateMediaCache(
        cacheDir: tempDir,
        dio: dio,
        tokenStorage: storage,
      );
      cache.updateSession(accountId: 'artisan_dedup_01', backendUrl: 'https://api.kalasetu.org');

      const mediaId = 'med_concurrent_asset_001';
      const downloadUrl = 'https://api.kalasetu.org/api/v1/media/$mediaId';

      // Dispatch two concurrent downloads for identical asset
      final f1 = cache.downloadAndCacheMedia(mediaId: mediaId, downloadUrl: downloadUrl);
      final f2 = cache.downloadAndCacheMedia(mediaId: mediaId, downloadUrl: downloadUrl);

      final results = await Future.wait([f1, f2]);

      expect(results[0].path, equals(results[1].path));
      expect(results[0].existsSync(), isTrue);
      expect(networkRequestCount, equals(1), reason: 'Concurrent requests for same mediaId must be deduplicated into a single network call');
    });

    test('Account switch during download cancels request and rejects staging promotion', () async {
      final downloadCompleter = Completer<void>();
      final dio = Dio();
      dio.httpClientAdapter = _MockDelayedHttpAdapter((options) async {
        await downloadCompleter.future;
        return ResponseBody.fromBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
          200,
          headers: {
            Headers.contentLengthHeader: ['4'],
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });

      final storage = SecureTokenStorage();
      await storage.saveToken('mock_bearer_jwt');

      final cache = PrivateMediaCache(
        cacheDir: tempDir,
        dio: dio,
        tokenStorage: storage,
      );
      cache.updateSession(accountId: 'artisan_switch_01', backendUrl: 'https://api.kalasetu.org');

      const mediaId = 'med_switch_test_asset';
      const downloadUrl = 'https://api.kalasetu.org/api/v1/media/$mediaId';

      // Start download under account 1
      final downloadFuture = cache.downloadAndCacheMedia(
        mediaId: mediaId,
        downloadUrl: downloadUrl,
      );

      // Switch to account 2 before download completes
      cache.updateSession(accountId: 'artisan_switch_02', backendUrl: 'https://api.kalasetu.org');

      downloadCompleter.complete();

      // Download must fail with SessionChangedException or DioException (cancelled)
      expect(
        downloadFuture,
        throwsA(anyOf(isA<SessionChangedException>(), isA<DioException>())),
      );

      // Ensure no unverified asset was promoted to cache under account 2
      expect(await cache.isCached(mediaId), isFalse);
    });
  });
}

class _MockDelayedHttpAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  _MockDelayedHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (cancelFuture != null) {
      final cancelCompleter = Completer<ResponseBody>();
      cancelFuture.then((_) {
        if (!cancelCompleter.isCompleted) {
          cancelCompleter.completeError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Request was cancelled',
            ),
          );
        }
      });
      handler(options).then((res) {
        if (!cancelCompleter.isCompleted) cancelCompleter.complete(res);
      }).catchError((e) {
        if (!cancelCompleter.isCompleted) cancelCompleter.completeError(e);
      });
      return cancelCompleter.future;
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
