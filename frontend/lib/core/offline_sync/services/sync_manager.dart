import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import 'connectivity_service.dart';
import 'upload_api.dart';

/// The engine. Owns the queue's lifecycle end to end:
/// enqueue -> upload -> poll -> complete/fail -> retry.
///
/// Nothing in here knows about widgets, screens, or navigation — it only
/// talks to the Drift database, the connectivity service, and the upload API.
class SyncManager {
  SyncManager({
    required this.db,
    required this.uploadApi,
    required this.connectivityService,
  });

  final OfflineSyncDatabase db;
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
    unawaited(_scheduleNextPollIfNeeded());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _processingPollTimer?.cancel();
    _processingPollTimer = null;
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

    await db.insertQueueItem(
      QueueItemsCompanion(
        localId: Value(localId),
        type: Value(type),
        localFilePath: Value(localPath),
        productDraftId: Value(productDraftId),
        status: const Value(QueueStatus.pending),
        createdAt: Value(DateTime.now()),
      ),
    );

    unawaited(triggerSyncIfOnline());
    return localId;
  }

  /// Safe to call as often as you like — no-ops if a sync is already
  /// running or if there's no real internet.
  Future<void> triggerSyncIfOnline() async {
    if (_isSyncing) return;
    if (!await connectivityService.hasRealInternet()) {
      await _scheduleNextPollIfNeeded();
      return;
    }

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
    final items = await db.getPendingAndFailedItems();

    for (final item in items) {
      if (item.status == QueueStatus.failed && !item.isRetryable) continue;

      if (!File(item.localFilePath).existsSync()) {
        await db.updateQueueItem(
          item.copyWith(
            status: QueueStatus.failed,
            errorMessage: const Value('Local file no longer exists on device'),
          ),
        );
        continue;
      }

      await _uploadSingleItem(item);

      // Connection may have dropped mid-batch — recheck before continuing
      // rather than burning through retries against a dead network.
      if (!await connectivityService.hasRealInternet()) break;
    }
  }

  Future<void> _uploadSingleItem(QueueItem item) async {
    var currentItem = item.copyWith(
      status: QueueStatus.uploading,
      lastAttemptAt: Value(DateTime.now()),
    );
    await db.updateQueueItem(currentItem);

    try {
      final file = File(currentItem.localFilePath);
      final result = currentItem.type == QueueItemType.imageEnhance
          ? await uploadApi.uploadImage(
              file: file,
              idempotencyKey: currentItem.localId,
              productDraftId: currentItem.productDraftId,
            )
          : await uploadApi.uploadVoiceNote(
              file: file,
              idempotencyKey: currentItem.localId,
              productDraftId: currentItem.productDraftId,
            );

      if (result.immediatelyCompleted) {
        currentItem = currentItem.copyWith(
          status: QueueStatus.completed,
          jobId: Value(result.jobId),
          errorMessage: const Value(null),
          resultJson: Value(jsonEncode(result.resultPayload ?? {})),
        );
      } else {
        currentItem = currentItem.copyWith(
          status: QueueStatus.processing,
          jobId: Value(result.jobId),
          errorMessage: const Value(null),
        );
      }
    } catch (e) {
      final newRetryCount = currentItem.retryCount + 1;
      currentItem = currentItem.copyWith(
        retryCount: newRetryCount,
        status: QueueStatus.failed,
        errorMessage: Value(e.toString()),
      );

      if (currentItem.isRetryable) {
        final delay = Duration(seconds: min(pow(2, currentItem.retryCount).toInt(), 60));
        Timer(delay, () => unawaited(triggerSyncIfOnline()));
      }
    }

    await db.updateQueueItem(currentItem);
  }

  Future<void> _pollProcessingItems() async {
    final items = await db.getProcessingItems();

    for (final item in items) {
      if (item.jobId == null) continue;

      try {
        final status = await uploadApi.checkStatus(item.jobId!);
        if (status.isComplete) {
          await db.updateQueueItem(
            item.copyWith(
              status: QueueStatus.completed,
              resultJson: Value(jsonEncode(status.resultPayload ?? {})),
            ),
          );
        } else if (status.isFailed) {
          await db.updateQueueItem(
            item.copyWith(
              retryCount: item.retryCount + 1,
              status: QueueStatus.failed,
              errorMessage: Value(status.errorMessage ?? 'Processing failed on the server'),
            ),
          );
        }
        // else still processing — leave as-is, we'll poll again shortly.
      } catch (_) {
        // Transient poll failure. Leave status untouched; next pass retries.
      }
    }
  }

  /// While any item is still PROCESSING or PENDING, keep checking every few
  /// seconds so the UI updates without the user needing to reopen the app.
  Future<void> _scheduleNextPollIfNeeded() async {
    _processingPollTimer?.cancel();
    final stillProcessing = await db.countProcessing();
    final pendingCount = await db.countPendingOrProcessing();
    if (stillProcessing > 0 || pendingCount > 0) {
      _processingPollTimer = Timer(const Duration(seconds: 5), () {
        unawaited(triggerSyncIfOnline());
      });
    }
  }

  Future<void> retryItem(String localId) async {
    await db.retryItem(localId);
    unawaited(triggerSyncIfOnline());
  }

  Future<void> retryAll() async {
    await db.retryAllFailed();
    unawaited(triggerSyncIfOnline());
  }
}
