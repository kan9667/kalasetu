import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Single-owner secure token storage using platform keystore / keychain.
///
/// Responsibilities:
/// 1. Stores and retrieves JWT bearer tokens securely via [FlutterSecureStorage].
/// 2. Performs a one-time migration from legacy unencrypted Hive 'auth_box'.
/// 3. Ensures sensitive bearer credentials never remain in unencrypted local files.
/// 4. Provides safe in-memory fallback during test execution or headless environments.
class SecureTokenStorage {
  static const String _tokenKey = 'jwt_access_token';
  static const String _legacyBoxName = 'auth_box';
  static const String _legacyTokenKey = 'access_token';

  final FlutterSecureStorage _storage;
  String? _inMemoryFallback;

  static Future<void>? _migrationFuture;
  static bool _globalMigrated = false;
  static bool _forceMigrationFailureForTesting = false;

  /// Reset testing flags and state.
  static void resetForTesting() {
    _forceMigrationFailureForTesting = false;
    _migrationFuture = null;
    _globalMigrated = false;
  }

  /// Hook to simulate secure storage migration failure in tests.
  static void setForceMigrationFailureForTesting(bool fail) {
    _forceMigrationFailureForTesting = fail;
    if (fail) {
      _globalMigrated = false;
      _migrationFuture = null;
    }
  }

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Performs migration from legacy Hive box to secure storage if needed.
  /// Single-flight across all SecureTokenStorage instances.
  /// Does NOT delete the legacy token until exact secure readback is verified.
  /// If migration fails, _globalMigrated remains false so it can be retried on next access.
  Future<void> _migrateLegacyTokenIfNeeded() async {
    if (_globalMigrated) return;

    if (_forceMigrationFailureForTesting) {
      debugPrint('[SecureTokenStorage] Simulated migration failure for testing.');
      return;
    }

    if (_migrationFuture != null) {
      return _migrationFuture;
    }

    _migrationFuture = _doMigrateLegacyToken();
    try {
      await _migrationFuture;
    } finally {
      if (!_globalMigrated) {
        _migrationFuture = null; // allow retry
      }
    }
  }

  Future<void> _doMigrateLegacyToken() async {
    try {
      if (Hive.isBoxOpen(_legacyBoxName)) {
        final box = Hive.box(_legacyBoxName);
        final legacyToken = box.get(_legacyTokenKey) as String?;
        if (legacyToken != null && legacyToken.isNotEmpty) {
          String? currentSecureToken;
          try {
            currentSecureToken = await _storage.read(key: _tokenKey);
          } catch (_) {}

          if (currentSecureToken == null || currentSecureToken.isEmpty) {
            await _storage.write(key: _tokenKey, value: legacyToken);
          }

          // Strict readback verification directly from secure storage before deleting from legacy box
          final readback = await _storage.read(key: _tokenKey);
          if (readback == legacyToken) {
            await box.delete(_legacyTokenKey);
            _globalMigrated = true;
            debugPrint('[SecureTokenStorage] Migrated legacy auth token to FlutterSecureStorage with verified readback.');
          } else {
            debugPrint('[SecureTokenStorage] Migration readback mismatch. Retaining legacy token for future retry.');
          }
        } else {
          _globalMigrated = true;
        }
      }
      // If box is not open, leave _globalMigrated = false so migration can run when opened
    } catch (e) {
      debugPrint('[SecureTokenStorage] Warning: Legacy token migration check failed: $e');
      // Leave _globalMigrated = false to allow retry
    }
  }

  /// Retrieve the current JWT access token.
  /// If secure migration failed or secure storage is inaccessible, continues
  /// reading the durable legacy token until migration succeeds.
  Future<String?> getToken() async {
    await _migrateLegacyTokenIfNeeded();
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } on MissingPluginException {
      if (_inMemoryFallback != null && _inMemoryFallback!.isNotEmpty) {
        return _inMemoryFallback;
      }
    } catch (e) {
      debugPrint('[SecureTokenStorage] Error reading token from secure storage: $e');
    }

    if (_inMemoryFallback != null && _inMemoryFallback!.isNotEmpty) {
      return _inMemoryFallback;
    }

    // Fallback: Check if legacy box still contains token
    try {
      if (Hive.isBoxOpen(_legacyBoxName)) {
        final box = Hive.box(_legacyBoxName);
        final legacyToken = box.get(_legacyTokenKey) as String?;
        if (legacyToken != null && legacyToken.isNotEmpty) {
          return legacyToken;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Securely persist the JWT access token.
  Future<void> saveToken(String token) async {
    await _migrateLegacyTokenIfNeeded();
    _inMemoryFallback = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } on MissingPluginException {
      debugPrint('[SecureTokenStorage] MissingPluginException: using in-memory token fallback for tests.');
    } catch (e) {
      debugPrint('[SecureTokenStorage] Error saving token: $e');
      rethrow;
    }
  }

  /// Remove the stored access token upon logout.
  Future<void> clearToken() async {
    _inMemoryFallback = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('[SecureTokenStorage] Error clearing token: $e');
    }
    try {
      if (Hive.isBoxOpen(_legacyBoxName)) {
        final box = Hive.box(_legacyBoxName);
        await box.delete(_legacyTokenKey);
      }
    } catch (_) {}
  }

  /// Check if an access token is stored.
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
