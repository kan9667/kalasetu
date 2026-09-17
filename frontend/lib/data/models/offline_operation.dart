import 'dart:convert';

/// Represents a durable offline operation queued for server synchronization.
///
/// Encapsulates product mutation type, revision metadata, deterministic content
/// hash, media dependency tracking, immutable payload snapshots, completed upstream
/// results, and persistent idempotency key.
class OfflineOperation {
  static const String actionCreate = 'CREATE';
  static const String actionUpdate = 'UPDATE';
  static const String actionApprovePublish = 'APPROVE_PUBLISH';
  static const String actionDelete = 'DELETE';
  static const String actionMediaUpload = 'MEDIA_UPLOAD';
  static const String actionAttachMedia = 'ATTACH_MEDIA';
  static const String actionUnpublish = 'UNPUBLISH';

  static const String statusPending = 'pending';
  static const String statusInFlight = 'in_flight';
  static const String statusInProgress = 'in_progress';
  static const String statusCompleted = 'completed';
  static const String statusUserActionRequired = 'user_action_required';
  static const String statusSuperseded = 'superseded';

  final String id;
  final String action;
  final String productId;
  final int? revision;
  final String? contentHash;
  final String idempotencyKey;
  final String? mediaLocalId;
  final String? mediaId;
  final String status;
  final String? dependsOnOpId;
  final String? mediaIdFromOpId;
  final Map<String, dynamic>? payloadSnapshot;
  final Map<String, dynamic>? resultData;
  final String? result;
  final String? errorMessage;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? leaseExpiresAt;

  OfflineOperation({
    String? id,
    required this.action,
    required this.productId,
    this.revision,
    this.contentHash,
    required this.idempotencyKey,
    this.mediaLocalId,
    this.mediaId,
    this.status = statusPending,
    this.dependsOnOpId,
    this.mediaIdFromOpId,
    this.payloadSnapshot,
    this.resultData,
    this.result,
    this.errorMessage,
    this.retryCount = 0,
    DateTime? createdAt,
    this.leaseExpiresAt,
  })  : id = id ?? 'op_${action.toLowerCase()}_${productId}_${DateTime.now().microsecondsSinceEpoch}',
        createdAt = createdAt ?? DateTime.now();

  bool isLeaseActive([DateTime? now]) {
    if (status != statusInFlight && status != statusInProgress) return false;
    if (leaseExpiresAt == null) return false;
    final currentTime = now ?? DateTime.now();
    return currentTime.isBefore(leaseExpiresAt!);
  }

  OfflineOperation copyWith({
    String? id,
    String? action,
    String? productId,
    int? revision,
    String? contentHash,
    String? idempotencyKey,
    String? mediaLocalId,
    String? mediaId,
    String? status,
    String? dependsOnOpId,
    String? mediaIdFromOpId,
    Map<String, dynamic>? payloadSnapshot,
    Map<String, dynamic>? resultData,
    String? result,
    String? errorMessage,
    int? retryCount,
    DateTime? createdAt,
    DateTime? leaseExpiresAt,
    bool clearLeaseExpiresAt = false,
  }) {
    return OfflineOperation(
      id: id ?? this.id,
      action: action ?? this.action,
      productId: productId ?? this.productId,
      revision: revision ?? this.revision,
      contentHash: contentHash ?? this.contentHash,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      mediaLocalId: mediaLocalId ?? this.mediaLocalId,
      mediaId: mediaId ?? this.mediaId,
      status: status ?? this.status,
      dependsOnOpId: dependsOnOpId ?? this.dependsOnOpId,
      mediaIdFromOpId: mediaIdFromOpId ?? this.mediaIdFromOpId,
      payloadSnapshot: payloadSnapshot ?? this.payloadSnapshot,
      resultData: resultData ?? this.resultData,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      leaseExpiresAt: clearLeaseExpiresAt ? null : (leaseExpiresAt ?? this.leaseExpiresAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'product_id': productId,
      'revision': revision,
      'content_hash': contentHash,
      'idempotency_key': idempotencyKey,
      'media_local_id': mediaLocalId,
      'media_id': mediaId,
      'status': status,
      'depends_on_op_id': dependsOnOpId,
      'media_id_from_op_id': mediaIdFromOpId,
      'payload_snapshot': payloadSnapshot,
      'result_data': resultData,
      'result': result,
      'error_message': errorMessage,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'lease_expires_at': leaseExpiresAt?.toIso8601String(),
    };
  }

  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'] as String?,
      action: json['action'] as String? ?? actionUpdate,
      productId: json['product_id'] as String? ?? json['productId'] as String? ?? '',
      revision: (json['revision'] as num?)?.toInt(),
      contentHash: json['content_hash'] as String? ?? json['contentHash'] as String?,
      idempotencyKey: json['idempotency_key'] as String? ??
          json['idempotencyKey'] as String? ??
          'op_${DateTime.now().millisecondsSinceEpoch}',
      mediaLocalId: json['media_local_id'] as String? ?? json['mediaLocalId'] as String?,
      mediaId: json['media_id'] as String? ?? json['mediaId'] as String?,
      status: json['status'] as String? ?? statusPending,
      dependsOnOpId: json['depends_on_op_id'] as String? ?? json['dependsOnOpId'] as String?,
      mediaIdFromOpId: json['media_id_from_op_id'] as String? ?? json['mediaIdFromOpId'] as String?,
      payloadSnapshot: json['payload_snapshot'] != null
          ? Map<String, dynamic>.from(json['payload_snapshot'] as Map)
          : null,
      resultData: json['result_data'] != null
          ? Map<String, dynamic>.from(json['result_data'] as Map)
          : null,
      result: json['result'] as String?,
      errorMessage: json['error_message'] as String? ?? json['errorMessage'] as String?,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'] as String) ?? DateTime.now())
          : DateTime.now(),
      leaseExpiresAt: json['lease_expires_at'] != null
          ? DateTime.tryParse(json['lease_expires_at'] as String)
          : (json['leaseExpiresAt'] != null
              ? DateTime.tryParse(json['leaseExpiresAt'] as String)
              : null),
    );
  }

  String toPendingString() => jsonEncode(toJson());

  /// Safely decodes either a modern JSON string or a legacy raw action string ('CREATE', 'UPDATE', 'DELETE')
  static OfflineOperation fromPendingString(String raw, String key) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        final op = OfflineOperation.fromJson(decoded);
        if (op.id.isEmpty) {
          return op.copyWith(id: key);
        }
        return op;
      } catch (_) {
        // Fallback to plain action if JSON parsing fails
      }
    }

    return OfflineOperation(
      id: key,
      action: trimmed.isNotEmpty ? trimmed : actionUpdate,
      productId: key,
      idempotencyKey: 'migrated_${key}_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
  }
}
