import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/storage/secure_token_storage.dart';
import 'package:kalasetu/core/storage/private_media_cache.dart';

class UnavailableStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw MissingPluginException('simulated unavailable keystore');

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw MissingPluginException('simulated unavailable keystore');
}

class InMemoryWorkingSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _map[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _map.remove(key);
    } else {
      _map[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _map.remove(key);
  }
}

class ProbeTokens extends SecureTokenStorage {
  String current = 'SYNTHETIC_ACCOUNT_A_TOKEN';
  @override
  Future<String?> getToken() async => current;
}

class ProbeAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes([1, 2, 3], 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kalasetu_probe_');
    Hive.init(temp.path);
    SecureTokenStorage.resetForTesting();
    ApiConfig.setBaseUrl('http://127.0.0.1:8000');
  });

  tearDown(() async {
    await Hive.close();
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  group('Reviewer Reproduction & Durability Invariants', () {
    test('legacy token remains durable when secure storage plugin is unavailable', () async {
      final box = await Hive.openBox('auth_box');
      await box.put('access_token', 'SYNTHETIC_LEGACY_TOKEN');
      final storage = SecureTokenStorage(storage: UnavailableStorage());
      final token = await storage.getToken();
      expect(token, 'SYNTHETIC_LEGACY_TOKEN');
      expect(box.get('access_token'), 'SYNTHETIC_LEGACY_TOKEN');
    });

    test('successful readback from explicit secure storage double migrates and deletes legacy token', () async {
      final box = await Hive.openBox('auth_box');
      await box.put('access_token', 'LEGACY_MIGRATION_TOKEN_123');
      final workingStorage = InMemoryWorkingSecureStorage();
      final storage = SecureTokenStorage(storage: workingStorage);

      final token = await storage.getToken();
      expect(token, 'LEGACY_MIGRATION_TOKEN_123');
      // Exact readback from working secure storage succeeded -> legacy token deleted from Hive
      expect(box.get('access_token'), isNull);
      expect(await workingStorage.read(key: 'jwt_access_token'), 'LEGACY_MIGRATION_TOKEN_123');
    });

    test('concurrent callers only trigger single-flight migration', () async {
      final box = await Hive.openBox('auth_box');
      await box.put('access_token', 'CONCURRENT_TOKEN_789');
      final workingStorage = InMemoryWorkingSecureStorage();
      final storage = SecureTokenStorage(storage: workingStorage);

      final results = await Future.wait([
        storage.getToken(),
        storage.getToken(),
        storage.getToken(),
      ]);

      expect(results, ['CONCURRENT_TOKEN_789', 'CONCURRENT_TOKEN_789', 'CONCURRENT_TOKEN_789']);
      expect(box.get('access_token'), isNull);
    });

    test('logout clears secure token and in-memory state', () async {
      final workingStorage = InMemoryWorkingSecureStorage();
      final storage = SecureTokenStorage(storage: workingStorage);
      await storage.saveToken('ACTIVE_SESSION_TOKEN');
      expect(await storage.getToken(), 'ACTIVE_SESSION_TOKEN');

      await storage.clearToken();
      expect(await storage.getToken(), isNull);
      expect(await workingStorage.read(key: 'jwt_access_token'), isNull);
    });

    test('private cache must not send bearer credentials to an arbitrary origin', () async {
      final adapter = ProbeAdapter();
      final cache = PrivateMediaCache(
        cacheDir: Directory('${temp.path}/cache'),
        tokenStorage: ProbeTokens(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      try {
        await cache.downloadAndCacheMedia(
          mediaId: 'med_probe',
          downloadUrl: 'https://untrusted.invalid/api/v1/media/med_probe',
        );
      } catch (_) {}
      expect(
        adapter.requests.where((r) =>
            r.uri.host == 'untrusted.invalid' && r.headers.containsKey('Authorization')),
        isEmpty,
      );
    });

    test('account switch must not return another accounts cached private media', () async {
      final adapter = ProbeAdapter();
      final tokens = ProbeTokens();
      final cache = PrivateMediaCache(
        cacheDir: Directory('${temp.path}/cache'),
        tokenStorage: tokens,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await cache.downloadAndCacheMedia(mediaId: 'med_probe');
      tokens.current = 'SYNTHETIC_ACCOUNT_B_TOKEN';
      final cached = await cache.getCachedFile('med_probe');
      expect(cached, isNull);
    });

    test('private cache rejects media IDs with path traversal characters', () async {
      final adapter = ProbeAdapter();
      final cache = PrivateMediaCache(
        cacheDir: Directory('${temp.path}/cache'),
        tokenStorage: ProbeTokens(),
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(
        () => cache.downloadAndCacheMedia(mediaId: '../../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => cache.getCachedFile('../sensitive_file'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
