import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/add_product/screens/add_product_flow_screen.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';

class MockHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = MockHttpOverrides();

    final tempDir = await Directory.systemTemp.createTemp('hive_add_product_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }

    if (!Hive.isBoxOpen('draft_box')) {
      await Hive.openBox('draft_box');
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
  });

  testWidgets('Add Product flow loads step 1 capture screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AddProductFlowScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    // Verify initial step title and capture icons exist
    expect(find.byIcon(Icons.camera_alt), findsWidgets);
    expect(find.byIcon(Icons.photo_library), findsWidgets);
  });
}
