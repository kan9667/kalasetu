import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/storage/private_media_cache.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/core/widgets/app_image.dart';

// Minimal 1x1 PNG bytes so Image.file succeeds without codec error
final Uint8List kTransparentPng = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5,
  0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

class MockStreamAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    requests.add(options);
    debugPrint('[MockStreamAdapter] fetch called! count: $fetchCount for ${options.path}');
    return ResponseBody(
      Stream<Uint8List>.value(kTransparentPng),
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempCacheDir;
  late Directory tempHiveDir;

  setUpAll(() async {
    tempHiveDir = await Directory.systemTemp.createTemp('app_image_hive_');
    Hive.init(tempHiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempHiveDir.existsSync()) {
      tempHiveDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    SecureTokenStorage.resetForTesting();
    tempCacheDir = await Directory.systemTemp.createTemp('app_image_cache_test_');
  });

  tearDown(() async {
    if (tempCacheDir.existsSync()) {
      tempCacheDir.deleteSync(recursive: true);
    }
  });

  group('AppImage Private Media Routing & Cache Tests', () {
    testWidgets('routes /api/v1/media/<id> through PrivateMediaCache and renders Image.file', (tester) async {
      final mockAdapter = MockStreamAdapter();
      final dio = Dio()..httpClientAdapter = mockAdapter;

      final cache = PrivateMediaCache(
        cacheDir: tempCacheDir,
        dio: dio,
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppImage(
                imageUrl: 'http://127.0.0.1:8000/api/v1/media/med_test_abc',
                mediaCache: cache,
              ),
            ),
          ),
        );

        int retries = 0;
        while (retries < 50) {
          final f = await cache.getCachedFile('med_test_abc');
          if (f != null && f.existsSync() && f.lengthSync() > 0) break;
          await Future.delayed(const Duration(milliseconds: 20));
          retries++;
        }
      });

      await tester.pump();

      // Verify file was cached and rendered as Image
      expect(find.byType(Image), findsOneWidget);
      expect(mockAdapter.fetchCount, equals(1));
      expect(mockAdapter.requests.first.path, contains('/api/v1/media/med_test_abc'));

      File? cachedFile;
      await tester.runAsync(() async {
        cachedFile = await cache.getCachedFile('med_test_abc');
      });
      expect(cachedFile, isNotNull);
      expect(cachedFile!.existsSync(), isTrue);
      expect(cachedFile!.lengthSync(), equals(kTransparentPng.length));
    });

    testWidgets('routes med_<id> through PrivateMediaCache and reuses cached file on restart', (tester) async {
      final mockAdapter = MockStreamAdapter();
      final dio = Dio()..httpClientAdapter = mockAdapter;

      final cache = PrivateMediaCache(
        cacheDir: tempCacheDir,
        dio: dio,
      );

      // First run: downloads and caches
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppImage(
                imageUrl: 'med_artisan_craft_999',
                mediaCache: cache,
              ),
            ),
          ),
        );

        int retries = 0;
        while (retries < 50) {
          final f = await cache.getCachedFile('med_artisan_craft_999');
          if (f != null && f.existsSync() && f.lengthSync() > 0) break;
          await Future.delayed(const Duration(milliseconds: 20));
          retries++;
        }
      });

      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(mockAdapter.fetchCount, equals(1));

      // Simulate app restart / new cache instance pointing to same directory
      final restartedCache = PrivateMediaCache(
        cacheDir: tempCacheDir,
        dio: dio,
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppImage(
                imageUrl: 'med_artisan_craft_999',
                mediaCache: restartedCache,
              ),
            ),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      // fetchCount should STILL be 1 because file was reused from disk cache without network call
      expect(mockAdapter.fetchCount, equals(1),
          reason: 'Cached asset must be reused across app sessions without redownloading');
    });

    test('staging cleanup purges orphaned files leaving cached files intact', () async {
      final adapter = MockStreamAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final cache = PrivateMediaCache(cacheDir: tempCacheDir, dio: dio);

      // Valid cached file
      final cachedFile = await cache.downloadAndCacheMedia(mediaId: 'med_valid');
      expect(await cachedFile.exists(), isTrue);

      final staging = Directory('${tempCacheDir.path}/staging');
      await staging.create(recursive: true);

      // Orphaned staging file from interrupted session
      final orphanStaging = File('${staging.path}/staging_med_interrupted_123.tmp');
      await orphanStaging.writeAsBytes([1, 2, 3]);

      final cleanedCount = await cache.cleanStagingFiles();
      expect(cleanedCount, equals(1));
      expect(await orphanStaging.exists(), isFalse, reason: 'Orphaned .tmp staging file must be purged');
      expect(await cachedFile.exists(), isTrue, reason: 'Authoritative .cached file must be preserved');
    });
  });
}
