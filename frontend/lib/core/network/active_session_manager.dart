import 'package:hive/hive.dart';
import '../config/api_config.dart';

/// Enum representing the authoritative active session mode.
enum ActiveSessionMode {
  artisan,
  ngoSimulation,
  unauthenticated,
}

/// Authoritative manager for active session state across authenticated clients,
/// private media caching, and background synchronization outbox.
class ActiveSessionManager {
  static const String authBoxName = 'auth_box';
  static const String keyIsNgoSimulation = 'is_ngo_simulation';
  static const String keyIsAuthenticated = 'is_authenticated';
  static const String keyUserId = 'user_id';
  static const String keyNgoUserId = 'ngo_user_id';

  static int _sessionGeneration = 0;

  /// Monotonically increasing session generation counter.
  static int get sessionGeneration => _sessionGeneration;

  /// Explicitly bumps session generation upon login, logout, account switch, or simulation change.
  static void bumpSessionGeneration() {
    _sessionGeneration++;
  }

  /// Synchronously checks if NGO simulation is active according to Hive auth_box.
  static bool isNgoSimulation() {
    if (!Hive.isBoxOpen(authBoxName)) return false;
    final box = Hive.box(authBoxName);
    return box.get(keyIsNgoSimulation, defaultValue: false) == true;
  }

  /// Asynchronously checks if NGO simulation is active.
  static Future<bool> isNgoSimulationAsync() async {
    final box = Hive.isBoxOpen(authBoxName)
        ? Hive.box(authBoxName)
        : await Hive.openBox(authBoxName);
    return box.get(keyIsNgoSimulation, defaultValue: false) == true;
  }

  /// Checks if session storage initialization is complete.
  static bool isSessionReady() {
    return Hive.isBoxOpen(authBoxName);
  }

  /// Synchronously gets current user ID from auth_box if open.
  static String? getCurrentUserIdSync() {
    if (!Hive.isBoxOpen(authBoxName)) return null;
    return Hive.box(authBoxName).get(keyUserId) as String?;
  }

  /// Synchronously resolves active session mode from auth_box.
  static ActiveSessionMode getActiveSessionModeSync() {
    if (!Hive.isBoxOpen(authBoxName)) return ActiveSessionMode.unauthenticated;
    final box = Hive.box(authBoxName);
    if (box.get(keyIsNgoSimulation, defaultValue: false) == true) {
      return ActiveSessionMode.ngoSimulation;
    }
    if (box.get(keyIsAuthenticated, defaultValue: false) == true) {
      return ActiveSessionMode.artisan;
    }
    return ActiveSessionMode.unauthenticated;
  }

  /// Resolves the current authoritative active session mode.
  static Future<ActiveSessionMode> getActiveSessionMode() async {
    final box = Hive.isBoxOpen(authBoxName)
        ? Hive.box(authBoxName)
        : await Hive.openBox(authBoxName);
    final isSim = box.get(keyIsNgoSimulation, defaultValue: false) == true;
    if (isSim) {
      return ActiveSessionMode.ngoSimulation;
    }
    final isAuth = box.get(keyIsAuthenticated, defaultValue: false) == true;
    if (isAuth) {
      return ActiveSessionMode.artisan;
    }
    return ActiveSessionMode.unauthenticated;
  }

  /// Validates if an initialized, authenticated artisan session is currently active
  /// and strictly matches the expected initiating credentials and session generation.
  static bool validateArtisanSession({
    required String? expectedUserId,
    required int expectedGeneration,
    required String expectedBackendOrigin,
  }) {
    if (!isSessionReady()) return false;
    if (getActiveSessionModeSync() != ActiveSessionMode.artisan) return false;
    final currentUserId = getCurrentUserIdSync();
    if (currentUserId == null || currentUserId.isEmpty || currentUserId != expectedUserId) {
      return false;
    }
    if (_sessionGeneration != expectedGeneration) return false;
    if (ApiConfig.baseUrl != expectedBackendOrigin) return false;
    return true;
  }
}
