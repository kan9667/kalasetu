import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/product.dart';
import '../../data/models/user_profile.dart';
import 'hive_migration_runner.dart';

/// Represents a failure where safety-critical box data cannot be safely opened.
class HiveCorruptionException implements Exception {
  final String boxName;
  final String error;
  final String? quarantinedPath;

  HiveCorruptionException(this.boxName, this.error, this.quarantinedPath);

  @override
  String toString() =>
      'HiveCorruptionException: Critical box "$boxName" failed to open: $error (Quarantined at: $quarantinedPath)';
}

/// Status report for Hive initialization and data integrity.
class HiveRecoveryReport {
  final bool isHealthy;
  final String? failedBox;
  final String? error;
  final String? quarantinedPath;

  const HiveRecoveryReport({
    required this.isHealthy,
    this.failedBox,
    this.error,
    this.quarantinedPath,
  });

  factory HiveRecoveryReport.healthy() => const HiveRecoveryReport(isHealthy: true);

  factory HiveRecoveryReport.corrupted({
    required String boxName,
    required String error,
    String? quarantinedPath,
  }) {
    return HiveRecoveryReport(
      isHealthy: false,
      failedBox: boxName,
      error: error,
      quarantinedPath: quarantinedPath,
    );
  }
}

/// Centralized manager for Hive local storage with non-destructive, fail-closed safety.
///
/// Invariants:
/// 1. NEVER calls [Hive.deleteBoxFromDisk] on safety-critical boxes.
/// 2. Never silently replaces corrupted boxes with empty boxes.
/// 3. Quarantines original bytes with timestamped filenames if decoding fails.
/// 4. Halts sync and startup into a fail-closed recovery state when critical boxes fail.
class HiveBoxManager {
  static const Set<String> criticalBoxes = {
    'products_box',
    'pending_sync_box',
    'draft_box',
    'user_profile_box',
    'auth_box',
    'ai_operations_box',
  };

  static const String boxProducts = 'products_box';
  static const String boxPendingSync = 'pending_sync_box';
  static const String boxDrafts = 'draft_box';
  static const String boxUserProfile = 'user_profile_box';
  static const String boxAuth = 'auth_box';
  static const String boxAiOperations = 'ai_operations_box';
  static const String boxAppSettings = 'app_settings_box';

  static String? _activeDir;
  static HiveRecoveryReport _report = HiveRecoveryReport.healthy();
  static HiveRecoveryReport get report => _report;
  static bool get isHealthy => _report.isHealthy;

