import 'dart:async';
import '../config/api_config.dart';
import 'active_session_manager.dart';

/// Immutable identity context for a network request, captured before any
/// asynchronous preparation to guarantee callers never dispatch under a
/// switched session.
class RequestSessionContext {
  final String? userId;
  final int sessionGeneration;
  final String backendOrigin;

  const RequestSessionContext({
    required this.userId,
    required this.sessionGeneration,
    required this.backendOrigin,
  });

  static const Symbol zoneKey = #kalasetuRequestSessionContext;

  /// Captures initiating identity context before asynchronous preparation.
  /// Prefers scoped Zone overrides when present, falling back to current active session.
  factory RequestSessionContext.capture() {
    final scoped = Zone.current[zoneKey] as RequestSessionContext?;
    if (scoped != null) return scoped;

    final zoneUserId = Zone.current[#kalasetuExpectedUserId] as String?;
    final zoneSessionGen = Zone.current[#kalasetuExpectedSessionGen] as int?;
    final zoneBackend = Zone.current[#kalasetuExpectedBackend] as String?;

    return RequestSessionContext(
      userId: zoneUserId ?? ActiveSessionManager.getCurrentUserIdSync(),
      sessionGeneration: zoneSessionGen ?? ActiveSessionManager.sessionGeneration,
      backendOrigin: zoneBackend ?? ApiConfig.baseUrl,
    );
  }

  /// Explicit factory for when operation identity is already known (e.g. offline queue operation).
  factory RequestSessionContext.explicit({
    required String? userId,
    required int sessionGeneration,
    required String backendOrigin,
  }) {
    return RequestSessionContext(
      userId: userId,
      sessionGeneration: sessionGeneration,
      backendOrigin: backendOrigin,
    );
  }

  /// Returns metadata map suitable for [RequestOptions.extra].
  Map<String, dynamic> toExtra() {
    return {
      if (userId != null && userId!.isNotEmpty) 'expected_user_id': userId,
      'expected_session_gen': sessionGeneration,
      'expected_backend_origin': backendOrigin,
    };
  }
}
