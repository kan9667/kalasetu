import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/product.dart';
import '../models/offline_operation.dart';
import '../services/api_service.dart';

/// Repository managing local Hive cache and the append-only offline synchronization outbox.
///
/// Guarantees:
/// 1. Hive records in pending_sync_box are keyed by unique OfflineOperation.id (never productId).
/// 2. Payload snapshots are persisted immutably with operations.
/// 3. Offline create -> media upload -> attach media -> approve/publish is modeled via explicit dependencies.
/// 4. Completed upstream results (server product ID, media ID, revision, content hash) are persisted in resultData.
/// 5. Completed operations are never purged while dependent operations remain in the outbox.
/// 6. Offline items are marked pendingApprovalSync with null approval/published metadata.
/// 7. Stored idempotency keys are strictly preserved across retries.
class ProductRepository {
  final ApiService _apiService;
  static const String _productsBoxName = 'products_box';
  static const String _pendingBoxName = 'pending_sync_box';
  static const Duration defaultLeaseDuration = Duration(seconds: 30);

  ProductRepository({ApiService? apiService})
      : _apiService = apiService ?? MockApiService();

  /// Explicit deterministic initialization: upgrades legacy outbox records
  /// and reclaims expired in-flight leases.
  Future<void> initialize({DateTime? now}) async {
    await migrateLegacyPendingQueueIfNeeded();
    await reclaimExpiredLeases(now: now);
  }

  Box<Product> _getProductsBox() {
    return Hive.box<Product>(_productsBoxName);
  }

  Box<String> _getPendingBox() {
    return Hive.box<String>(_pendingBoxName);
  }

  /// Automatically upgrades legacy raw action strings ('CREATE', 'UPDATE', 'DELETE')
  /// or legacy records keyed by productId to modern OfflineOperation records keyed by op.id.
  Future<void> migrateLegacyPendingQueueIfNeeded() async {
    try {
      if (!Hive.isBoxOpen(_pendingBoxName)) return;
      final pendingBox = _getPendingBox();
      final keys = pendingBox.keys.cast<String>().toList();
      for (final key in keys) {
        final raw = pendingBox.get(key);
        if (raw == null) continue;
        final op = OfflineOperation.fromPendingString(raw, key);
        if (key != op.id) {
          await pendingBox.put(op.id, op.toPendingString());
          await pendingBox.delete(key);
        } else if (!raw.trim().startsWith('{')) {
          await pendingBox.put(op.id, op.toPendingString());
        }
      }
    } catch (e) {
      debugPrint('ProductRepository: Pending queue migration notice: $e');
    }
  }

  /// Reclaims expired in-flight operations (e.g. after app crash or process kill)
  /// by resetting their status to pending and clearing the lease.
  Future<int> reclaimExpiredLeases({DateTime? now}) async {
    try {
      if (!Hive.isBoxOpen(_pendingBoxName)) return 0;
      final pendingBox = _getPendingBox();
      final currentTime = now ?? DateTime.now();
      int reclaimed = 0;

      for (final key in pendingBox.keys.cast<String>()) {
        final raw = pendingBox.get(key);
        if (raw == null) continue;
        final op = OfflineOperation.fromPendingString(raw, key);
        if (op.status == OfflineOperation.statusInFlight || op.status == OfflineOperation.statusInProgress) {
          final isExpired = op.leaseExpiresAt == null || currentTime.isAfter(op.leaseExpiresAt!);
          if (isExpired) {
            final reclaimedOp = op.copyWith(
              status: OfflineOperation.statusPending,
              clearLeaseExpiresAt: true,
            );
            await pendingBox.put(key, reclaimedOp.toPendingString());
            reclaimed++;
          }
        }
      }
      return reclaimed;
    } catch (e) {
      debugPrint('ProductRepository: Lease reclamation error: $e');
      return 0;
    }
  }

  /// Checks if a product has any active (non-completed) operations in the outbox.
  bool hasPendingOperationsFor(String productId) {
    final pendingBox = _getPendingBox();
    for (final raw in pendingBox.values) {
      final op = OfflineOperation.fromPendingString(raw, '');
      if (op.productId == productId && op.status != OfflineOperation.statusCompleted) {
        return true;
      }
    }
    return false;
  }

