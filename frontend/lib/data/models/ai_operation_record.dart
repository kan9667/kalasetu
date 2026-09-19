import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Represents an immutable record of an AI operation before and after execution.
///
/// Encapsulates operation identity, idempotency key, owner, backend origin,
/// canonical input fingerprint (including file content SHA-256), generation counter,
/// status lifecycle, and eventual authoritative result.
class AiOperationRecord {
  static const String statusPending = 'pending';
  static const String statusInFlight = 'in_flight';
  static const String statusCompleted = 'completed';
  static const String statusFailed = 'failed';
  static const String statusSuperseded = 'superseded';

  final String id;
  final String idempotencyKey;
  final String owner;
  final String backend;
  final String operationType;
  final String draftId;
  final int inputGeneration;
  final String inputFingerprint;
  final Map<String, dynamic> requestSnapshot;
  final String status;
  final Map<String, dynamic>? resultData;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiOperationRecord({
    required this.id,
    required this.idempotencyKey,
    required this.owner,
    required this.backend,
    required this.operationType,
    required this.draftId,
    required this.inputGeneration,
    required this.inputFingerprint,
    required this.requestSnapshot,
    this.status = statusPending,
    this.resultData,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  AiOperationRecord copyWith({
    String? status,
    Map<String, dynamic>? resultData,
    String? errorMessage,
    DateTime? updatedAt,
  }) {
    return AiOperationRecord(
      id: id,
      idempotencyKey: idempotencyKey,
      owner: owner,
      backend: backend,
      operationType: operationType,
      draftId: draftId,
      inputGeneration: inputGeneration,
      inputFingerprint: inputFingerprint,
      requestSnapshot: requestSnapshot,
      status: status ?? this.status,
      resultData: resultData ?? this.resultData,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'idempotency_key': idempotencyKey,
      'owner': owner,
      'backend': backend,
      'operation_type': operationType,
      'draft_id': draftId,
      'input_generation': inputGeneration,
      'input_fingerprint': inputFingerprint,
      'request_snapshot': requestSnapshot,
      'status': status,
      'result_data': resultData,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory AiOperationRecord.fromJson(Map<String, dynamic> json) {
    return AiOperationRecord(
      id: json['id'] as String,
      idempotencyKey: json['idempotency_key'] as String? ?? json['id'] as String,
      owner: json['owner'] as String? ?? 'anonymous',
      backend: json['backend'] as String? ?? '',
      operationType: json['operation_type'] as String,
      draftId: json['draft_id'] as String? ?? '',
      inputGeneration: (json['input_generation'] as num?)?.toInt() ?? 0,
      inputFingerprint: json['input_fingerprint'] as String,
      requestSnapshot: json['request_snapshot'] != null
          ? Map<String, dynamic>.from(json['request_snapshot'] as Map)
          : {},
      status: json['status'] as String? ?? statusPending,
      resultData: json['result_data'] != null
          ? Map<String, dynamic>.from(json['result_data'] as Map)
          : null,
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// Computes a canonical SHA-256 fingerprint over all input fields affecting results.
  /// If files are provided, computes the SHA-256 hash of the actual FILE CONTENT.
  static Future<String> computeFingerprint({
    required String operationType,
    required String owner,
    required String backend,
    required Map<String, dynamic> inputs,
    List<File>? files,
  }) async {
    final canonicalMap = SplayTreeMap<String, dynamic>();
    canonicalMap['__type'] = operationType;
    canonicalMap['__owner'] = owner;
    canonicalMap['__backend'] = backend;

    // Add canonical inputs
    inputs.forEach((key, value) {
      if (value != null) {
        if (value is Map) {
          canonicalMap[key] = SplayTreeMap<String, dynamic>.from(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
        } else if (value is List) {
          canonicalMap[key] = value.map((e) => e?.toString()).toList();
        } else {
          canonicalMap[key] = value;
        }
      }
    });

    // Hash file contents
    if (files != null && files.isNotEmpty) {
      final fileHashes = <String>[];
      for (final file in files) {
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          fileHashes.add(sha256.convert(bytes).toString());
        } else {
          fileHashes.add('file_missing_${file.path}');
        }
      }
      canonicalMap['__file_hashes'] = fileHashes;
    }

    final canonicalJson = jsonEncode(canonicalMap);
    final bytes = utf8.encode(canonicalJson);
    return sha256.convert(bytes).toString();
  }
}

/// Durable storage manager for AI Operation Records using Hive.
class AiOperationStorage {
  static const String boxName = 'ai_operations_box';

  static Future<Box<String>> _getBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<String>(boxName);
    }
    return await Hive.openBox<String>(boxName);
  }

  /// Persists an operation record durably before any network dispatch.
  static Future<void> save(AiOperationRecord record) async {
    final box = await _getBox();
    await box.put(record.id, jsonEncode(record.toJson()));
  }

  /// Retrieves an operation record by ID.
  static Future<AiOperationRecord?> get(String id) async {
    final box = await _getBox();
    final raw = box.get(id);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AiOperationRecord.fromJson(json);
    } catch (e) {
      debugPrint('[AiOperationStorage] Error decoding record $id: $e');
      return null;
    }
  }

  /// Finds an active or completed operation matching the given draft, type, and fingerprint.
  static Future<AiOperationRecord?> findMatching({
    required String operationType,
    required String draftId,
    required String inputFingerprint,
    required int inputGeneration,
  }) async {
    final box = await _getBox();
    for (final raw in box.values) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final rec = AiOperationRecord.fromJson(json);
        if (rec.operationType == operationType &&
            rec.draftId == draftId &&
            rec.inputFingerprint == inputFingerprint &&
            rec.inputGeneration == inputGeneration &&
            rec.status != AiOperationRecord.statusSuperseded) {
          return rec;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Returns all operations for a specific draft.
  static Future<List<AiOperationRecord>> getOperationsForDraft(String draftId) async {
    final box = await _getBox();
    final list = <AiOperationRecord>[];
    for (final raw in box.values) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final rec = AiOperationRecord.fromJson(json);
        if (rec.draftId == draftId) {
          list.add(rec);
        }
      } catch (_) {}
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Marks any older operations for this draft & operation type as superseded.
  static Future<void> markSuperseded(
    String draftId,
    String operationType,
    int currentGeneration,
  ) async {
    final box = await _getBox();
    for (final key in box.keys.cast<String>()) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final rec = AiOperationRecord.fromJson(json);
        if (rec.draftId == draftId &&
            rec.operationType == operationType &&
            rec.inputGeneration < currentGeneration &&
            rec.status != AiOperationRecord.statusSuperseded) {
          final updated = rec.copyWith(status: AiOperationRecord.statusSuperseded);
          await box.put(key, jsonEncode(updated.toJson()));
        }
      } catch (_) {}
    }
  }

  /// Updates status and eventual result for an operation.
  static Future<void> updateResult(
    String id, {
    required String status,
    Map<String, dynamic>? resultData,
    String? errorMessage,
  }) async {
    final existing = await get(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      status: status,
      resultData: resultData,
      errorMessage: errorMessage,
    );
    await save(updated);
  }
}
