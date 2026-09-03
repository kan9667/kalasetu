export '../database/database.dart';

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

const int kMaxQueueItemRetries = 5;