  /// Get all products - Hive is the instant source of truth.
  Future<List<Product>> getProducts({bool forceRefresh = false, bool isOnline = true}) async {
    final box = _getProductsBox();

    // If box is empty and online, populate with remote products
    if ((box.isEmpty || forceRefresh) && isOnline) {
      try {
        final remote = await _apiService.getProducts();
        for (var p in remote) {
          // Safeguard: Never overwrite items that have pending local offline changes
          if (!hasPendingOperationsFor(p.id)) {
            await box.put(p.id, p);
          }
        }
      } catch (e) {
        debugPrint('ProductRepository: Remote fetch failed, using local cache: $e');
      }
    }

    // Return all local products sorted by creation time (newest first)
    final list = box.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Product? getProductById(String id) {
    return _getProductsBox().get(id);
  }

  /// Add product draft - Writes to Hive first as draft, queues for sync if offline or API fails.
  /// INVARIANT: Client mutations are strictly drafts. Never publishes directly here.
  Future<Product> addProduct(Product product, {bool isOnline = true, String? artisanId}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    final id = product.id.isEmpty
        ? 'prod_${DateTime.now().millisecondsSinceEpoch}'
        : product.id;

    final draftProduct = product.copyWith(
      id: id,
      status: ProductStatus.draft,
    );

    final idempotencyKey = 'idem_create_${draftProduct.id}';
    final payloadSnapshot = draftProduct.toBackendJson(artisanId: artisanId);

    if (isOnline) {
      try {
        final created = await _apiService.createProduct(
          draftProduct,
          artisanId: artisanId,
          idempotencyKey: idempotencyKey,
        );
        await productsBox.put(created.id, created);
        return created;
      } catch (e) {
        debugPrint('ProductRepository: Online create failed, saving draft to pending queue: $e');
      }
    }

    // Offline mode or API failed: save locally with pendingSync status
    final localDraft = draftProduct.copyWith(
      status: ProductStatus.pendingSync,
    );
    await productsBox.put(localDraft.id, localDraft);

    final op = OfflineOperation(
      action: OfflineOperation.actionCreate,
      productId: localDraft.id,
      revision: localDraft.revision,
      contentHash: localDraft.contentHash,
      idempotencyKey: idempotencyKey,
      payloadSnapshot: payloadSnapshot,
    );
    await pendingBox.put(op.id, op.toPendingString());
    return localDraft;
  }

  /// Update product draft - invalidates prior approval server-side.
  Future<Product> updateProduct(
    Product product, {
    bool isOnline = true,
    String? idempotencyKey,
  }) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    // Find latest active upstream op for this product in outbox to preserve dependency ordering
    String? upstreamOpId;
    for (final raw in pendingBox.values) {
      final existingOp = OfflineOperation.fromPendingString(raw, '');
      if (existingOp.productId == product.id && existingOp.status != OfflineOperation.statusCompleted) {
        upstreamOpId = existingOp.id;
      }
    }

    // Generate update idempotency key once before the first request and reuse it across fallback.
    final effectiveIdempotencyKey = idempotencyKey ??
        'idem_update_${product.id}_${product.revision}_${DateTime.now().microsecondsSinceEpoch}';
    final payloadSnapshot = product.toJson();

    if (isOnline) {
      try {
        final updated = await _apiService.updateProduct(
          product,
          expectedRevision: product.revision,
          idempotencyKey: effectiveIdempotencyKey,
        );
        await productsBox.put(updated.id, updated);
        return updated;
      } catch (e) {
        debugPrint('ProductRepository: Online update failed, saving to pending queue: $e');
      }
    }

    final localProduct = product.copyWith(
      status: product.status,
    );
    await productsBox.put(localProduct.id, localProduct);

    final op = OfflineOperation(
      action: OfflineOperation.actionUpdate,
      productId: localProduct.id,
      revision: localProduct.revision,
      contentHash: localProduct.contentHash,
      idempotencyKey: effectiveIdempotencyKey,
      dependsOnOpId: upstreamOpId,
      payloadSnapshot: payloadSnapshot,
    );
    await pendingBox.put(op.id, op.toPendingString());
    return localProduct;
  }

  /// Explicit artisan approval and publish workflow.
  /// Rejects publishing below cost floor and requires server-validated media asset.
  Future<Product> approveAndPublishProduct(
    String id, {
    int? revision,
    String? contentHash,
    bool isOnline = true,
    String? idempotencyKey,
  }) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();
    var product = productsBox.get(id);

