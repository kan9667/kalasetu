import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/offline_operation.dart';
import 'package:kalasetu/data/repositories/product_repository.dart';
import 'package:kalasetu/core/storage/hive_migration_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_migration_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('OfflineOperation Serialization & Legacy Migration', () {
    test('OfflineOperation parses legacy string action cleanly', () {
      final op = OfflineOperation.fromPendingString('CREATE', 'prod_123');
      expect(op.action, 'CREATE');
      expect(op.productId, 'prod_123');
      expect(op.idempotencyKey, startsWith('migrated_prod_123_'));
    });

    test('OfflineOperation round-trips modern JSON payload', () {
      final original = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: 'prod_999',
        revision: 2,
        contentHash: 'hash_abc123',
        idempotencyKey: 'idem_key_777',
        mediaId: 'media_uuid_456',
      );

      final jsonStr = original.toPendingString();
      final decoded = OfflineOperation.fromPendingString(jsonStr, 'prod_999');

      expect(decoded.action, OfflineOperation.actionApprovePublish);
      expect(decoded.productId, 'prod_999');
      expect(decoded.revision, 2);
      expect(decoded.contentHash, 'hash_abc123');
      expect(decoded.idempotencyKey, 'idem_key_777');
      expect(decoded.mediaId, 'media_uuid_456');
    });

    test('ProductRepository migrates legacy raw strings in pending_sync_box', () async {
      final pendingBox = await Hive.openBox<String>('pending_sync_box');
      await Hive.openBox<Product>('products_box');

      // Put legacy raw string entries
      await pendingBox.put('prod_legacy_1', 'CREATE');
      await pendingBox.put('prod_legacy_2', 'UPDATE');

      final repo = ProductRepository();
      await repo.migrateLegacyPendingQueueIfNeeded();

      // Check prod_legacy_1 was migrated to JSON
      final raw1 = pendingBox.get('prod_legacy_1')!;
      expect(raw1.startsWith('{'), isTrue);
      final json1 = jsonDecode(raw1) as Map<String, dynamic>;
      expect(json1['action'], 'CREATE');
      expect(json1['product_id'], 'prod_legacy_1');
      expect(json1['idempotency_key'], startsWith('migrated_prod_legacy_1_'));

      // Check prod_legacy_2 was migrated to JSON
      final raw2 = pendingBox.get('prod_legacy_2')!;
      expect(raw2.startsWith('{'), isTrue);
      final json2 = jsonDecode(raw2) as Map<String, dynamic>;
      expect(json2['action'], 'UPDATE');
      expect(json2['product_id'], 'prod_legacy_2');
    });
  });

  group('HiveMigrationRunner Scenarios', () {
    late Box appSettingsBox;
    late Box<Product> productsBox;
    late Box<String> pendingSyncBox;

    setUp(() async {
      appSettingsBox = await Hive.openBox('test_app_settings_box');
      productsBox = await Hive.openBox<Product>('test_products_box');
      pendingSyncBox = await Hive.openBox<String>('test_pending_sync_box');
      await appSettingsBox.clear();
      await productsBox.clear();
      await pendingSyncBox.clear();
    });

    tearDown(() async {
      await appSettingsBox.clear();
      await productsBox.clear();
      await pendingSyncBox.clear();
    });

    test('Scenario 1: Fresh install initializes schema_version to 1 without errors', () async {
      expect(appSettingsBox.get(HiveMigrationRunner.keySchemaVersion), isNull);

      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );

      expect(appSettingsBox.get(HiveMigrationRunner.keySchemaVersion), equals(1));
      expect(productsBox.isEmpty, isTrue);
    });

    test('Scenario 2: Legacy live product WITH active APPROVE_PUBLISH in pending_sync_box transitions to pendingApprovalSync with null approval metadata', () async {
      final legacyProduct = Product(
        id: 'prod_live_active_approval',
        title: 'Brass Diya',
        description: 'Handcrafted traditional brass oil lamp',
        price: 850.0,
        photoPath: '/local/photo.jpg',
        category: 'Metalwork',
        status: ProductStatus.live,
        revision: 2,
        approvedRevision: 2,
        approvedAt: DateTime.now(),
        approvedByArtisanId: 'art_123',
        publishedAt: DateTime.now(),
        contentHash: 'hash_abc',
      );
      await productsBox.put(legacyProduct.id, legacyProduct);

      // Active approval operation in outbox
      final op = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: 'prod_live_active_approval',
        revision: 2,
        contentHash: 'hash_abc',
        idempotencyKey: 'idem_key_live_1',
        status: OfflineOperation.statusPending,
      );
      await pendingSyncBox.put(op.id, op.toPendingString());

      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );

      final migrated = productsBox.get('prod_live_active_approval')!;
      expect(migrated.status, equals(ProductStatus.pendingApprovalSync));
      expect(migrated.approvedRevision, isNull, reason: 'Approval metadata must be null in pendingApprovalSync');
      expect(migrated.approvedAt, isNull);
      expect(migrated.approvedByArtisanId, isNull);
      expect(migrated.publishedAt, isNull);
      expect(migrated.revision, equals(2));
      expect(appSettingsBox.get(HiveMigrationRunner.keySchemaVersion), equals(1));
    });

    test('Scenario 3: Legacy live product WITHOUT active approval transitions to legacyUnverified with null approval metadata', () async {
      final legacyProduct = Product(
        id: 'prod_live_no_approval',
        title: 'Clay Pot',
        description: 'Terracotta water pot',
        price: 350.0,
        photoPath: '/local/pot.jpg',
        category: 'Pottery',
        status: ProductStatus.live,
        revision: 1,
        approvedRevision: 1,
        approvedAt: DateTime.now(),
        approvedByArtisanId: 'art_456',
        publishedAt: DateTime.now(),
        contentHash: 'hash_def',
      );
      await productsBox.put(legacyProduct.id, legacyProduct);

      // Pending sync box only has an unrelated UPDATE operation
      final op = OfflineOperation(
        action: OfflineOperation.actionUpdate,
        productId: 'prod_live_no_approval',
        idempotencyKey: 'idem_key_update_1',
      );
      await pendingSyncBox.put(op.id, op.toPendingString());

      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );

      final migrated = productsBox.get('prod_live_no_approval')!;
      expect(migrated.status, equals(ProductStatus.legacyUnverified));
      expect(migrated.approvedRevision, isNull, reason: 'Legacy unverified listing must have NULL approval metadata');
      expect(migrated.approvedAt, isNull);
      expect(migrated.approvedByArtisanId, isNull);
      expect(migrated.publishedAt, isNull);
    });

    test('Scenario 4: Legacy published product transitions to legacyUnverified or pendingApprovalSync based on outbox', () async {
      final prodNoApproval = Product(
        id: 'prod_published_none',
        title: 'Wool Shawl',
        description: 'Handwoven Pashmina shawl',
        price: 2500.0,
        photoPath: '/local/shawl.jpg',
        category: 'Textiles',
        status: ProductStatus.published,
        approvedRevision: 1,
        approvedAt: DateTime.now(),
        approvedByArtisanId: 'art_789',
        publishedAt: DateTime.now(),
      );
      final prodWithApproval = Product(
        id: 'prod_published_active',
        title: 'Silk Scarf',
        description: 'Kashmiri silk scarf',
        price: 1800.0,
        photoPath: '/local/scarf.jpg',
        category: 'Textiles',
        status: ProductStatus.published,
        approvedRevision: 1,
        approvedAt: DateTime.now(),
        approvedByArtisanId: 'art_789',
        publishedAt: DateTime.now(),
      );

      await productsBox.put(prodNoApproval.id, prodNoApproval);
      await productsBox.put(prodWithApproval.id, prodWithApproval);

      final op = OfflineOperation(
        action: OfflineOperation.actionApprovePublish,
        productId: 'prod_published_active',
        idempotencyKey: 'idem_key_pub_1',
      );
      await pendingSyncBox.put(op.id, op.toPendingString());

      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );

      final migratedNoApproval = productsBox.get('prod_published_none')!;
      expect(migratedNoApproval.status, equals(ProductStatus.legacyUnverified));
      expect(migratedNoApproval.approvedRevision, isNull);

      final migratedWithApproval = productsBox.get('prod_published_active')!;
      expect(migratedWithApproval.status, equals(ProductStatus.pendingApprovalSync));
      expect(migratedWithApproval.approvedRevision, isNull);
    });

    test('Scenario 5: Already migrated schema or non-live products are preserved without modification', () async {
      final draftProduct = Product(
        id: 'prod_draft',
        title: 'Wood Carving',
        description: 'Draft carving',
        price: 500.0,
        photoPath: '/local/wood.jpg',
        category: 'Woodwork',
        status: ProductStatus.draft,
      );
      final soldOutProduct = Product(
        id: 'prod_sold_out',
        title: 'Jute Bag',
        description: 'Eco-friendly jute bag',
        price: 200.0,
        photoPath: '/local/bag.jpg',
        category: 'Jute',
        status: ProductStatus.soldOut,
      );
      final legacyUnverified = Product(
        id: 'prod_already_legacy',
        title: 'Bangle',
        description: 'Glass bangle',
        price: 100.0,
        photoPath: '/local/bangle.jpg',
        category: 'Glass',
        status: ProductStatus.legacyUnverified,
      );

      await productsBox.put(draftProduct.id, draftProduct);
      await productsBox.put(soldOutProduct.id, soldOutProduct);
      await productsBox.put(legacyUnverified.id, legacyUnverified);

      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );

      expect(productsBox.get('prod_draft')!.status, equals(ProductStatus.draft));
      expect(productsBox.get('prod_sold_out')!.status, equals(ProductStatus.soldOut));
      expect(productsBox.get('prod_already_legacy')!.status, equals(ProductStatus.legacyUnverified));

      // Second run: when schema_version is already 1, nothing runs
      expect(appSettingsBox.get(HiveMigrationRunner.keySchemaVersion), equals(1));
      await HiveMigrationRunner.runMigrations(
        appSettingsBox: appSettingsBox,
        productsBox: productsBox,
        pendingSyncBox: pendingSyncBox,
      );
      expect(appSettingsBox.get(HiveMigrationRunner.keySchemaVersion), equals(1));
    });
  });
}
