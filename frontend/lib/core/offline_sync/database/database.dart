import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/queue_item.dart';

export '../models/queue_item.dart';

part 'database.g.dart';

@DataClassName('QueueItem')
class QueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localId => text().unique()();
  IntColumn get type => intEnum<QueueItemType>()();
  TextColumn get localFilePath => text()();
  TextColumn get productDraftId => text()();
  IntColumn get status =>
      intEnum<QueueStatus>().withDefault(Constant(QueueStatus.pending.index))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get jobId => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get resultJson => text().nullable()();
}

extension QueueItemExtensions on QueueItem {
  static const int maxRetries = kMaxQueueItemRetries;
  bool get isRetryable => status == QueueStatus.failed && retryCount < kMaxQueueItemRetries;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'offline_sync.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftDatabase(tables: [QueueItems])
class OfflineSyncDatabase extends _$OfflineSyncDatabase {
  OfflineSyncDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  /// Watch all items ordered by creation time (fire immediately by default in Drift)
  Stream<List<QueueItem>> watchQueue() {
    return (select(queueItems)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  /// Watch a single item by localId
  Stream<QueueItem?> watchItem(String localId) {
    return (select(queueItems)..where((t) => t.localId.equals(localId)))
        .watchSingleOrNull();
  }

  /// Get all items
  Future<List<QueueItem>> getAllQueueItems() {
    return (select(queueItems)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// Get pending and failed items for upload pass
  Future<List<QueueItem>> getPendingAndFailedItems() {
    return (select(queueItems)
          ..where((t) =>
              t.status.equals(QueueStatus.pending.index) |
              t.status.equals(QueueStatus.failed.index))
          ..orderBy([
            (t) => OrderingTerm(expression: t.status),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Get in-progress processing items
  Future<List<QueueItem>> getProcessingItems() {
    return (select(queueItems)
          ..where((t) => t.status.equals(QueueStatus.processing.index)))
        .get();
  }

  /// Count items currently in queue (pending, uploading, processing)
  Future<int> countPendingOrProcessing() async {
    final countExp = queueItems.id.count();
    final query = selectOnly(queueItems)
      ..addColumns([countExp])
      ..where(
        queueItems.status.equals(QueueStatus.pending.index) |
        queueItems.status.equals(QueueStatus.uploading.index) |
        queueItems.status.equals(QueueStatus.processing.index),
      );
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Count items currently processing
  Future<int> countProcessing() async {
    final countExp = queueItems.id.count();
    final query = selectOnly(queueItems)
      ..addColumns([countExp])
      ..where(queueItems.status.equals(QueueStatus.processing.index));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Find item by localId
  Future<QueueItem?> findItemByLocalId(String localId) {
    return (select(queueItems)..where((t) => t.localId.equals(localId)))
        .getSingleOrNull();
  }

  /// Insert a new queue item
  Future<int> insertQueueItem(QueueItemsCompanion item) {
    return into(queueItems).insert(item);
  }

  /// Update an existing item
  Future<bool> updateQueueItem(QueueItem item) {
    return update(queueItems).replace(item);
  }

  /// Reset a single item to pending
  Future<void> retryItem(String localId) async {
    await (update(queueItems)..where((t) => t.localId.equals(localId))).write(
      const QueueItemsCompanion(
        status: Value(QueueStatus.pending),
        retryCount: Value(0),
        errorMessage: Value(null),
      ),
    );
  }

  /// Reset all failed items to pending
  Future<void> retryAllFailed() async {
    await (update(queueItems)
          ..where((t) => t.status.equals(QueueStatus.failed.index)))
        .write(
      const QueueItemsCompanion(
        status: Value(QueueStatus.pending),
        retryCount: Value(0),
        errorMessage: Value(null),
      ),
    );
  }
}
