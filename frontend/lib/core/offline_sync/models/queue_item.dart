import 'package:isar/isar.dart';

part 'queue_item.g.dart';

/// The two kinds of captures that can be queued for offline sync.
enum QueueItemType {
  imageEnhance,
  voiceCatalog,
}

/// Lifecycle of a single queued item.
///
///   pending -> uploading -> processing -> completed
///                    \-> failed (auto-retried with backoff until
///                                 maxRetries, then needs a manual retry)
enum QueueStatus {
  pending,
  uploading,
  processing,
  completed,
  failed,
}

@collection
class QueueItem {
  Id id = Isar.autoIncrement;

  /// Client-generated UUID. Doubles as the idempotency key sent to the
  /// backend so retries can never create a duplicate listing.
  @Index(unique: true, replace: true)
  late String localId;

  @enumerated
  late QueueItemType type;

  /// Path to the *copy* of the file living in app-private storage.
  /// We always copy on enqueue so the original (e.g. a camera temp file)
  /// can be deleted/overwritten without breaking the queue.
  late String localFilePath;

  @Index()
  late String productDraftId;

  @Index()
  @enumerated
  QueueStatus status = QueueStatus.pending;

  int retryCount = 0;

  static const int maxRetries = 5;

  late DateTime createdAt;
  DateTime? lastAttemptAt;

  /// Backend job id, set once the upload itself succeeds and the backend
  /// has accepted the item for async AI processing.
  String? jobId;

  String? errorMessage;

  /// Raw JSON of the backend's final result (enhanced image URL,
  /// generated listing copy, suggested price, etc). Parse this on the
  /// frontend once status == completed.
  String? resultJson;

  @ignore
  bool get isRetryable => status == QueueStatus.failed && retryCount < maxRetries;
}