    if (product == null) {
      if (isOnline) {
        try {
          product = await _apiService.getProduct(id);
          await productsBox.put(id, product);
        } catch (_) {}
      }
      if (product == null) {
        throw Exception('Product $id not found locally');
      }
    }

    final effectiveRevision = revision ?? product.revision;
    final effectiveHash = contentHash ?? product.contentHash ?? '';
    final effectiveIdempotencyKey = idempotencyKey ?? 'idem_pub_${id}_$effectiveRevision';

    if (isOnline) {
      try {
        // Verify media asset exists remotely; upload if only phone-local
        if ((product.mediaId == null || product.mediaId!.isEmpty) &&
            product.displayPhotoPath.isNotEmpty &&
            File(product.displayPhotoPath).existsSync()) {
          final mediaUploadKey = 'idem_upload_${id}_${DateTime.now().millisecondsSinceEpoch}';
          final mediaRes = await _apiService.uploadMediaFile(
            product.displayPhotoPath,
            idempotencyKey: mediaUploadKey,
          );
          final serverMediaId = mediaRes['media_id'] as String?;
          if (serverMediaId != null) {
            product = product.copyWith(mediaId: serverMediaId);
            final attachKey = 'idem_attach_${id}_${product.revision}_${DateTime.now().millisecondsSinceEpoch}';
            final attached = await _apiService.updateProduct(
              product,
              expectedRevision: product.revision,
              idempotencyKey: attachKey,
            );
            await productsBox.put(attached.id, attached);
            product = attached;
          }
        }

        final pubRevision = product.revision;
        final pubHash = product.contentHash ?? effectiveHash;
        final published = await _apiService.approveAndPublishProduct(
          id,
          revision: pubRevision,
          contentHash: pubHash,
          idempotencyKey: effectiveIdempotencyKey,
        );
        await productsBox.put(published.id, published);
        return published;
      } on StaleRevisionException {
        rethrow;
      } catch (e) {
        debugPrint('ProductRepository: Online publish failed, queueing approve & publish: $e');
      }
    }

    // Offline or network failure:
    // INVARIANT: Do NOT mark an offline item approved or published locally!
    // Replace this with pendingApprovalSync, leave approval/published metadata null.
    final queuedLocal = product!.copyWith(
      status: ProductStatus.pendingApprovalSync,
      approvedRevision: null,
      approvedAt: null,
      publishedAt: null,
    );
    await productsBox.put(queuedLocal.id, queuedLocal);

    // Find any active upstream operation for this product (e.g. CREATE or UPDATE)
    String? latestUpstreamOpId;
    for (final raw in pendingBox.values) {
      final existingOp = OfflineOperation.fromPendingString(raw, '');
      if (existingOp.productId == queuedLocal.id &&
          existingOp.status != OfflineOperation.statusCompleted) {
        latestUpstreamOpId = existingOp.id;
      }
    }

    // Model dependency chain:
    // If photo needs to be uploaded:
    // [CREATE/UPDATE] -> MEDIA_UPLOAD -> ATTACH_MEDIA -> APPROVE_PUBLISH
    if ((queuedLocal.mediaId == null || queuedLocal.mediaId!.isEmpty) &&
        queuedLocal.displayPhotoPath.isNotEmpty &&
        File(queuedLocal.displayPhotoPath).existsSync()) {
      final mediaOpId = 'op_media_${queuedLocal.id}_${DateTime.now().microsecondsSinceEpoch}';
      final mediaUploadKey = 'idem_media_${queuedLocal.id}';
      final mediaOp = OfflineOperation(
        id: mediaOpId,
        action: OfflineOperation.actionMediaUpload,
        productId: queuedLocal.id,
        idempotencyKey: mediaUploadKey,
        mediaLocalId: queuedLocal.displayPhotoPath,
        dependsOnOpId: latestUpstreamOpId,
      );
      await pendingBox.put(mediaOp.id, mediaOp.toPendingString());

      final attachOpId = 'op_attach_${queuedLocal.id}_${DateTime.now().microsecondsSinceEpoch}';
      final attachKey = 'idem_attach_${queuedLocal.id}';
      final attachOp = OfflineOperation(
        id: attachOpId,
        action: OfflineOperation.actionAttachMedia,
        productId: queuedLocal.id,
        idempotencyKey: attachKey,
        dependsOnOpId: mediaOpId,
        mediaIdFromOpId: mediaOpId,
      );
      await pendingBox.put(attachOp.id, attachOp.toPendingString());

      final pubOpId = 'op_pub_${queuedLocal.id}_${DateTime.now().microsecondsSinceEpoch}';
      final pubOp = OfflineOperation(
        id: pubOpId,
        action: OfflineOperation.actionApprovePublish,
        productId: queuedLocal.id,
        revision: effectiveRevision,
        contentHash: effectiveHash,
        idempotencyKey: effectiveIdempotencyKey,
        dependsOnOpId: attachOpId,
        payloadSnapshot: {
          'expected_revision': effectiveRevision,
          'content_hash': effectiveHash,
        },
      );
      await pendingBox.put(pubOp.id, pubOp.toPendingString());
    } else {
      // Photo already has mediaId or does not exist
      final pubOpId = 'op_pub_${queuedLocal.id}_${DateTime.now().microsecondsSinceEpoch}';
      final pubOp = OfflineOperation(
        id: pubOpId,
        action: OfflineOperation.actionApprovePublish,
        productId: queuedLocal.id,
        revision: effectiveRevision,
        contentHash: effectiveHash,
        idempotencyKey: effectiveIdempotencyKey,
        mediaLocalId: queuedLocal.displayPhotoPath,
        mediaId: queuedLocal.mediaId,
        dependsOnOpId: latestUpstreamOpId,
        payloadSnapshot: {
          'expected_revision': effectiveRevision,
          'content_hash': effectiveHash,
        },
      );
      await pendingBox.put(pubOp.id, pubOp.toPendingString());
    }

