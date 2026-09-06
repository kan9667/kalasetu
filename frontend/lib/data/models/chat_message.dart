class ChatActionModel {
  final String type; // 'navigate' | 'update_product_status' | 'filter_catalogue' | 'sync_pending'
  final String destination; // 'add_product', 'catalogue', 'my_stats', etc.
  final String? route; // '/add-product', '/my-stats'
  final int? tabIndex; // 0, 1, 2, 3
  final String label;
  final Map<String, dynamic>? params;
  final String? updatedProductId;
  final String? previousStatus;
  final bool isUndone;
  final bool isExecuted;

  const ChatActionModel({
    required this.type,
    required this.destination,
    this.route,
    this.tabIndex,
    required this.label,
    this.params,
    this.updatedProductId,
    this.previousStatus,
    this.isUndone = false,
    this.isExecuted = false,
  });

  bool get isNavigate => type == 'navigate';
  bool get isStatusUpdate => type == 'update_product_status';
  bool get isCatalogueFilter => type == 'filter_catalogue';
  bool get isSyncPending => type == 'sync_pending';

  String? get targetProduct => params?['target_product'] as String?;
  String? get targetStatus => params?['status'] as String?;
  String? get filterQuery => params?['query'] as String?;
  String? get filterCategory => params?['category'] as String?;

  ChatActionModel copyWith({
    String? type,
    String? destination,
    String? route,
    int? tabIndex,
    String? label,
    Map<String, dynamic>? params,
    String? updatedProductId,
    String? previousStatus,
    bool? isUndone,
    bool? isExecuted,
  }) {
    return ChatActionModel(
      type: type ?? this.type,
      destination: destination ?? this.destination,
      route: route ?? this.route,
      tabIndex: tabIndex ?? this.tabIndex,
      label: label ?? this.label,
      params: params ?? this.params,
      updatedProductId: updatedProductId ?? this.updatedProductId,
      previousStatus: previousStatus ?? this.previousStatus,
      isUndone: isUndone ?? this.isUndone,
      isExecuted: isExecuted ?? this.isExecuted,
    );
  }

  factory ChatActionModel.fromJson(Map<String, dynamic> json) {
    return ChatActionModel(
      type: json['type'] as String? ?? 'navigate',
      destination: json['destination'] as String? ?? '',
      route: json['route'] as String?,
      tabIndex: json['tab_index'] as int?,
      label: json['label'] as String? ?? 'Go',
      params: json['params'] as Map<String, dynamic>?,
      updatedProductId: json['updated_product_id'] as String?,
      previousStatus: json['previous_status'] as String?,
      isUndone: json['is_undone'] as bool? ?? false,
      isExecuted: json['is_executed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'destination': destination,
      'route': route,
      'tab_index': tabIndex,
      'label': label,
      'params': params,
      'updated_product_id': updatedProductId,
      'previous_status': previousStatus,
      'is_undone': isUndone,
      'is_executed': isExecuted,
    };
  }
}

class ChatMessageModel {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final ChatActionModel? action;
  final List<String> suggestedQueries;
  final bool isPending;

  const ChatMessageModel({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.action,
    this.suggestedQueries = const [],
    this.isPending = false,
  });

  factory ChatMessageModel.user(String text) {
    return ChatMessageModel(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
  }

  factory ChatMessageModel.assistant({
    required String text,
    ChatActionModel? action,
    List<String> suggestedQueries = const [],
  }) {
    return ChatMessageModel(
      id: 'assistant_${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
      action: action,
      suggestedQueries: suggestedQueries,
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String? ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
      text: json['reply'] as String? ?? json['text'] as String? ?? '',
      isUser: json['is_user'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      action: json['action'] != null
          ? ChatActionModel.fromJson(json['action'] as Map<String, dynamic>)
          : null,
      suggestedQueries: (json['suggested_queries'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    ChatActionModel? action,
    List<String>? suggestedQueries,
    bool? isPending,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      suggestedQueries: suggestedQueries ?? this.suggestedQueries,
      isPending: isPending ?? this.isPending,
    );
  }
}
