import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app.dart';
import 'data/models/product.dart';
import 'data/models/user_profile.dart';
import 'core/offline_sync/offline_sync_service.dart';
import 'core/offline_sync/services/upload_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive TypeAdapters
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(ProductStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ProductAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(UserProfileAdapter());
  }

  // Open Hive Boxes
  await Hive.openBox<Product>('products_box');
  await Hive.openBox<String>('pending_sync_box');
  await Hive.openBox<UserProfile>('user_profile_box');
  await Hive.openBox('auth_box');
  await Hive.openBox('draft_box');

  await OfflineSyncService.instance.init(
    uploadApi: MockUploadApi(),
    healthCheckUrl: null,
  );

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
      child: const ProviderScope(
        child: KalaSetuApp(),
      ),
    ),
  );
}
