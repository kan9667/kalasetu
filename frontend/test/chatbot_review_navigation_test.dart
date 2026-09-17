import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/router/app_route_constants.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/chat_message.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/features/catalogue/screens/review_existing_product_screen.dart';
import 'package:kalasetu/features/chatbot/providers/chat_provider.dart';
import 'package:kalasetu/features/chatbot/screens/chatbot_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_review_nav_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ProductStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    final box = Hive.box<Product>('products_box');
    await box.clear();

    final draftProduct = Product(
      id: 'prod_review_999',
      title: 'Terracotta Vase Draft',
      description: 'Handcrafted terracotta clay vase',
      category: 'Pottery & Ceramics',
      price: 1500,
      floorPrice: 800,
      materialsCost: 300,
      laborHours: 5,
      hourlyRate: 100,
      photoPath: 'assets/images/placeholder.jpg',
      status: ProductStatus.draft,
      createdAt: DateTime.now(),
      revision: 1,
    );
    await box.put(draftProduct.id, draftProduct);
  });

  testWidgets('tapping review action navigates to /review-product/:id without auto-publishing', (tester) async {
    final router = GoRouter(
      initialLocation: '/assistant',
      routes: [
        GoRoute(
          path: '/assistant',
          builder: (context, state) => const Scaffold(body: ChatbotSheet()),
        ),
        GoRoute(
          path: '/review-product/:id',
          name: AppRouteConstants.reviewProduct,
          builder: (context, state) {
            final productId = state.pathParameters['id'] ?? '';
            final box = Hive.box<Product>('products_box');
            final product = box.get(productId) ??
                Product(
                  id: productId,
                  title: '',
                  description: '',
                  category: '',
                  price: 0,
                  photoPath: '',
                  status: ProductStatus.draft,
                  createdAt: DateTime.now(),
                );
            return ReviewExistingProductScreen(initialProduct: product);
          },
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Inject a message with a review action card
    final chatNotifier = container.read(chatNotifierProvider.notifier);
    final reviewMessage = ChatMessageModel.assistant(
      text: 'Your draft listing is ready for review.',
      action: const ChatActionModel(
        type: 'review_product',
        destination: 'review_product',
        label: 'Review Listing',
        params: {'product_id': 'prod_review_999'},
      ),
    );

    chatNotifier.state = chatNotifier.state.copyWith(
      messages: [reviewMessage],
    );

    await tester.pumpAndSettle();

    // Verify action card button is visible
    expect(find.text('Review Listing'), findsOneWidget);

    // Tap action card button
    await tester.tap(find.text('Review Listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify navigation landed on ReviewExistingProductScreen with correct product
    expect(find.byType(ReviewExistingProductScreen), findsOneWidget);
    expect(find.textContaining('Terracotta Vase Draft'), findsWidgets);

    // CRITICAL INVARIANT: Verify product status in storage is STILL draft, NEVER auto-published
    final box = Hive.box<Product>('products_box');
    final storedProduct = box.get('prod_review_999');
    expect(storedProduct, isNotNull);
    expect(storedProduct!.status, equals(ProductStatus.draft),
        reason: 'Action execution must NEVER auto-publish without explicit user confirmation on the review screen.');
  });
}
