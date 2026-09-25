import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../core/config/api_config.dart';
import '../../core/network/active_session_manager.dart';
import '../../core/network/session_expired_exception.dart';
import '../../core/storage/private_media_cache.dart';
import '../models/product.dart';
import '../models/offline_operation.dart';
import '../services/api_service.dart';

class _SessionChangedInternalException implements Exception {}

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

  Future<void>? _initFuture;
  bool _isInitialized = false;

  /// Explicit single-flight deterministic initialization: upgrades legacy outbox records
  /// and reclaims expired in-flight leases.
  Future<void> initialize({DateTime? now}) {
    if (_isInitialized) return Future.value();
    if (_initFuture != null) return _initFuture!;
    return _initFuture = _doInitialize(now).then((_) {
      _isInitialized = true;
    });
  }

  Future<void> _doInitialize(DateTime? now) async {
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
  /// Also performs non-destructive provenance recovery for operations lacking owner or backend:
  /// - Attempts recovery of owner from payloadSnapshot (artisan_id, artisanId, approved_by_artisan_id)
  ///   or parent dependency chains.
  /// - Attempts recovery of backend from parent/child dependency chains.
  /// - If provenance cannot be established, transitions pending operation to statusUserActionRequired
  ///   without deleting or assuming current active artisan session.
  Future<void> migrateLegacyPendingQueueIfNeeded() async {
    if (!Hive.isBoxOpen(_pendingBoxName)) return;
    final pendingBox = _getPendingBox();
    final keys = pendingBox.keys.cast<String>().toList();

    // First pass: re-key legacy productId keys to op.id and decode
    final allOps = <String, OfflineOperation>{};
    for (final key in keys) {
      final raw = pendingBox.get(key);
      if (raw == null) continue;
      final op = OfflineOperation.fromPendingString(raw, key);
      if (key != op.id) {
        await pendingBox.put(op.id, op.toPendingString());
        await pendingBox.delete(key);
        allOps[op.id] = op;
      } else if (!raw.trim().startsWith('{')) {
        await pendingBox.put(op.id, op.toPendingString());
        allOps[op.id] = op;
      } else {
        allOps[key] = op;
      }
    }

    // Provenance recovery passes:
    // 1. Recover owner from payloadSnapshot
    for (final entry in allOps.entries) {
      var op = entry.value;
      if (op.owner == null || op.owner!.isEmpty) {
        String? recoveredOwner;
        if (op.payloadSnapshot != null) {
          recoveredOwner = op.payloadSnapshot!['artisan_id'] as String? ??
              op.payloadSnapshot!['artisanId'] as String? ??
              op.payloadSnapshot!['approved_by_artisan_id'] as String? ??
              op.payloadSnapshot!['approvedByArtisanId'] as String?;
        }
        if (recoveredOwner != null && recoveredOwner.isNotEmpty) {
          op = op.copyWith(owner: recoveredOwner);
          allOps[entry.key] = op;
          await pendingBox.put(op.id, op.toPendingString());
        }
      }
    }

    // 2. Propagate owner and backend across dependency chains (forward & backward)
    bool changed = true;
    while (changed) {
      changed = false;
      for (final entry in allOps.entries) {
        var op = entry.value;
        String? newOwner = op.owner;
        String? newBackend = op.backend;

        if (op.dependsOnOpId != null && allOps.containsKey(op.dependsOnOpId)) {
          final parent = allOps[op.dependsOnOpId]!;
          if ((newOwner == null || newOwner.isEmpty) && parent.owner != null && parent.owner!.isNotEmpty) {
            newOwner = parent.owner;
          }
          if ((newBackend == null || newBackend.isEmpty) && parent.backend != null && parent.backend!.isNotEmpty) {
            newBackend = parent.backend;
          }
        }

        // Also check if any child has owner/backend that this parent lacks
        for (final other in allOps.values) {
          if (other.dependsOnOpId == op.id) {
            if ((newOwner == null || newOwner.isEmpty) && other.owner != null && other.owner!.isNotEmpty) {
              newOwner = other.owner;
            }
            if ((newBackend == null || newBackend.isEmpty) && other.backend != null && other.backend!.isNotEmpty) {
              newBackend = other.backend;
            }
          }
        }

        if (newOwner != op.owner || newBackend != op.backend) {
          op = op.copyWith(owner: newOwner, backend: newBackend);
          allOps[entry.key] = op;
          await pendingBox.put(op.id, op.toPendingString());
          changed = true;
        }
      }
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
    await initialize();
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
  /// Add product draft - Writes to Hive first as draft, queues for sync if offline or API fails.
  /// INVARIANT: Client mutations are strictly drafts. Never publishes directly here.
  Future<Product> addProduct(Product product, {bool isOnline = true, String? artisanId}) async {
    // Capture initiating session identity BEFORE any async work
    final initiatingUserId = artisanId ?? ActiveSessionManager.getCurrentUserIdSync();
    final initiatingBackend = ApiConfig.baseUrl;
    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;

    return runZoned(() async {
      await initialize();
      final productsBox = _getProductsBox();
      final pendingBox = _getPendingBox();

      bool isSessionValid() {
        if (!ActiveSessionManager.isSessionReady()) {
          return false;
        }
        return ActiveSessionManager.validateArtisanSession(
          expectedUserId: initiatingUserId,
          expectedGeneration: initiatingSessionGen,
          expectedBackendOrigin: initiatingBackend,
        );
      }

      final id = product.id.isEmpty
          ? 'prod_${DateTime.now().millisecondsSinceEpoch}'
          : product.id;

      final draftProduct = product.copyWith(
        id: id,
        status: ProductStatus.draft,
      );

      final idempotencyKey = 'idem_create_${draftProduct.id}';
      final payloadSnapshot = draftProduct.toBackendJson(artisanId: initiatingUserId);

      if (isOnline && isSessionValid()) {
        try {
          final created = await _apiService.createProduct(
            draftProduct,
            artisanId: initiatingUserId,
            idempotencyKey: idempotencyKey,
          );
          if (isSessionValid()) {
            await productsBox.put(created.id, created);
          } else {
            debugPrint('ProductRepository: Session changed while createProduct in-flight; skipping local cache mutation to prevent cross-account contamination.');
          }
          return created;
        } catch (e) {
          debugPrint('ProductRepository: Online create failed, saving draft to pending queue: $e');
        }
      }

    // Offline mode or API failed: save locally with pendingSync status
    final localDraft = draftProduct.copyWith(
      status: ProductStatus.pendingSync,
    );
    if (isSessionValid()) {
      await productsBox.put(localDraft.id, localDraft);
    } else {
      debugPrint('ProductRepository: Session changed before saving offline draft; skipping local cache mutation to prevent cross-account contamination.');
    }

      final op = OfflineOperation(
        action: OfflineOperation.actionCreate,
        productId: localDraft.id,
        revision: localDraft.revision,
        contentHash: localDraft.contentHash,
        idempotencyKey: idempotencyKey,
        payloadSnapshot: payloadSnapshot,
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(op.id, op.toPendingString());
      return localDraft;
    }, zoneValues: {
      #kalasetuExpectedUserId: initiatingUserId,
      #kalasetuExpectedSessionGen: initiatingSessionGen,
      #kalasetuExpectedBackend: initiatingBackend,
    });
  }

  /// Update product draft - invalidates prior approval server-side.
  Future<Product> updateProduct(
    Product product, {
    bool isOnline = true,
    String? idempotencyKey,
  }) async {
    // Capture initiating session identity BEFORE any async work
    final initiatingUserId = ActiveSessionManager.getCurrentUserIdSync();
    final initiatingBackend = ApiConfig.baseUrl;
    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;

    return runZoned(() async {
      await initialize();
      final productsBox = _getProductsBox();
      final pendingBox = _getPendingBox();

      bool isSessionValid() {
        if (!ActiveSessionManager.isSessionReady()) {
          return false;
        }
        return ActiveSessionManager.validateArtisanSession(
          expectedUserId: initiatingUserId,
          expectedGeneration: initiatingSessionGen,
          expectedBackendOrigin: initiatingBackend,
        );
      }

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

      if (isOnline && isSessionValid()) {
        try {
          final updated = await _apiService.updateProduct(
            product,
            expectedRevision: product.revision,
            idempotencyKey: effectiveIdempotencyKey,
          );
          if (isSessionValid()) {
            await productsBox.put(updated.id, updated);
          } else {
            debugPrint('ProductRepository: Session changed while updateProduct in-flight; skipping local cache mutation to prevent cross-account contamination.');
          }
          return updated;
        } on StaleRevisionException {
          rethrow;
        } catch (e) {
          debugPrint('ProductRepository: Online update failed, saving to pending queue: $e');
        }
      }

    final localProduct = product.copyWith(
      status: product.status,
    );
    if (isSessionValid()) {
      await productsBox.put(localProduct.id, localProduct);
    } else {
      debugPrint('ProductRepository: Session changed before saving offline update; skipping local cache mutation.');
    }

      final op = OfflineOperation(
        action: OfflineOperation.actionUpdate,
        productId: localProduct.id,
        revision: localProduct.revision,
        contentHash: localProduct.contentHash,
        idempotencyKey: effectiveIdempotencyKey,
        dependsOnOpId: upstreamOpId,
        payloadSnapshot: payloadSnapshot,
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(op.id, op.toPendingString());
      return localProduct;
    }, zoneValues: {
      #kalasetuExpectedUserId: initiatingUserId,
      #kalasetuExpectedSessionGen: initiatingSessionGen,
      #kalasetuExpectedBackend: initiatingBackend,
    });
  }

  Future<Product> approveAndPublishProduct(
    String id, {
    int? revision,
    String? contentHash,
    bool isOnline = true,
    String? idempotencyKey,
    String? reviewedChecksum,
  }) async {
    // Capture initiating session identity BEFORE any async work
    final initiatingUserId = ActiveSessionManager.getCurrentUserIdSync();
    final initiatingBackend = ApiConfig.baseUrl;
    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;

    return runZoned(() async {
      await initialize();
      final productsBox = _getProductsBox();
      final pendingBox = _getPendingBox();

      bool isSessionValid() {
        if (!ActiveSessionManager.isSessionReady()) {
          return false;
        }
        return ActiveSessionManager.validateArtisanSession(
          expectedUserId: initiatingUserId,
          expectedGeneration: initiatingSessionGen,
          expectedBackendOrigin: initiatingBackend,
        );
      }

      var product = productsBox.get(id);

      if (product == null) {
        if (isOnline && isSessionValid()) {
          try {
            product = await _apiService.getProduct(id);
            if (isSessionValid()) {
              await productsBox.put(id, product);
            }
          } catch (_) {}
        }
        if (product == null) {
          throw Exception('Product $id not found locally');
        }
      }

      final effectiveRevision = revision ?? product.revision;
      final effectiveHash = contentHash ?? product.contentHash ?? '';
      final effectiveIdempotencyKey = idempotencyKey ?? 'idem_pub_${id}_$effectiveRevision';
      final effectiveReviewedChecksum = reviewedChecksum ?? product.reviewedMediaChecksum;

      if (effectiveReviewedChecksum != null && effectiveReviewedChecksum.isNotEmpty) {
        if (product.displayPhotoPath.isNotEmpty && File(product.displayPhotoPath).existsSync()) {
          final currentBytes = File(product.displayPhotoPath).readAsBytesSync();
          final currentSha256 = sha256.convert(currentBytes).toString();
          if (currentSha256 != effectiveReviewedChecksum) {
            throw StateError(
              'Approval failed: Image on disk was modified or replaced after preview verification '
              '($currentSha256 != $effectiveReviewedChecksum)',
            );
          }
        }
      }

      if (isOnline && isSessionValid()) {
        try {
          // Verify media asset exists remotely; upload if only phone-local
          if ((product.mediaId == null || product.mediaId!.isEmpty) &&
              product.displayPhotoPath.isNotEmpty &&
              File(product.displayPhotoPath).existsSync()) {
            if (!isSessionValid()) {
              throw _SessionChangedInternalException();
            }
            final photoBytes = File(product.displayPhotoPath).readAsBytesSync();
            final photoSha256 = sha256.convert(photoBytes).toString();
            if (effectiveReviewedChecksum != null &&
                effectiveReviewedChecksum.isNotEmpty &&
                photoSha256 != effectiveReviewedChecksum) {
              throw StateError(
                'Approval failed: Image on disk was modified or replaced after preview verification '
                '($photoSha256 != $effectiveReviewedChecksum)',
              );
            }
            final snapshotDir = Directory('${Directory.systemTemp.path}/kalasetu_reviewed_uploads');
            if (!snapshotDir.existsSync()) {
              snapshotDir.createSync(recursive: true);
            }
            final snapshotPath = '${snapshotDir.path}/reviewed_${product.id}_${DateTime.now().microsecondsSinceEpoch}.tmp';
            final snapshotFile = File(snapshotPath)..writeAsBytesSync(photoBytes, flush: true);

            final snapshotSha256 = sha256.convert(snapshotFile.readAsBytesSync()).toString();
            if (snapshotSha256 != photoSha256 ||
                (effectiveReviewedChecksum != null &&
                 effectiveReviewedChecksum.isNotEmpty &&
                 snapshotSha256 != effectiveReviewedChecksum)) {
              try { snapshotFile.deleteSync(); } catch (_) {}
              throw StateError(
                'Approval failed: Snapshot checksum mismatch ($snapshotSha256 != $effectiveReviewedChecksum)',
              );
            }

            final mediaUploadKey = 'idem_upload_${id}_${DateTime.now().millisecondsSinceEpoch}';
            Map<String, dynamic> mediaRes;
            try {
              mediaRes = await _apiService.uploadMediaFile(
                snapshotPath,
                idempotencyKey: mediaUploadKey,
              );
            } finally {
              try { snapshotFile.deleteSync(); } catch (_) {}
            }

            final serverChecksum = mediaRes['sha256_checksum'] as String? ?? mediaRes['sha256Checksum'] as String?;
            final expectedChecksum = effectiveReviewedChecksum ?? photoSha256;
            if (serverChecksum == null || serverChecksum.toLowerCase() != expectedChecksum.toLowerCase()) {
              throw StateError(
                'Approval failed: Server-returned media checksum does not match reviewed checksum '
                '($serverChecksum != $expectedChecksum)',
              );
            }
            final serverMediaId = mediaRes['media_id'] as String?;
            if (serverMediaId == null || serverMediaId.isEmpty) {
              throw StateError('Approval failed: Server did not return a valid media ID');
            }

            product = product.copyWith(mediaId: serverMediaId);

            if (!isSessionValid()) {
              throw _SessionChangedInternalException();
            }

            final attachKey = 'idem_attach_${id}_${product.revision}_${DateTime.now().millisecondsSinceEpoch}';
            final attached = await _apiService.updateProduct(
              product,
              expectedRevision: product.revision,
              idempotencyKey: attachKey,
            );
            if (isSessionValid()) {
              await productsBox.put(attached.id, attached);
            }
            product = attached;
          }

          if (!isSessionValid()) {
            throw _SessionChangedInternalException();
          }

          final pubRevision = product.revision;
          final pubHash = product.contentHash ?? effectiveHash;
          final published = await _apiService.approveAndPublishProduct(
            id,
            revision: pubRevision,
            contentHash: pubHash,
            idempotencyKey: effectiveIdempotencyKey,
          );
          if (isSessionValid()) {
            await productsBox.put(published.id, published);
          } else {
            debugPrint('ProductRepository: Session changed while approveAndPublishProduct in-flight; skipping local cache mutation.');
          }
          return published;
        } on StaleRevisionException {
          rethrow;
        } on StateError {
          rethrow;
        } on _SessionChangedInternalException {
          debugPrint('ProductRepository: Session changed during multi-stage approve and publish; halting online dispatch.');
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
      reviewedMediaChecksum: effectiveReviewedChecksum,
    );
    if (isSessionValid()) {
      await productsBox.put(queuedLocal.id, queuedLocal);
    } else {
      debugPrint('ProductRepository: Session changed before saving offline approval; skipping local cache mutation.');
    }

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
      final photoBytes = File(queuedLocal.displayPhotoPath).readAsBytesSync();
      final photoSha256 = sha256.convert(photoBytes).toString();
      if (effectiveReviewedChecksum != null &&
          effectiveReviewedChecksum.isNotEmpty &&
          photoSha256 != effectiveReviewedChecksum) {
        throw StateError(
          'Approval failed: Image on disk was modified or replaced after preview verification '
          '($photoSha256 != $effectiveReviewedChecksum)',
        );
      }
      final mediaOpId = 'op_media_${queuedLocal.id}_${DateTime.now().millisecondsSinceEpoch}';
      final mediaUploadKey = 'idem_media_${queuedLocal.id}';
      final mediaOp = OfflineOperation(
        id: mediaOpId,
        action: OfflineOperation.actionMediaUpload,
        productId: queuedLocal.id,
        idempotencyKey: mediaUploadKey,
        mediaLocalId: queuedLocal.displayPhotoPath,
        dependsOnOpId: latestUpstreamOpId,
        payloadSnapshot: {
          'media_sha256': effectiveReviewedChecksum ?? photoSha256,
          'expected_revision': effectiveRevision,
          'content_hash': effectiveHash,
        },
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(mediaOp.id, mediaOp.toPendingString());

      final attachOpId = 'op_attach_${queuedLocal.id}_${DateTime.now().millisecondsSinceEpoch}';
      final attachKey = 'idem_attach_${queuedLocal.id}';
      final attachOp = OfflineOperation(
        id: attachOpId,
        action: OfflineOperation.actionAttachMedia,
        productId: queuedLocal.id,
        idempotencyKey: attachKey,
        dependsOnOpId: mediaOpId,
        mediaIdFromOpId: mediaOpId,
        payloadSnapshot: {
          'expected_revision': effectiveRevision,
          'content_hash': effectiveHash,
          'media_sha256': effectiveReviewedChecksum ?? photoSha256,
        },
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(attachOp.id, attachOp.toPendingString());

      final pubOpId = 'op_pub_${queuedLocal.id}_${DateTime.now().millisecondsSinceEpoch}';
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
          'media_sha256': effectiveReviewedChecksum ?? photoSha256,
        },
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(pubOp.id, pubOp.toPendingString());
    } else {
      // Photo already has mediaId or does not exist
      final pubOpId = 'op_pub_${queuedLocal.id}_${DateTime.now().millisecondsSinceEpoch}';
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
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(pubOp.id, pubOp.toPendingString());
    }

    return queuedLocal;
    }, zoneValues: {
      #kalasetuExpectedUserId: initiatingUserId,
      #kalasetuExpectedSessionGen: initiatingSessionGen,
      #kalasetuExpectedBackend: initiatingBackend,
    });
  }

  /// Delete product.
  Future<void> deleteProduct(String id, {bool isOnline = true}) async {
    // Capture initiating session identity BEFORE any async work
    final initiatingUserId = ActiveSessionManager.getCurrentUserIdSync();
    final initiatingBackend = ApiConfig.baseUrl;
    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;

    return runZoned(() async {
      await initialize();
      final productsBox = _getProductsBox();
      final pendingBox = _getPendingBox();

      bool isSessionValid() {
        if (!ActiveSessionManager.isSessionReady()) {
          return false;
        }
        return ActiveSessionManager.validateArtisanSession(
          expectedUserId: initiatingUserId,
          expectedGeneration: initiatingSessionGen,
          expectedBackendOrigin: initiatingBackend,
        );
      }

      final idempotencyKey = 'idem_del_$id';

      if (isOnline && isSessionValid()) {
        try {
          await _apiService.deleteProduct(
            id,
            idempotencyKey: idempotencyKey,
          );
          if (isSessionValid()) {
            await productsBox.delete(id);
            // Clean up any remaining operations for this deleted product
            final toDelete = <String>[];
            for (final entry in pendingBox.toMap().entries) {
              final op = OfflineOperation.fromPendingString(entry.value, entry.key.toString());
              if (op.productId == id && (op.owner == null || op.owner == initiatingUserId)) {
                toDelete.add(entry.key.toString());
              }
            }
            for (final k in toDelete) {
              await pendingBox.delete(k);
            }
          } else {
            debugPrint('ProductRepository: Session changed while deleteProduct in-flight; skipping local cache mutation.');
          }
          return;
        } catch (e) {
          debugPrint('ProductRepository: Online delete failed: $e');
        }
      }

    if (isSessionValid()) {
      await productsBox.delete(id);
    } else {
      debugPrint('ProductRepository: Session changed before deleting offline product; skipping local cache mutation.');
    }

      final op = OfflineOperation(
        action: OfflineOperation.actionDelete,
        productId: id,
        idempotencyKey: idempotencyKey,
        owner: initiatingUserId,
        backend: initiatingBackend,
      );
      await pendingBox.put(op.id, op.toPendingString());
    }, zoneValues: {
      #kalasetuExpectedUserId: initiatingUserId,
      #kalasetuExpectedSessionGen: initiatingSessionGen,
      #kalasetuExpectedBackend: initiatingBackend,
    });
  }

  /// Unpublish a published product, resetting server status to draft and revoking approvals.
  Future<Product> unpublishProduct(String productId, {bool isOnline = true, String? idempotencyKey}) async {
    // Capture initiating session identity BEFORE any async work
    final initiatingUserId = ActiveSessionManager.getCurrentUserIdSync();
    final initiatingBackend = ApiConfig.baseUrl;
    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;

    return runZoned(() async {
      await initialize();
      final productsBox = _getProductsBox();
      final pendingBox = _getPendingBox();
      final effectiveKey = idempotencyKey ?? 'idem_unpub_${productId}_${DateTime.now().millisecondsSinceEpoch}';

      bool isSessionValid() {
        if (!ActiveSessionManager.isSessionReady()) {
          return false;
        }
        return ActiveSessionManager.validateArtisanSession(
          expectedUserId: initiatingUserId,
          expectedGeneration: initiatingSessionGen,
          expectedBackendOrigin: initiatingBackend,
        );
      }

      final local = productsBox.get(productId);
      if (local == null) {
        throw Exception('Product $productId not found in local cache');
      }
      Product activeLocal = local;

      final sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
      bool hasValidContentHash = activeLocal.contentHash != null &&
          sha256Pattern.hasMatch(activeLocal.contentHash!.toLowerCase());

      // If online and missing valid revision or content hash, fetch authoritative product
      if (isOnline && isSessionValid() && (!hasValidContentHash || activeLocal.revision <= 0)) {
        try {
          final authoritative = await _apiService.getProduct(productId);
          if (isSessionValid()) {
            await productsBox.put(productId, authoritative);
            activeLocal = authoritative;
            hasValidContentHash = activeLocal.contentHash != null &&
                sha256Pattern.hasMatch(activeLocal.contentHash!.toLowerCase());
          }
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

      if (isOnline && isSessionValid() && !hasPendingDependencies && hasValidContentHash) {
        try {
          final serverProduct = await _apiService.unpublishProduct(
            productId,
            expectedRevision: activeLocal.revision,
            contentHash: activeLocal.contentHash!.toLowerCase(),
            idempotencyKey: effectiveKey,
          );
          if (!isSessionValid()) {
            throw _SessionChangedInternalException();
          }
          await productsBox.put(serverProduct.id, serverProduct);
          return serverProduct;
        } on StaleRevisionException catch (e) {
          debugPrint('ProductRepository: Stale revision on unpublish: $e');
          if (isSessionValid()) {
            try {
              final authoritative = await _apiService.getProduct(productId);
              if (isSessionValid()) {
                await productsBox.put(productId, authoritative);
              }
            } catch (fetchErr) {
              debugPrint(
                  'ProductRepository: Failed to refresh stale product on unpublish: $fetchErr');
              if (isSessionValid()) {
                await productsBox.put(
                    productId,
                    activeLocal.copyWith(status: ProductStatus.pendingUnpublishSync));
              }
            }
          }
          rethrow;
        } on _SessionChangedInternalException {
          debugPrint('ProductRepository: Session changed during unpublish; preserving offline operation under original identity.');
        } catch (e) {
          debugPrint('ProductRepository: Online unpublish failed, queuing offline: $e');
        }
      }

      // 4. Offline, session invalid, or has pending dependencies:
      // Invariant: Do NOT set local product to draft, do NOT increment authoritative revision,
      // and do NOT clear last-confirmed approval/publication metadata.
      final pendingUnpubLocal = activeLocal.copyWith(
        status: ProductStatus.pendingUnpublishSync,
      );
      if (isSessionValid()) {
        await productsBox.put(productId, pendingUnpubLocal);
      }

      final op = OfflineOperation(
        action: OfflineOperation.actionUnpublish,
        productId: productId,
        revision: activeLocal.revision,
        contentHash: activeLocal.contentHash,
        idempotencyKey: effectiveKey,
        dependsOnOpId: unpublishDepOp?.id,
        owner: initiatingUserId,
        backend: initiatingBackend,
        payloadSnapshot: {
          'expected_revision': activeLocal.revision,
          'content_hash': activeLocal.contentHash,
        },
      );
      await pendingBox.put(op.id, op.toPendingString());
      return pendingUnpubLocal;
    }, zoneValues: {
      #kalasetuExpectedUserId: initiatingUserId,
      #kalasetuExpectedSessionGen: initiatingSessionGen,
      #kalasetuExpectedBackend: initiatingBackend,
    });
  }

  /// Drain pending offline queue with dependency ordering:
  /// drafts -> media validation -> attach media -> approve and publish.
  /// Preserves idempotency keys across retries, stores upstream results in resultData,
  /// and ensures completed operations are retained while dependents remain.
  Future<int> syncPendingQueue() async {
    await initialize();
    final productsBox = _getProductsBox();
    final pendingBox = _getPendingBox();

    // Reclaim any expired in-flight leases before draining
    await reclaimExpiredLeases();

    // Invariant: Require an initialized, authenticated artisan session, not merely "not simulation".
    if (!ActiveSessionManager.isSessionReady()) {
      debugPrint('[ProductRepository] Skipping queue sync: session storage not ready.');
      return 0;
    }
    if (ActiveSessionManager.getActiveSessionModeSync() != ActiveSessionMode.artisan) {
      debugPrint('[ProductRepository] Skipping queue sync: active session is not in authenticated artisan mode.');
      return 0;
    }

    final initiatingUserId = ActiveSessionManager.getCurrentUserIdSync();
    if (initiatingUserId == null || initiatingUserId.isEmpty) {
      debugPrint('[ProductRepository] Skipping queue sync: authenticated artisan userId missing.');
      return 0;
    }

    final initiatingSessionGen = ActiveSessionManager.sessionGeneration;
    final initiatingBackend = ApiConfig.baseUrl;

    bool isSessionValid() {
      return ActiveSessionManager.validateArtisanSession(
        expectedUserId: initiatingUserId,
        expectedGeneration: initiatingSessionGen,
        expectedBackendOrigin: initiatingBackend,
      );
    }

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
        // Invariant: Revalidate identity before each operation
        if (!isSessionValid()) {
          debugPrint('[ProductRepository] Session changed during queue drain; halting sync safely.');
          return totalSynced;
        }

        // Invariant: Missing owner is not authorization.
        // If owner provenance cannot be established, mark statusUserActionRequired.
        if (op.owner == null || op.owner!.isEmpty) {
          debugPrint('[ProductRepository] Operation ${op.id} lacks owner provenance; transitioning to user_action_required.');
          final quarantinedOp = op.copyWith(
            status: OfflineOperation.statusUserActionRequired,
            clearLeaseExpiresAt: true,
            errorMessage: 'Legacy operation lacks verifiable owner provenance; manual review required.',
          );
          await pendingBox.put(op.id, quarantinedOp.toPendingString());
          allOps[op.id] = quarantinedOp;
          continue;
        }

        // Invariant: Do not execute artisan A's queued work using artisan B's token.
        if (op.owner != initiatingUserId) {
          debugPrint('[ProductRepository] Skipping operation ${op.id}: owned by artisan "${op.owner}", current session is "$initiatingUserId".');
          continue;
        }

        // Invariant: Backend affinity.
        // If backend provenance is missing, mark statusUserActionRequired.
        if (op.backend == null || op.backend!.isEmpty) {
          debugPrint('[ProductRepository] Operation ${op.id} lacks backend origin; transitioning to user_action_required.');
          final quarantinedOp = op.copyWith(
            status: OfflineOperation.statusUserActionRequired,
            clearLeaseExpiresAt: true,
            errorMessage: 'Legacy operation lacks verifiable backend origin provenance; manual review required.',
          );
          await pendingBox.put(op.id, quarantinedOp.toPendingString());
          allOps[op.id] = quarantinedOp;
          continue;
        }

        final opBackendNorm = PrivateMediaCache.normalizeBackendOrigin(op.backend!);
        final currentBackendNorm = PrivateMediaCache.normalizeBackendOrigin(initiatingBackend);
        if (opBackendNorm != currentBackendNorm) {
          debugPrint('[ProductRepository] Skipping operation ${op.id}: targeted to backend "$opBackendNorm", current backend is "$currentBackendNorm".');
          continue;
        }

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

        // Upstream dependencies are satisfied! Execute this operation with bound identity context:
        bool shouldHaltDrain = false;
        await runZoned(
          () async {
            try {
              if (op.action == OfflineOperation.actionCreate) {
                Product? product;
                if (op.payloadSnapshot != null) {
                  product = Product.fromJson(op.payloadSnapshot!);
                } else {
                  product = productsBox.get(op.productId);
                }
                if (product != null) {
                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed after async preparation for CREATE ${op.id}; reverting lease and halting.');
                    final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, revertedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

                  final created = await _apiService.createProduct(
                    product.copyWith(status: ProductStatus.draft),
                    idempotencyKey: op.idempotencyKey,
                  );

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed between server success and local response application for CREATE ${op.id}; preserving operation and halting.');
                    final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, preservedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

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
                if (filePath == null || !File(filePath).existsSync()) {
                  debugPrint('[ProductRepository] Media upload failed closed: file "$filePath" does not exist.');
                  final failedOp = op.copyWith(
                    status: OfflineOperation.statusFailed,
                    clearLeaseExpiresAt: true,
                    errorMessage: 'Media file missing on device: $filePath',
                  );
                  await pendingBox.put(op.id, failedOp.toPendingString());
                  allOps[op.id] = failedOp;
                  return;
                }

                final fileBytes = await File(filePath).readAsBytes();
                final actualSha256 = sha256.convert(fileBytes).toString();
                final expectedSha256 = op.payloadSnapshot?['media_sha256'] as String?;
                if (expectedSha256 != null && expectedSha256.isNotEmpty && actualSha256 != expectedSha256) {
                  debugPrint('[ProductRepository] Media upload failed closed: SHA-256 mismatch (actual $actualSha256 != expected $expectedSha256).');
                  final failedOp = op.copyWith(
                    status: OfflineOperation.statusFailed,
                    clearLeaseExpiresAt: true,
                    errorMessage: 'Media file mutated on device (SHA-256 mismatch)',
                  );
                  await pendingBox.put(op.id, failedOp.toPendingString());
                  allOps[op.id] = failedOp;
                  return;
                }

                final snapshotDir = Directory('${Directory.systemTemp.path}/kalasetu_sync_uploads');
                if (!snapshotDir.existsSync()) {
                  snapshotDir.createSync(recursive: true);
                }
                final snapshotPath = '${snapshotDir.path}/sync_upload_${op.id}_${DateTime.now().microsecondsSinceEpoch}.tmp';
                final snapshotFile = File(snapshotPath)..writeAsBytesSync(fileBytes, flush: true);

                if (!isSessionValid()) {
                  try { snapshotFile.deleteSync(); } catch (_) {}
                  debugPrint('[ProductRepository] Session changed after async preparation for MEDIA_UPLOAD ${op.id}; reverting lease and halting.');
                  final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, revertedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

                Map<String, dynamic> mediaRes;
                try {
                  mediaRes = await _apiService.uploadMediaFile(
                    snapshotPath,
                    idempotencyKey: op.idempotencyKey,
                  );
                } finally {
                  try { snapshotFile.deleteSync(); } catch (_) {}
                }

                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed between server success and local response application for MEDIA_UPLOAD ${op.id}; preserving operation and halting.');
                  final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, preservedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

                final serverChecksum = mediaRes['sha256_checksum'] as String? ?? mediaRes['sha256Checksum'] as String?;
                if (expectedSha256 != null && expectedSha256.isNotEmpty) {
                  if (serverChecksum == null || serverChecksum.toLowerCase() != expectedSha256.toLowerCase()) {
                    debugPrint('[ProductRepository] Server media checksum mismatch during sync: server ($serverChecksum) != expected ($expectedSha256)');
                    final failedOp = op.copyWith(
                      status: OfflineOperation.statusFailed,
                      clearLeaseExpiresAt: true,
                      errorMessage: 'Server-returned media checksum mismatch: $serverChecksum != $expectedSha256',
                    );
                    await pendingBox.put(op.id, failedOp.toPendingString());
                    allOps[op.id] = failedOp;
                    return;
                  }
                }

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
              } else if (op.action == OfflineOperation.actionAttachMedia) {
                // Resolve mediaId from parent media op if needed
                String? resolvedMediaId = op.mediaId;
                if ((resolvedMediaId == null || resolvedMediaId.isEmpty) && op.mediaIdFromOpId != null) {
                  final parentMediaOp = allOps[op.mediaIdFromOpId];
                  resolvedMediaId = parentMediaOp?.resultData?['media_id'] as String? ?? parentMediaOp?.mediaId;
                }

                var product = productsBox.get(op.productId);
                if (product != null && resolvedMediaId != null && resolvedMediaId.isNotEmpty) {
                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed after async preparation for ATTACH_MEDIA ${op.id}; reverting lease and halting.');
                    final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, revertedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

                  final attachedProduct = product.copyWith(mediaId: resolvedMediaId);
                  final updated = await _apiService.updateProduct(
                    attachedProduct,
                    expectedRevision: product.revision,
                    idempotencyKey: op.idempotencyKey,
                  );

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed between server success and local response application for ATTACH_MEDIA ${op.id}; preserving operation and halting.');
                    final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, preservedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

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

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed after async preparation for UPDATE ${op.id}; reverting lease and halting.');
                    final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, revertedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

                  final updated = await _apiService.updateProduct(
                    product,
                    expectedRevision: effectiveExpectedRevision,
                    idempotencyKey: op.idempotencyKey,
                  );

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed between server success and local response application for UPDATE ${op.id}; preserving operation and halting.');
                    final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, preservedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

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

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed after async preparation for APPROVE_PUBLISH ${op.id}; reverting lease and halting.');
                    final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, revertedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

                  final published = await _apiService.approveAndPublishProduct(
                    op.productId,
                    revision: pubRevision,
                    contentHash: pubHash,
                    idempotencyKey: op.idempotencyKey,
                  );

                  if (!isSessionValid()) {
                    debugPrint('[ProductRepository] Session changed between server success and local response application for APPROVE_PUBLISH ${op.id}; preserving operation and halting.');
                    final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                    await pendingBox.put(op.id, preservedOp.toPendingString());
                    shouldHaltDrain = true;
                    return;
                  }

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
                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed after async preparation for DELETE ${op.id}; reverting lease and halting.');
                  final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, revertedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

                await _apiService.deleteProduct(
                  op.productId,
                  idempotencyKey: op.idempotencyKey,
                );

                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed between server success and local response application for DELETE ${op.id}; preserving operation and halting.');
                  final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, preservedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

                final updatedOp = op.copyWith(
                  status: OfflineOperation.statusCompleted,
                  clearLeaseExpiresAt: true,
                );
                await pendingBox.put(op.id, updatedOp.toPendingString());
                allOps[op.id] = updatedOp;
                totalSynced++;
                progressMade = true;
              } else if (op.action == OfflineOperation.actionUnpublish) {
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
                  return;
                }

                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed after async preparation for UNPUBLISH ${op.id}; reverting lease and halting.');
                  final revertedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, revertedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

                final unpublished = await _apiService.unpublishProduct(
                  op.productId,
                  expectedRevision: expectedRevision,
                  contentHash: contentHash.toLowerCase(),
                  idempotencyKey: op.idempotencyKey,
                );

                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed between server success and local response application for UNPUBLISH ${op.id}; preserving operation and halting.');
                  final preservedOp = op.copyWith(status: OfflineOperation.statusPending, clearLeaseExpiresAt: true);
                  await pendingBox.put(op.id, preservedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }

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
              if (!isSessionValid()) {
                debugPrint('[ProductRepository] Session changed before stale refresh for ${op.id}; reverting lease without incrementing retryCount and halting.');
                final revertedOp = op.copyWith(
                  status: OfflineOperation.statusPending,
                  clearLeaseExpiresAt: true,
                );
                await pendingBox.put(op.id, revertedOp.toPendingString());
                shouldHaltDrain = true;
                return;
              }

              try {
                final refreshedProduct = await _apiService.getProduct(op.productId);
                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed after stale getProduct for ${op.id}; reverting lease without incrementing retryCount and halting.');
                  final revertedOp = op.copyWith(
                    status: OfflineOperation.statusPending,
                    clearLeaseExpiresAt: true,
                  );
                  await pendingBox.put(op.id, revertedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }
                await productsBox.put(op.productId, refreshedProduct);
              } catch (fetchErr) {
                debugPrint('ProductRepository: Failed to refresh stale product ${op.productId}: $fetchErr');
                if (!isSessionValid()) {
                  debugPrint('[ProductRepository] Session changed before fallback cache write for ${op.id}; reverting lease without incrementing retryCount and halting.');
                  final revertedOp = op.copyWith(
                    status: OfflineOperation.statusPending,
                    clearLeaseExpiresAt: true,
                  );
                  await pendingBox.put(op.id, revertedOp.toPendingString());
                  shouldHaltDrain = true;
                  return;
                }
                final existing = productsBox.get(op.productId);
                if (existing != null) {
                  final fallbackStatus = op.action == OfflineOperation.actionUnpublish
                      ? ProductStatus.pendingUnpublishSync
                      : ProductStatus.awaitingApproval;
                  await productsBox.put(op.productId, existing.copyWith(status: fallbackStatus));
                }
              }

              if (!isSessionValid()) {
                debugPrint('[ProductRepository] Session changed before marking user_action_required for ${op.id}; reverting lease without incrementing retryCount and halting.');
                final revertedOp = op.copyWith(
                  status: OfflineOperation.statusPending,
                  clearLeaseExpiresAt: true,
                );
                await pendingBox.put(op.id, revertedOp.toPendingString());
                shouldHaltDrain = true;
                return;
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
              if (!isSessionValid() || e is SessionExpiredException || (e is DioException && e.error is SessionExpiredException)) {
                debugPrint('[ProductRepository] Session invalidated during op ${op.id}; reverting lease without incrementing retryCount and halting.');
                final revertedOp = op.copyWith(
                  status: OfflineOperation.statusPending,
                  clearLeaseExpiresAt: true,
                );
                await pendingBox.put(op.id, revertedOp.toPendingString());
                shouldHaltDrain = true;
                return;
              }
              final updatedOp = op.copyWith(
                status: OfflineOperation.statusPending,
                clearLeaseExpiresAt: true,
                retryCount: op.retryCount + 1,
                errorMessage: e.toString(),
              );
              await pendingBox.put(op.id, updatedOp.toPendingString());
              allOps[op.id] = updatedOp;
              if (!isSessionValid()) {
                debugPrint('[ProductRepository] Session changed during op ${op.id} error; halting queue drain.');
                shouldHaltDrain = true;
                return;
              }
            }
          },
          zoneValues: {
            #kalasetuExpectedUserId: op.owner,
            #kalasetuExpectedSessionGen: initiatingSessionGen,
            #kalasetuExpectedBackend: op.backend ?? initiatingBackend,
          },
        );

        if (shouldHaltDrain) {
          return totalSynced;
        }
      }
    }

    // Purge policy:
    // "Do not purge completed operations/results while dependent operations remain."
    // An operation can only be safely purged if NO OTHER non-completed operation in pendingBox depends on it!
    if (!isSessionValid()) {
      debugPrint('[ProductRepository] Session changed before purge policy; halting sync.');
      return totalSynced;
    }

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
      if (op.status == OfflineOperation.statusCompleted &&
          !dependentIds.contains(op.id) &&
          (op.owner == null || op.owner == initiatingUserId)) {
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
