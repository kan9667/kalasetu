import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'database/database.dart';
import 'models/queue_item.dart';
import 'services/connectivity_service.dart';
import 'services/sync_manager.dart';
import 'services/upload_api.dart';

/// The ONLY class the rest of the app should ever import from this module.
///
/// Usage:
/// ```dart
/// await OfflineSyncService.instance.init(
///   uploadApi: RealUploadApi(baseUrl: 'https://api.kaarigarconnect.in'),
///   healthCheckUrl: 'https://api.kaarigarconnect.in/health',
/// );
/// ```
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  late OfflineSyncDatabase _db;
  late SyncManager _syncManager;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Visible for testing to access database directly if needed
  OfflineSyncDatabase get db {
    _assertInitialized();
    return _db;
  }

  /// Call once, before `runApp()`. Safe to call again — no-ops after the
  /// first successful call.
  Future<void> init({
    required UploadApi uploadApi,
    String? healthCheckUrl = 'https://your-backend.example.com/health',
    OfflineSyncDatabase? db,
  }) async {
    if (_initialized) return;

    _db = db ?? OfflineSyncDatabase();

    final connectivityService = ConnectivityService(healthCheckUrl: healthCheckUrl);
    _syncManager = SyncManager(
      db: _db,
      uploadApi: uploadApi,
      connectivityService: connectivityService,
    );
    _syncManager.startListening();

    _initialized = true;
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _syncManager.dispose();
    await _db.close();
    _initialized = false;
  }

  /// Instantly saves the image locally and queues it for AI enhancement.
  /// Returns a localId you can pass to [watchItem] to track progress.
  Future<String> enqueueImage({
    required File imageFile,
    required String productDraftId,
  }) {
    _assertInitialized();
    return _syncManager.enqueue(
      file: imageFile,
      type: QueueItemType.imageEnhance,
      productDraftId: productDraftId,
    );
  }

  /// Instantly saves the voice note locally and queues it for
  /// transcription + cataloging.
  Future<String> enqueueVoiceNote({
    required File audioFile,
    required String productDraftId,
  }) {
    _assertInitialized();
    return _syncManager.enqueue(
      file: audioFile,
      type: QueueItemType.voiceCatalog,
      productDraftId: productDraftId,
    );
  }

  /// Live stream of the entire queue — drive a "3 items syncing" banner
  /// off this directly, no manual refresh needed.
  Stream<List<QueueItem>> watchQueue() {
    _assertInitialized();
    return _db.watchQueue();
  }

  /// Live stream of a single item — drive a per-product status icon
  /// (clock / spinner / sparkle / check / retry) off this.
  Stream<QueueItem?> watchItem(String localId) {
    _assertInitialized();
    return _db.watchItem(localId);
  }

  Future<void> retryItem(String localId) {
    _assertInitialized();
    return _syncManager.retryItem(localId);
  }

  Future<void> retryAll() {
    _assertInitialized();
    return _syncManager.retryAll();
  }

  /// Manual "sync now" hook, e.g. for a pull-to-refresh gesture.
  Future<void> triggerSyncNow() {
    _assertInitialized();
    return _syncManager.triggerSyncIfOnline();
  }

  Future<int> pendingCount() {
    _assertInitialized();
    return _db.countPendingOrProcessing();
  }

  Future<List<QueueItem>> getAllQueueItems() async {
    _assertInitialized();
    return _db.getAllQueueItems();
  }

  Future<Map<String, dynamic>> getLocalMediaLocations() async {
    final docDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory('${docDir.path}/offline_sync_queue');
    final recordingsDir = Directory('${docDir.path}/offline_sync_recordings');

    final queueFiles = queueDir.existsSync()
        ? queueDir.listSync().whereType<File>().map((f) => f.path).toList()
        : <String>[];
    final recordingFiles = recordingsDir.existsSync()
        ? recordingsDir.listSync().whereType<File>().map((f) => f.path).toList()
        : <String>[];

    return {
      'queue_files': queueFiles,
      'recording_files': recordingFiles,
      'app_doc_directory': docDir.path,
    };
  }

  Future<void> dumpQueueToConsole() async {
    final items = await getAllQueueItems();
    for (final item in items) {
      debugPrint(
        'QueueItem: localId=${item.localId}, type=${item.type.name}, status=${item.status.name}, draft=${item.productDraftId}, jobId=${item.jobId}, result=${item.resultJson}',
      );
    }

    final media = await getLocalMediaLocations();
    debugPrint('Local media directories: ${media['app_doc_directory']}');
    debugPrint('Queued files: ${media['queue_files']}');
    debugPrint('Recording files: ${media['recording_files']}');
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'OfflineSyncService.init() must be called before use — call it once in main.dart.',
      );
    }
  }
}