  /// Register Hive type adapters safely.
  static void registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
  }

  /// Initialize Hive and open all boxes with fail-closed safety.
  static Future<HiveRecoveryReport> init({String? subDir}) async {
    try {
      _activeDir = subDir;
      if (subDir != null) {
        Hive.init(subDir);
      } else {
        await Hive.initFlutter();
      }

      registerAdapters();

      // Open critical boxes sequentially with crashRecovery: false to prevent silent data truncation
      await _openCriticalBox<Product>(boxProducts);
      await _openCriticalBox<String>(boxPendingSync);
      await _openCriticalBox<UserProfile>(boxUserProfile);
      await _openCriticalBox(boxAuth);
      await _openCriticalBox(boxDrafts);
      await _openCriticalBox<String>(boxAiOperations);

      // Open non-critical box
      await _openNonCriticalBox(boxAppSettings);

      // Run versioned Hive data migrations safely
      await HiveMigrationRunner.runMigrations();

      _report = HiveRecoveryReport.healthy();
      return _report;
    } on HiveCorruptionException catch (e) {
      _report = HiveRecoveryReport.corrupted(
        boxName: e.boxName,
        error: e.error,
        quarantinedPath: e.quarantinedPath,
      );
      return _report;
    } catch (e) {
      _report = HiveRecoveryReport.corrupted(
        boxName: 'unknown_initialization',
        error: e.toString(),
      );
      return _report;
    }
  }

  /// Opens a safety-critical box. If opening fails, quarantines original data and fails closed.
  static Future<Box<T>> _openCriticalBox<T>(String boxName) async {
    final completer = Completer<Box<T>>();
    runZonedGuarded(() async {
      try {
        final box = await Hive.openBox<T>(boxName, crashRecovery: false);
        if (!completer.isCompleted) completer.complete(box);
      } catch (e) {
        debugPrint('[HiveBoxManager] CRITICAL: Failed to open safety-critical box "$boxName": $e');

        // Quarantine original bytes before failing closed
        final quarantinedPath = await _quarantineBoxFiles(boxName);

        // Invariant: NEVER delete and NEVER open empty replacement.
        if (!completer.isCompleted) {
          completer.completeError(HiveCorruptionException(boxName, e.toString(), quarantinedPath));
        }
      }
    }, (error, stack) {
      // Swallows Hive's dangling unawaited internal completer error
      debugPrint('[HiveBoxManager] Handled internal Hive async error: $error');
    });

    return completer.future;
  }

  /// Opens a non-critical box. Quarantines prior to reset if opening fails.
  static Future<Box<T>> _openNonCriticalBox<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      debugPrint('[HiveBoxManager] Non-critical box "$boxName" failed to open: $e');
      await _quarantineBoxFiles(boxName);
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } catch (err) {
        debugPrint('[HiveBoxManager] Warning deleting non-critical box $boxName: $err');
      }
      return await Hive.openBox<T>(boxName);
    }
  }

  /// Locates box files on disk and copies them to a quarantine directory.
  static Future<String?> _quarantineBoxFiles(String boxName) async {
    try {
      Directory dir;
      if (_activeDir != null) {
        dir = Directory(_activeDir!);
      } else {
        try {
          dir = await getApplicationDocumentsDirectory();
        } catch (_) {
          dir = Directory.current;
        }
      }

      final boxFile = File('${dir.path}/$boxName.hive');
      if (await boxFile.exists()) {
        final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
        final quarantineDir = Directory('${dir.path}/quarantine');
        if (!await quarantineDir.exists()) {
          await quarantineDir.create(recursive: true);
        }
        final targetPath = '${quarantineDir.path}/$boxName.hive.quarantine_$timestamp';
        await boxFile.copy(targetPath);

        // Apply and verify restrictive owner-only permissions (0600) on POSIX systems
        if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
          bool verifiedOwnerOnly = false;
          try {
            final result = await Process.run('chmod', ['0600', targetPath]);
            if (result.exitCode == 0) {
              final stat = await FileStat.stat(targetPath);
              verifiedOwnerOnly = (stat.mode & 0x3F) == 0; // 0077 octal
              if (verifiedOwnerOnly) {
                debugPrint('[HiveBoxManager] Quarantined file permissions verified owner-only (0600, mode: ${stat.modeString()})');
              } else {
                debugPrint('[HiveBoxManager] Warning: chmod 0600 exited 0 but stat mode is ${stat.modeString()} (mode & 077 != 0)');
              }
            } else {
              debugPrint('[HiveBoxManager] Warning: chmod 0600 failed with exit code ${result.exitCode}: ${result.stderr}');
            }
          } catch (chmodErr) {
            debugPrint('[HiveBoxManager] Warning: Unable to enforce POSIX 0600 permissions on quarantine file: $chmodErr');
          }

          if (!verifiedOwnerOnly) {
            debugPrint('[HiveBoxManager] Security violation: Owner-only permissions (0600) could not be verified on $targetPath. Deleting quarantine file to remain fail-closed.');
            try {
              final qFile = File(targetPath);
              if (await qFile.exists()) {
                await qFile.delete();
              }
            } catch (_) {}
            return null;
          }
        } else {
          debugPrint('[HiveBoxManager] Notice: Platform ${Platform.operatingSystem} is non-POSIX; 0600 owner-only permissions cannot be guaranteed via chmod.');
        }

        debugPrint('[HiveBoxManager] Quarantined corrupted box "$boxName" to $targetPath');
        return targetPath;
      }
    } catch (err) {
      debugPrint('[HiveBoxManager] Failed to create quarantine file for $boxName: $err');
    }
    return null;
  }

  /// Get an open box safely.
  static Box<T> getBox<T>(String boxName) {
    if (!_report.isHealthy) {
      throw StateError(
        'HiveBoxManager is in recovery state due to corrupted box "${_report.failedBox}". Cannot access "$boxName".',
      );
    }
    return Hive.box<T>(boxName);
  }

  /// Reset internal state (for testing and restart recovery purposes).
  static void resetState() {
    _report = HiveRecoveryReport.healthy();
  }
}
