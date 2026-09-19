import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../data/models/offline_operation.dart';
import '../../data/models/product.dart';
import 'hive_box_manager.dart';

/// Manages versioned data migrations for local Hive boxes.
///
/// Ensures backward-compatibility when schemas change or when legacy unverified
/// listings must be transitioned safely according to Trust & Data Integrity rules.
class HiveMigrationRunner {
  static const int currentSchemaVersion = 1;
  static const String keySchemaVersion = 'schema_version';

  /// Runs all pending schema migrations sequentially.
  ///
  /// Can accept explicit boxes (useful for isolated unit testing) or default to
  /// the boxes registered in [HiveBoxManager].
  static Future<void> runMigrations({
    Box? appSettingsBox,
    Box<Product>? productsBox,
    Box<String>? pendingSyncBox,
  }) async {
    final settingsBox = appSettingsBox ??
        (Hive.isBoxOpen(HiveBoxManager.boxAppSettings)
            ? Hive.box(HiveBoxManager.boxAppSettings)
            : await Hive.openBox(HiveBoxManager.boxAppSettings));

    final currentVersion =
        (settingsBox.get(keySchemaVersion, defaultValue: 0) as num).toInt();

    if (currentVersion >= currentSchemaVersion) {
      debugPrint(
          '[HiveMigrationRunner] Schema is already up-to-date (v$currentVersion).');
      return;
    }

    debugPrint(
        '[HiveMigrationRunner] Upgrading schema from v$currentVersion to v$currentSchemaVersion...');

    if (currentVersion < 1) {
      await _migrateToV1(
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );
      await settingsBox.put(keySchemaVersion, 1);
      debugPrint('[HiveMigrationRunner] Successfully migrated schema to v1.');
    }
  }

  /// Migration v1:
  /// Resolves legacy cached listings that had status `live` or `published`:
  /// - If an active `APPROVE_PUBLISH` operation is found in `pending_sync_box`,
  ///   the product is transitioned to `pendingApprovalSync` with approval metadata strictly NULL.
  /// - Otherwise, the product is transitioned to `legacyUnverified` with approval metadata strictly NULL.
  /// - All other product statuses (`draft`, `soldOut`, etc.) are preserved.
  static Future<void> _migrateToV1({
    Box<Product>? productsBox,
    Box<String>? pendingSyncBox,
  }) async {
    final pBox = productsBox ??
        (Hive.isBoxOpen(HiveBoxManager.boxProducts)
            ? Hive.box<Product>(HiveBoxManager.boxProducts)
            : await Hive.openBox<Product>(HiveBoxManager.boxProducts));

    final syncBox = pendingSyncBox ??
        (Hive.isBoxOpen(HiveBoxManager.boxPendingSync)
            ? Hive.box<String>(HiveBoxManager.boxPendingSync)
            : await Hive.openBox<String>(HiveBoxManager.boxPendingSync));

    // 1. Scan pending_sync_box for active approval operations
    final activeApprovalProductIds = <String>{};
    for (final key in syncBox.keys) {
      final raw = syncBox.get(key);
      if (raw == null) continue;
      try {
        final op = OfflineOperation.fromPendingString(raw, key.toString());
        if (op.action == OfflineOperation.actionApprovePublish &&
            op.status != OfflineOperation.statusCompleted &&
            op.status != OfflineOperation.statusSuperseded) {
          activeApprovalProductIds.add(op.productId);
        }
      } catch (e) {
        debugPrint(
            '[HiveMigrationRunner] Skipping unparseable pending op $key: $e');
      }
    }

    // 2. Scan products_box and migrate legacy live/published rows
    for (final key in pBox.keys.toList()) {
      final product = pBox.get(key);
      if (product == null) continue;

      if (product.status == ProductStatus.live ||
          product.status == ProductStatus.published) {
        final hasActiveApproval = activeApprovalProductIds.contains(product.id);

        final migrated = product.copyWith(
          status: hasActiveApproval
              ? ProductStatus.pendingApprovalSync
              : ProductStatus.legacyUnverified,
          clearApprovalMetadata: true,
        );

        await pBox.put(key, migrated);
        debugPrint(
            '[HiveMigrationRunner] Migrated product ${product.id} from ${product.status} to ${migrated.status} (hasActiveApproval=$hasActiveApproval)');
      }
    }
  }
}
