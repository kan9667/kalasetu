import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app.dart';
import 'data/models/product.dart';
import 'data/models/user_profile.dart';

Future<Box<T>> _openSafeBox<T>(String boxName) async {
  try {
    return await Hive.openBox<T>(boxName);
  } catch (e) {
    debugPrint('Resetting incompatible Hive box "$boxName": $e');
    await Hive.deleteBoxFromDisk(boxName);
    return await Hive.openBox<T>(boxName);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await Hive.initFlutter();

  // Register adapters if not already present
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(ProductStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ProductAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(UserProfileAdapter());
  }

  // Safely open all boxes
  await _openSafeBox<Product>('products_box');
  await _openSafeBox<String>('pending_sync_box');
  await _openSafeBox<UserProfile>('user_profile_box');
  await _openSafeBox('auth_box');
  await _openSafeBox('draft_box');
  await _openSafeBox('app_settings_box');

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
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