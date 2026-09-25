/// Thrown when an authenticated endpoint returns 401 Unauthorized or 403 Forbidden,
/// indicating that the artisan's session has expired or permissions are invalid.
///
/// This exception must NEVER be caught as an offline fallback, AI failure, or mock fallback.
class SessionExpiredException implements Exception {
  final String message;
  final int? statusCode;

  const SessionExpiredException([
    this.message = 'Session expired or unauthorized. Please log in again.',
    this.statusCode,
  ]);

  @override
  String toString() => 'SessionExpiredException($statusCode): $message';
}
