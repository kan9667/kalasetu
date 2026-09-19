import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app.dart';
import 'core/providers/app_providers.dart';
import 'core/storage/hive_box_manager.dart';
import 'core/storage/hive_recovery_app.dart';
import 'core/offline_sync/offline_sync_service.dart';
import 'core/offline_sync/services/upload_api.dart';
import 'core/storage/private_media_cache.dart';
import 'core/config/api_config.dart';
import 'core/services/app_sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  rootBundle.evict('assets/translations/en.json');
  rootBundle.evict('assets/translations/hi.json');
  rootBundle.evict('assets/translations/ta.json');
  rootBundle.evict('assets/translations/bn.json');
  await EasyLocalization.ensureInitialized();

  // Fail-closed, non-destructive Hive initialization
  final report = await HiveBoxManager.init();
  if (!report.isHealthy) {
    debugPrint('[main] Hive data integrity violation: ${report.error}. Entering protection mode.');
    runApp(HiveRecoveryApp(report: report));
    return;
  }

  // Purge any orphaned staging files from prior interrupted downloads
  await PrivateMediaCache.instance.cleanStagingFiles();

  await AppSoundService.instance.init();

  final activeBaseUrl = await ApiConfig.discoverWorkingUrl();

  await OfflineSyncService.instance.init(
    uploadApi: RealUploadApi(baseUrl: activeBaseUrl),
    healthCheckUrl: '$activeBaseUrl/api/v1/health',
  );

  final container = ProviderContainer();

  // Await ProductRepository.initialize on the SAME repository instance consumed by production providers
  try {
    await container.read(productRepositoryProvider).initialize();
  } catch (e) {
    debugPrint('[main] Repository initialization failure: $e');
    runApp(
      HiveRecoveryApp(
        report: HiveRecoveryReport.corrupted(
          boxName: 'pending_sync_box',
          error: e.toString(),
        ),
      ),
    );
    return;
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('ta'),
        Locale('bn'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      useOnlyLangCode: true,
      child: UncontrolledProviderScope(
        container: container,
        child: const KalaSetuApp(),
      ),
    ),
  );
}