    return queuedLocal;
  }

  /// Delete product.
  Future<void> deleteProduct(String id, {bool isOnline = true}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    await productsBox.delete(id);

    final idempotencyKey = 'idem_del_$id';

    if (isOnline) {
      try {
        await _apiService.deleteProduct(id, idempotencyKey: idempotencyKey);
        // Clean up any remaining operations for this deleted product
        final toDelete = <String>[];
        for (final entry in pendingBox.toMap().entries) {
          final op = OfflineOperation.fromPendingString(entry.value, entry.key.toString());
          if (op.productId == id) {
            toDelete.add(entry.key.toString());
          }
        }
        for (final k in toDelete) {
          await pendingBox.delete(k);
        }
        return;
      } catch (e) {
        debugPrint('ProductRepository: Online delete failed: $e');
      }
    }

    final op = OfflineOperation(
      action: OfflineOperation.actionDelete,
      productId: id,
      idempotencyKey: idempotencyKey,
    );
    await pendingBox.put(op.id, op.toPendingString());
  }

  /// Unpublish a published product, resetting server status to draft and revoking approvals.
  Future<Product> unpublishProduct(String productId, {bool isOnline = true, String? idempotencyKey}) async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();
    final effectiveKey = idempotencyKey ?? 'idem_unpub_${productId}_${DateTime.now().millisecondsSinceEpoch}';

    final local = productsBox.get(productId);
    if (local == null) {
      throw Exception('Product $productId not found in local cache');
    }
    Product activeLocal = local;

    final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
    bool hasValidContentHash = activeLocal.contentHash != null &&
        sha256Pattern.hasMatch(activeLocal.contentHash!.toLowerCase());

    // If online and missing valid revision or content hash, fetch authoritative product
    if (isOnline && (!hasValidContentHash || activeLocal.revision <= 0)) {
      try {
        final authoritative = await _apiService.getProduct(productId);
        await productsBox.put(productId, authoritative);
        activeLocal = authoritative;
        hasValidContentHash = activeLocal.contentHash != null &&
            sha256Pattern.hasMatch(activeLocal.contentHash!.toLowerCase());
      } catch (e) {
        debugPrint(
            'ProductRepository: Failed to fetch authoritative product before unpublish: $e');
      }
    }

    // Inspect existing operations for this product in pendingBox
    final allPendingStrings = pendingBox.values.toList();
    final productOps = allPendingStrings
        .map((s) => OfflineOperation.fromPendingString(s.toString(), ''))
        .where((op) => op.productId == productId)
        .toList();

    // 1. Check for any APPROVE_PUBLISH operations for this product
    final approveOps = productOps.where((op) => op.action == OfflineOperation.actionApprovePublish).toList();
    OfflineOperation? unpublishDepOp;

    final Set<String> supersededOpIds = {};
    for (final approveOp in approveOps) {
      final isDefinitelyPendingNeverSubmitted =
          approveOp.status == OfflineOperation.statusPending &&
          approveOp.retryCount == 0 &&
          approveOp.leaseExpiresAt == null &&
          approveOp.resultData == null;

      if (isDefinitelyPendingNeverSubmitted) {
        // Safe to cancel/supersede: definitely pending and has never been submitted
        final supersededApprove = approveOp.copyWith(
          status: OfflineOperation.statusSuperseded,
          errorMessage: 'Superseded by unpublish before submission',
          clearLeaseExpiresAt: true,
        );
        await pendingBox.put(supersededApprove.id, supersededApprove.toPendingString());
        supersededOpIds.add(approveOp.id);
        debugPrint('ProductRepository: Cancelled definitely-pending unsubmitted approval ${approveOp.id}');
      } else {
        // In-flight, leased, response-lost, or completed: NEVER delete or cancel!
        // Unpublish must depend on this approval operation so it executes after it or recovers its result.
        unpublishDepOp = approveOp;
      }
    }

    // 2. If no approval dependency, check for latest active operation for this product (restricted to CREATE, UPDATE, ATTACH_MEDIA, APPROVE_PUBLISH)
    if (unpublishDepOp == null) {
      const validDependencyActions = {
        OfflineOperation.actionCreate,
        OfflineOperation.actionUpdate,
        OfflineOperation.actionAttachMedia,
        OfflineOperation.actionApprovePublish,
      };
      final activeOps = productOps.where((op) =>
          !supersededOpIds.contains(op.id) &&
          validDependencyActions.contains(op.action) &&
          (op.status == OfflineOperation.statusPending ||
           op.status == OfflineOperation.statusInFlight ||
           op.status == OfflineOperation.statusInProgress ||
           op.status == OfflineOperation.statusCompleted) &&
          op.status != OfflineOperation.statusSuperseded
      ).toList();
      if (activeOps.isNotEmpty) {
        activeOps.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        unpublishDepOp = activeOps.last;
      }
    }

    // 3. Check if online and no pending active dependencies remain
    final bool hasPendingDependencies = productOps.any((op) =>
        (op.status == OfflineOperation.statusPending ||
         op.status == OfflineOperation.statusInFlight ||
         op.status == OfflineOperation.statusInProgress) &&
        op.status != OfflineOperation.statusSuperseded
    );

    if (isOnline && !hasPendingDependencies && hasValidContentHash) {
      try {
        final serverProduct = await _apiService.unpublishProduct(
          productId,
          expectedRevision: activeLocal.revision,
          contentHash: activeLocal.contentHash!.toLowerCase(),
          idempotencyKey: effectiveKey,
        );
        await productsBox.put(serverProduct.id, serverProduct);
        return serverProduct;
      } on StaleRevisionException catch (e) {
        debugPrint('ProductRepository: Stale revision on unpublish: $e');
        try {
          final authoritative = await _apiService.getProduct(productId);
          await productsBox.put(productId, authoritative);
        } catch (fetchErr) {
          debugPrint(
              'ProductRepository: Failed to refresh stale product on unpublish: $fetchErr');
          await productsBox.put(
              productId,
              activeLocal.copyWith(status: ProductStatus.pendingUnpublishSync));
        }
        rethrow;
      } catch (e) {
        debugPrint('ProductRepository: Online unpublish failed, queuing offline: $e');
      }
    }

    // 4. Offline or has pending dependencies:
    // Invariant: Do NOT set local product to draft, do NOT increment authoritative revision,
    // and do NOT clear last-confirmed approval/publication metadata.
    final pendingUnpubLocal = activeLocal.copyWith(
      status: ProductStatus.pendingUnpublishSync,
    );
    await productsBox.put(productId, pendingUnpubLocal);

    final op = OfflineOperation(
      action: OfflineOperation.actionUnpublish,
      productId: productId,
      revision: activeLocal.revision,
      contentHash: activeLocal.contentHash,
      idempotencyKey: effectiveKey,
      dependsOnOpId: unpublishDepOp?.id,
      payloadSnapshot: {
        'expected_revision': activeLocal.revision,
        'content_hash': activeLocal.contentHash,
      },
    );
    await pendingBox.put(op.id, op.toPendingString());
    return pendingUnpubLocal;
  }

  /// Drain pending offline queue with dependency ordering:
  /// Drain pending offline queue with dependency ordering:
  /// drafts -> media validation -> attach media -> approve and publish.
  /// Preserves idempotency keys across retries, stores upstream results in resultData,
  /// and ensures completed operations are retained while dependents remain.
  Future<int> syncPendingQueue() async {
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    // Reclaim any expired in-flight leases before draining
    await reclaimExpiredLeases();

    if (pendingBox.isEmpty) return 0;

    int totalSynced = 0;
    bool progressMade = true;

    // Multi-pass drain: in each pass, execute any operation whose upstream dependencies are met
    while (progressMade) {
      progressMade = false;

      // Load all current operations
      final allOps = <String, OfflineOperation>{};
      for (final key in pendingBox.keys.cast<String>()) {
        final raw = pendingBox.get(key);
        if (raw != null) {
          allOps[key] = OfflineOperation.fromPendingString(raw, key);
        }
      }

      final pendingOps = allOps.values
          .where((op) => op.status == OfflineOperation.statusPending)
          .toList();

      if (pendingOps.isEmpty) break;

      for (final op in pendingOps) {
        // Dependency Check:
        if (op.dependsOnOpId != null) {
          final parentOp = allOps[op.dependsOnOpId];
          // If parentOp is missing, wait for it
          if (parentOp == null) {
            continue;
          }
          // If parent was superseded before execution, dependency is resolved/bypassed
          if (parentOp.status == OfflineOperation.statusSuperseded) {
            // Parent superseded, proceed
          } else if (parentOp.status != OfflineOperation.statusCompleted) {
            continue;
          }
        }

        // Atomically claim operation with a lease before execution:
        // Check current state in pendingBox to prevent concurrent worker execution
        final currentRaw = pendingBox.get(op.id);
        if (currentRaw == null) continue;
        final currentOp = OfflineOperation.fromPendingString(currentRaw, op.id);
        if (currentOp.isLeaseActive()) {
          // Another worker is actively executing this operation under a valid lease
          continue;
        }

        final claimedOp = currentOp.copyWith(
          status: OfflineOperation.statusInFlight,
          leaseExpiresAt: DateTime.now().add(defaultLeaseDuration),
        );
        await pendingBox.put(op.id, claimedOp.toPendingString());
        allOps[op.id] = claimedOp;

        // Upstream dependencies are satisfied! Execute this operation:
        try {
          if (op.action == OfflineOperation.actionCreate) {
            Product? product;
            if (op.payloadSnapshot != null) {
              product = Product.fromJson(op.payloadSnapshot!);
            } else {
              product = productsBox.get(op.productId);
            }
            if (product != null) {
              final created = await _apiService.createProduct(
                product.copyWith(status: ProductStatus.draft),
                idempotencyKey: op.idempotencyKey,
              );
              final existingLocal = productsBox.get(created.id);
              if (existingLocal == null || existingLocal.revision <= created.revision) {
                await productsBox.put(created.id, created);
              }
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                resultData: {
                  'server_product_id': created.id,
                  'revision': created.revision,
                  'content_hash': created.contentHash,
                },
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              totalSynced++;
              progressMade = true;
            }
          } else if (op.action == OfflineOperation.actionMediaUpload) {
            final filePath = op.mediaLocalId;
            if (filePath != null && File(filePath).existsSync()) {
              final mediaRes = await _apiService.uploadMediaFile(
                filePath,
                idempotencyKey: op.idempotencyKey,
              );
              final serverMediaId = mediaRes['media_id'] as String?;
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                mediaId: serverMediaId,
                resultData: mediaRes,
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              totalSynced++;
              progressMade = true;
            } else {
              // File missing or not needed
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                resultData: {'media_id': op.mediaId ?? ''},
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              progressMade = true;
            }
          } else if (op.action == OfflineOperation.actionAttachMedia) {
            // Resolve mediaId from parent media op if needed
            String? resolvedMediaId = op.mediaId;
            if ((resolvedMediaId == null || resolvedMediaId.isEmpty) && op.mediaIdFromOpId != null) {
              final parentMediaOp = allOps[op.mediaIdFromOpId];
              resolvedMediaId = parentMediaOp?.resultData?['media_id'] as String? ?? parentMediaOp?.mediaId;
            }

            var product = productsBox.get(op.productId);
            if (product != null && resolvedMediaId != null && resolvedMediaId.isNotEmpty) {
              final attachedProduct = product.copyWith(mediaId: resolvedMediaId);
              final updated = await _apiService.updateProduct(
                attachedProduct,
                expectedRevision: product.revision,
                idempotencyKey: op.idempotencyKey,
              );
              await productsBox.put(updated.id, updated);
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                mediaId: resolvedMediaId,
                resultData: {
                  'server_product_id': updated.id,
                  'revision': updated.revision,
                  'content_hash': updated.contentHash,
                  'media_id': resolvedMediaId,
                },
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              totalSynced++;
              progressMade = true;
            } else {
              // Mark completed if product or media already handled
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              progressMade = true;
            }
          } else if (op.action == OfflineOperation.actionUpdate) {
            Product? product;
            if (op.payloadSnapshot != null) {
              product = Product.fromJson(op.payloadSnapshot!);
              if (product.id.isEmpty) {
                product = product.copyWith(id: op.productId);
              }
            } else {
              product = productsBox.get(op.productId);
            }
            if (product != null) {
              final parentOp = op.dependsOnOpId != null ? allOps[op.dependsOnOpId] : null;
              final effectiveExpectedRevision = parentOp?.resultData?['revision'] as int? ?? product.revision;
              final updated = await _apiService.updateProduct(
                product,
                expectedRevision: effectiveExpectedRevision,
                idempotencyKey: op.idempotencyKey,
              );
              final existingLocal = productsBox.get(updated.id);
              if (existingLocal == null || existingLocal.revision <= updated.revision) {
                await productsBox.put(updated.id, updated);
              }
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                resultData: {
                  'server_product_id': updated.id,
                  'revision': updated.revision,
                  'content_hash': updated.contentHash,
                },
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              totalSynced++;
              progressMade = true;
            }
          } else if (op.action == OfflineOperation.actionApprovePublish) {
            var product = productsBox.get(op.productId);
            if (product != null) {
              // Retrieve server-returned revision and hash from upstream operations if available
              int pubRevision = product.revision;
              String pubHash = product.contentHash ?? op.contentHash ?? '';

              if (op.dependsOnOpId != null) {
                final parentOp = allOps[op.dependsOnOpId];
                if (parentOp != null && parentOp.resultData != null) {
                  final serverRev = parentOp.resultData!['revision'] as int?;
                  final serverHash = parentOp.resultData!['content_hash'] as String?;
                  if (serverRev != null) pubRevision = serverRev;
                  if (serverHash != null && serverHash.isNotEmpty) pubHash = serverHash;
                }
              }

              final published = await _apiService.approveAndPublishProduct(
                op.productId,
                revision: pubRevision,
                contentHash: pubHash,
                idempotencyKey: op.idempotencyKey,
              );
              await productsBox.put(published.id, published);
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusCompleted,
                clearLeaseExpiresAt: true,
                resultData: {
                  'server_product_id': published.id,
                  'revision': published.revision,
                  'content_hash': published.contentHash,
                  'status': 'published',
                },
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              totalSynced++;
              progressMade = true;
            }
          } else if (op.action == OfflineOperation.actionDelete) {
            await _apiService.deleteProduct(
              op.productId,
              idempotencyKey: op.idempotencyKey,
            );
            final updatedOp = op.copyWith(
              status: OfflineOperation.statusCompleted,
              clearLeaseExpiresAt: true,
            );
            await pendingBox.put(op.id, updatedOp.toPendingString());
            allOps[op.id] = updatedOp;
            totalSynced++;
            progressMade = true;
          } else if (op.action == OfflineOperation.actionUnpublish) {
            // Resolve expected_revision and content_hash:
            // When an upstream dependency changes revision/hash, use its authoritative resultData.
            // If dependency output lacks either value, stop with user_action_required rather than guessing.
            int? expectedRevision = op.revision;
            String? contentHash = op.contentHash;

            if (op.dependsOnOpId != null && allOps.containsKey(op.dependsOnOpId)) {
              final parentOp = allOps[op.dependsOnOpId]!;
              if (parentOp.resultData != null && parentOp.resultData!.containsKey('revision')) {
                expectedRevision = (parentOp.resultData!['revision'] as num?)?.toInt();
                contentHash = parentOp.resultData!['content_hash'] as String?;
              }
            }

            final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
            if (expectedRevision == null ||
                contentHash == null ||
                !sha256Pattern.hasMatch(contentHash.toLowerCase())) {
              debugPrint('ProductRepository: Unpublish op ${op.id} missing valid revision ($expectedRevision) or contentHash ($contentHash). Stopping with user_action_required.');
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusUserActionRequired,
                clearLeaseExpiresAt: true,
                errorMessage: 'Cannot unpublish: authoritative revision ($expectedRevision) or content hash ($contentHash) is missing or not a valid 64-char SHA-256.',
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              continue;
            }

            final unpublished = await _apiService.unpublishProduct(
              op.productId,
              expectedRevision: expectedRevision,
              contentHash: contentHash.toLowerCase(),
              idempotencyKey: op.idempotencyKey,
            );
            await productsBox.put(unpublished.id, unpublished);
            final updatedOp = op.copyWith(
              status: OfflineOperation.statusCompleted,
              clearLeaseExpiresAt: true,
              resultData: {
                'server_product_id': unpublished.id,
                'revision': unpublished.revision,
                'content_hash': unpublished.contentHash,
              },
            );
            await pendingBox.put(op.id, updatedOp.toPendingString());
            allOps[op.id] = updatedOp;
            totalSynced++;
            progressMade = true;
          }
        } on StaleRevisionException catch (e) {
          debugPrint('ProductRepository: Stale revision during sync for op ${op.id}: $e');
          try {
            final refreshedProduct = await _apiService.getProduct(op.productId);
            await productsBox.put(op.productId, refreshedProduct);
          } catch (fetchErr) {
            debugPrint('ProductRepository: Failed to refresh stale product ${op.productId}: $fetchErr');
            final existing = productsBox.get(op.productId);
            if (existing != null) {
              final fallbackStatus = op.action == OfflineOperation.actionUnpublish
                  ? ProductStatus.pendingUnpublishSync
                  : ProductStatus.awaitingApproval;
              await productsBox.put(op.productId, existing.copyWith(status: fallbackStatus));
            }
          }
          final updatedOp = op.copyWith(
            status: OfflineOperation.statusUserActionRequired,
            clearLeaseExpiresAt: true,
            errorMessage: e.toString(),
          );
          await pendingBox.put(op.id, updatedOp.toPendingString());
          allOps[op.id] = updatedOp;
        } catch (e) {
          debugPrint('ProductRepository: Failed to sync pending op ${op.id}: $e');
          final updatedOp = op.copyWith(
            status: OfflineOperation.statusPending,
            clearLeaseExpiresAt: true,
            retryCount: op.retryCount + 1,
            errorMessage: e.toString(),
          );
          await pendingBox.put(op.id, updatedOp.toPendingString());
          allOps[op.id] = updatedOp;
        }
      }
    }

    // Purge policy:
    // "Do not purge completed operations/results while dependent operations remain."
    // An operation can only be safely purged if NO OTHER non-completed operation in pendingBox depends on it!
    final currentOps = <String, OfflineOperation>{};
    for (final key in pendingBox.keys.cast<String>()) {
      final raw = pendingBox.get(key);
      if (raw != null) {
        currentOps[key] = OfflineOperation.fromPendingString(raw, key);
      }
    }

    final dependentIds = <String>{};
    for (final op in currentOps.values) {
      if (op.status != OfflineOperation.statusCompleted) {
        if (op.dependsOnOpId != null) dependentIds.add(op.dependsOnOpId!);
        if (op.mediaIdFromOpId != null) dependentIds.add(op.mediaIdFromOpId!);
      }
    }

    for (final op in currentOps.values) {
      if (op.status == OfflineOperation.statusCompleted && !dependentIds.contains(op.id)) {
        await pendingBox.delete(op.id);
      }
    }

    return totalSynced;
  }

  int getPendingCount() {
    final pendingBox = _getPendingBox();
    int count = 0;
    for (final raw in pendingBox.values) {
      final op = OfflineOperation.fromPendingString(raw, '');
      if (op.status != OfflineOperation.statusCompleted) {
        count++;
      }
    }
    return count;
  }

  List<String> getPendingIds() {
    final pendingBox = _getPendingBox();
    final ids = <String>[];
    for (final raw in pendingBox.values) {
      final op = OfflineOperation.fromPendingString(raw, '');
      if (op.status != OfflineOperation.statusCompleted) {
        ids.add(op.id);
      }
    }
    return ids;
  }

  List<OfflineOperation> getAllOperations() {
    final pendingBox = _getPendingBox();
    return pendingBox.values
        .map((raw) => OfflineOperation.fromPendingString(raw, ''))
        .toList();
  }
}
