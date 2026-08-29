import 'package:workmanager/workmanager.dart';

import 'offline_sync_service.dart';
import 'services/upload_api.dart';

const String kSyncTaskName = 'kaarigar-offline-sync-task';

/// Runs in a separate background isolate — re-initializes everything it
/// needs from scratch (no state is shared with the foreground app).
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await OfflineSyncService.instance.init(
        uploadApi: RealUploadApi(baseUrl: 'https://api.kaarigarconnect.in'),
        healthCheckUrl: 'https://api.kaarigarconnect.in/health',
      );
      await OfflineSyncService.instance.triggerSyncNow();
      return true;
    } catch (_) {
      return false; // WorkManager reschedules based on its own backoff policy
    }
  });
}

/// Call once from `main.dart`, alongside `OfflineSyncService.instance.init(...)`.
///
/// Notes:
/// - Android: WorkManager honors this reliably, even across app kill/reboot.
///   15 minutes is the OS-enforced minimum interval for periodic tasks.
/// - iOS: background execution is opportunistic — iOS decides when (or
///   whether) this actually runs. Treat "sync resumes the moment the
///   artisan reopens the app" (handled by `SyncManager.startListening()`)
///   as the real guarantee; this is a bonus, not the primary mechanism.
void registerBackgroundSync() {
  Workmanager().initialize(syncCallbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    kSyncTaskName,
    kSyncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}
