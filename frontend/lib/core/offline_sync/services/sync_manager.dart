import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/queue_item.dart';
import 'connectivity_service.dart';
import 'upload_api.dart';

/// The engine. Owns the queue's lifecycle end to end:
/// enqueue -> upload -> poll -> complete/fail -> retry.
///
/// Nothing in here knows about widgets, screens, or navigation — it only
/// talks to Isar, the connectivity service, and the upload API.
class SyncManager {
  SyncManager({
    required this.isar,
    required this.uploadApi,
    required this.connectivityService,
  });

  final Isar isar;
  final UploadApi uploadApi;
  final ConnectivityService connectivityService;

  StreamSubscription<bool>? _connectivitySub;
  Timer? _processingPollTimer;
  bool _isSyncing = false;

  static const _uuid = Uuid();

  void startListening() {
    _connectivitySub = connectivityService.onConnectivityChanged.listen((isOnline) {
      if (isOnline) unawaited(triggerSyncIfOnline());
    });
    // Catch anything that was queued while the app was fully closed.
    unawaited(triggerSyncIfOnline());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _processingPollTimer?.cancel();
  }

  /// Copies [file] into app-private storage and writes a PENDING queue
  /// record. Returns almost instantly — never waits on the network.
  Future<String> enqueue({
    required File file,
    required QueueItemType type,
    required String productDraftId,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory('${appDir.path}/offline_sync_queue');
    if (!await queueDir.exists()) {
      await queueDir.create(recursive: true);
    }

    final localId = _uuid.v4();
    final ext = file.path.contains('.') ? file.path.split('.').last : 'dat';
    final localPath = '${queueDir.path}/$localId.$ext';
    await file.copy(localPath);

    final item = QueueItem()
      ..localId = localId
      ..type = type
      ..localFilePath = localPath
      ..productDraftId = productDraftId
      ..status = QueueStatus.pending
      ..createdAt = DateTime.now();

    await isar.writeTxn(() => isar.queueItems.put(item));

    unawaited(triggerSyncIfOnline());
    return localId;
  }

  /// Safe to call as often as you like — no-ops if a sync is already
  /// running or if there's no real internet.
  Future<void> triggerSyncIfOnline() async {
    if (_isSyncing) return;
    if (!await connectivityService.hasRealInternet()) return;

    _isSyncing = true;
    try {
      await _uploadPendingItems();
      await _pollProcessingItems();
      await _scheduleNextPollIfNeeded();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _uploadPendingItems() async {
    final items = await isar.queueItems
        .filter()
        .statusEqualTo(QueueStatus.pending)
        .or()
        .statusEqualTo(QueueStatus.failed)
        .sortByCreatedAt()
        .findAll();

    for (final item in items) {
      if (item.status == QueueStatus.failed && !item.isRetryable) continue;

      if (!File(item.localFilePath).existsSync()) {
        item.status = QueueStatus.failed;
        item.errorMessage = 'Local file no longer exists on device';
        await isar.writeTxn(() => isar.queueItems.put(item));
        continue;
      }

      await _uploadSingleItem(item);

      // Connection may have dropped mid-batch — recheck before continuing
      // rather than burning through retries against a dead network.
      if (!await connectivityService.hasRealInternet()) break;
    }
  }

  Future<void> _uploadSingleItem(QueueItem item) async {
    item.status = QueueStatus.uploading;
    item.lastAttemptAt = DateTime.now();
    await isar.writeTxn(() => isar.queueItems.put(item));

    try {
      final file = File(item.localFilePath);
      final result = item.type == QueueItemType.imageEnhance
          ? await uploadApi.uploadImage(
              file: file, idempotencyKey: item.localId, productDraftId: item.productDraftId)
          : await uploadApi.uploadVoiceNote(
              file: file, idempotencyKey: item.localId, productDraftId: item.productDraftId);

      item.jobId = result.jobId;
      item.errorMessage = null;

      if (result.immediatelyCompleted) {
        item.status = QueueStatus.completed;
        item.resultJson = jsonEncode(result.resultPayload ?? {});
      } else {
        item.status = QueueStatus.processing;
      }
    } catch (e) {
      item.retryCount += 1;
      item.status = QueueStatus.failed;
      item.errorMessage = e.toString();

      if (item.isRetryable) {
        final delay = Duration(seconds: min(pow(2, item.retryCount).toInt(), 60));
        Timer(delay, () => unawaited(triggerSyncIfOnline()));
      }
    }

    await isar.writeTxn(() => isar.queueItems.put(item));
  }

  Future<void> _pollProcessingItems() async {
    final items = await isar.queueItems.filter().statusEqualTo(QueueStatus.processing).findAll();

    for (final item in items) {
      if (item.jobId == null) continue;

      try {
        final status = await uploadApi.checkStatus(item.jobId!);
        if (status.isComplete) {
          item.status = QueueStatus.completed;
          item.resultJson = jsonEncode(status.resultPayload ?? {});
        } else if (status.isFailed) {
          item.retryCount += 1;
          item.status = QueueStatus.failed;
          item.errorMessage = status.errorMessage ?? 'Processing failed on the server';
        }
        // else still processing — leave as-is, we'll poll again shortly.
      } catch (_) {
        // Transient poll failure. Leave status untouched; next pass retries.
      }

      await isar.writeTxn(() => isar.queueItems.put(item));
    }
  }

  /// While any item is still PROCESSING, keep checking on it every few
  /// seconds so the UI updates without the user needing to reopen the app.
  Future<void> _scheduleNextPollIfNeeded() async {
    _processingPollTimer?.cancel();
    final stillProcessing =
        await isar.queueItems.filter().statusEqualTo(QueueStatus.processing).count();
    if (stillProcessing > 0) {
      _processingPollTimer = Timer(const Duration(seconds: 8), () {
        unawaited(triggerSyncIfOnline());
      });
    }
  }

  Future<void> retryItem(String localId) async {
    final item = await isar.queueItems.filter().localIdEqualTo(localId).findFirst();
    if (item == null) return;

    item.status = QueueStatus.pending;
    item.retryCount = 0;
    item.errorMessage = null;
    await isar.writeTxn(() => isar.queueItems.put(item));

    unawaited(triggerSyncIfOnline());
  }

  Future<void> retryAll() async {
    final items = await isar.queueItems.filter().statusEqualTo(QueueStatus.failed).findAll();
    for (final item in items) {
      item.status = QueueStatus.pending;
      item.retryCount = 0;
      item.errorMessage = null;
    }
    await isar.writeTxn(() => isar.queueItems.putAll(items));

    unawaited(triggerSyncIfOnline());
  }
}
