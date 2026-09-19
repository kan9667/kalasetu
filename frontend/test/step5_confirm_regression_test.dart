import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/features/add_product/widgets/step5_confirm_widget.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/social_media_service.dart';
import 'package:kalasetu/features/social_media/providers/social_media_provider.dart';

class MockHttpOverrides extends HttpOverrides {}

class _FakeAddProductNotifier extends StateNotifier<AddProductDraft>
    implements AddProductFlowNotifier {
  _FakeAddProductNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSocialMediaService extends Fake implements SocialMediaService {
  @override
  Future<void> linkDraftsToListing({
    required String draftKey,
    required String listingId,
    String? idempotencyKey,
  }) async {}
}

class _FakeProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  final ProductStatus publishReturnStatus;

  _FakeProductListNotifier(this.publishReturnStatus) : super(const AsyncValue.data([]));

  @override
  Future<Product> addProduct(Product product) async {
    return product.copyWith(status: ProductStatus.draft, revision: 1);
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    int? revision,
    String? contentHash,
    String? idempotencyKey,
  }) async {
    return Product(
      id: productId,
      title: 'Handmade Bowl',
      description: 'Clay bowl',
      price: 500.0,
      photoPath: '',
      category: 'Pottery',
      status: publishReturnStatus,
      revision: revision ?? 1,
      contentHash: contentHash ?? '1111111111111111111111111111111111111111111111111111111111111111',
      publishedAt: publishReturnStatus == ProductStatus.published ? DateTime.now() : null,
      approvedAt: publishReturnStatus == ProductStatus.published ? DateTime.now() : null,
      approvedRevision: publishReturnStatus == ProductStatus.published ? (revision ?? 1) : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingProductListNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductListNotifier {
  _ThrowingProductListNotifier() : super(const AsyncValue.data([]));

  @override
  Future<Product> addProduct(Product product) async {
    return product.copyWith(status: ProductStatus.draft, revision: 1);
  }

  @override
  Future<Product> approveAndPublishProduct(
    String productId, {
    int? revision,
    String? contentHash,
    String? idempotencyKey,
  }) async {
    throw Exception('Simulated network error during approval');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AddProductDraft testDraft;

  setUpAll(() async {
    HttpOverrides.global = MockHttpOverrides();

    tempDir = await Directory.systemTemp.createTemp('hive_step5_test');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());

    if (!Hive.isBoxOpen('products_box')) await Hive.openBox<Product>('products_box');
    if (!Hive.isBoxOpen('pending_sync_box')) await Hive.openBox<String>('pending_sync_box');
    if (!Hive.isBoxOpen('user_profile_box')) await Hive.openBox<UserProfile>('user_profile_box');
    if (!Hive.isBoxOpen('draft_box')) await Hive.openBox('draft_box');

    final samplePhoto = File('${tempDir.path}/sample_pot.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

    testDraft = AddProductDraft(
      titleEn: 'Handmade Bowl',
      category: 'Pottery',
      finalPrice: 500.0,
      floorPrice: 300.0,
      originalImagePath: samplePhoto.path,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    await Hive.box<Product>('products_box').clear();
    await Hive.box<String>('pending_sync_box').clear();
  });

  testWidgets('Step 5 Confirm: Online connectivity with queued publish asserts neither dialog nor badge says live', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addProductFlowProvider.overrideWith((ref) => _FakeAddProductNotifier(testDraft)),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          productListProvider.overrideWith((ref) => _FakeProductListNotifier(ProductStatus.pendingApprovalSync)),
          userProfileProvider.overrideWith((ref) => UserProfileNotifier()),
          socialMediaServiceProvider.overrideWithValue(_FakeSocialMediaService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Step5ConfirmWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Invariant: Even though device is online, initial unapproved draft badge MUST NOT say live!
    expect(find.text('status_pending_approval_sync'), findsOneWidget);
    expect(find.text('status_live'), findsNothing);

    // Tap List Product button
    final listBtn = find.byIcon(Icons.cloud_upload_outlined);
    expect(listBtn, findsOneWidget);
    await tester.ensureVisible(listBtn);
    await tester.pumpAndSettle();
    await tester.tap(listBtn);
    await tester.pumpAndSettle();

    // Assert: Invariant enforced - neither dialog nor status badge says "live"!
    // Dialog assertions:
    expect(find.byIcon(Icons.cloud_queue), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('saved_offline_awaiting_sync'), findsOneWidget);
    expect(find.text('listing_online_success'), findsNothing);

    // Status badge assertions:
    expect(find.text('status_live'), findsNothing);
    expect(find.text('status_pending_approval_sync'), findsOneWidget);
  });

  testWidgets('Step 5 Confirm: Online connectivity with thrown publish error asserts neither dialog nor badge says live', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addProductFlowProvider.overrideWith((ref) => _FakeAddProductNotifier(testDraft)),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          productListProvider.overrideWith((ref) => _ThrowingProductListNotifier()),
          userProfileProvider.overrideWith((ref) => UserProfileNotifier()),
          socialMediaServiceProvider.overrideWithValue(_FakeSocialMediaService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Step5ConfirmWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initial badge check
    expect(find.text('status_live'), findsNothing);
    expect(find.text('status_pending_approval_sync'), findsOneWidget);

    // Tap List Product button
    final listBtn = find.byIcon(Icons.cloud_upload_outlined);
    expect(listBtn, findsOneWidget);
    await tester.ensureVisible(listBtn);
    await tester.pumpAndSettle();
    await tester.tap(listBtn);
    await tester.pumpAndSettle();

    // Error snackbar shown, no dialog, badge still not live
    expect(find.text('status_live'), findsNothing);
    expect(find.text('status_pending_approval_sync'), findsOneWidget);
    expect(find.text('listing_online_success'), findsNothing);
  });

  testWidgets('Step 5 Confirm: Online connectivity with successful publish shows listing online success and live badge', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addProductFlowProvider.overrideWith((ref) => _FakeAddProductNotifier(testDraft)),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
          productListProvider.overrideWith((ref) => _FakeProductListNotifier(ProductStatus.published)),
          userProfileProvider.overrideWith((ref) => UserProfileNotifier()),
          socialMediaServiceProvider.overrideWithValue(_FakeSocialMediaService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Step5ConfirmWidget(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Before tapping List Product, badge MUST NOT say live
    expect(find.text('status_live'), findsNothing);
    expect(find.text('status_pending_approval_sync'), findsOneWidget);

    // Tap List Product button
    final listBtn = find.byIcon(Icons.cloud_upload_outlined);
    expect(listBtn, findsOneWidget);
    await tester.ensureVisible(listBtn);
    await tester.pumpAndSettle();
    await tester.tap(listBtn);
    await tester.pumpAndSettle();

    // Assert: Server published status shows check_circle and listing_online_success
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cloud_queue), findsNothing);

    expect(find.text('listing_online_success'), findsOneWidget);
    expect(find.text('saved_offline_awaiting_sync'), findsNothing);

    // Assert: Status badge now indicates live
    expect(find.text('status_live'), findsOneWidget);
    expect(find.text('status_pending_approval_sync'), findsNothing);
  });
}
