import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/chat_message.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/services/chat_service.dart';
import 'package:kalasetu/features/catalogue/providers/catalogue_filter_provider.dart';
import 'package:kalasetu/features/chatbot/providers/chat_provider.dart';

class FakeChatService implements ChatService {
  ChatMessageModel? nextReply;

  @override
  Future<List<Map<String, dynamic>>> getQuickTopics({String languageCode = 'en'}) async {
    return [];
  }

  @override
  Future<ChatMessageModel> sendMessage({
    required String message,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    if (nextReply != null) return nextReply!;
    return ChatMessageModel.assistant(text: 'Fallback echo');
  }

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    return VoiceChatResult(
      userTranscript: 'voice note',
      assistantMessage: nextReply ?? ChatMessageModel.assistant(text: 'Voice reply'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeChatService fakeService;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return ['wifi'];
        }
        return null;
      },
    );

    final tempDir = await Directory.systemTemp.createTemp('hive_chat_action_test');
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
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  setUp(() async {
    fakeService = FakeChatService();
    final box = Hive.box<Product>('products_box');
    await box.clear();

    // Insert test product
    final testProduct = Product(
      id: 'test_prod_chanderi',
      title: 'Handloom Chanderi Saree',
      titleHi: 'हथकरघा चंदेरी साड़ी',
      description: 'Pure silk cotton saree',
      descriptionHi: 'शुद्ध रेशम सूती साड़ी',
      category: 'Textiles & Handloom',
      price: 3200,
      photoPath: 'assets/images/placeholder.jpg',
      status: ProductStatus.live,
      createdAt: DateTime.now(),
      tags: ['saree', 'chanderi', 'silk'],
    );
    await box.put(testProduct.id, testProduct);
  });

  test('ChatActionModel correctly identifies action types and properties', () {
    const statusAction = ChatActionModel(
      type: 'update_product_status',
      destination: 'catalogue',
      label: 'Mark as Sold',
      params: {'target_product': 'Chanderi Saree', 'status': 'sold'},
    );

    expect(statusAction.isStatusUpdate, isTrue);
    expect(statusAction.isCatalogueFilter, isFalse);
    expect(statusAction.targetProduct, equals('Chanderi Saree'));
    expect(statusAction.targetStatus, equals('sold'));

    const filterAction = ChatActionModel(
      type: 'filter_catalogue',
      destination: 'catalogue',
      label: 'Filter: Brass',
      params: {'query': 'brass', 'category': null},
    );

    expect(filterAction.isCatalogueFilter, isTrue);
    expect(filterAction.filterQuery, equals('brass'));

    const syncAction = ChatActionModel(
      type: 'sync_pending',
      destination: 'catalogue',
      label: 'Sync Pending',
    );

    expect(syncAction.isSyncPending, isTrue);
  });

  test('catalogueFilterProvider updates and clears filters', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogueFilterProvider).searchQuery, isEmpty);

    container.read(catalogueFilterProvider.notifier).setFilter(
          query: 'brass',
          category: 'Metal Craft',
        );

    expect(container.read(catalogueFilterProvider).searchQuery, equals('brass'));
    expect(container.read(catalogueFilterProvider).selectedCategory, equals('Metal Craft'));

    container.read(catalogueFilterProvider.notifier).clearFilter();
    expect(container.read(catalogueFilterProvider).searchQuery, isEmpty);
    expect(container.read(catalogueFilterProvider).selectedCategory, equals('filter_all'));
  });

  test('Direct status update marks product as sold and supports undo', () async {
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(fakeService),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(container.dispose);

    final box = Hive.box<Product>('products_box');
    expect(box.get('test_prod_chanderi')?.status, equals(ProductStatus.live));

    fakeService.nextReply = ChatMessageModel.assistant(
      text: 'Marking your Chanderi Saree as sold',
      action: const ChatActionModel(
        type: 'update_product_status',
        destination: 'catalogue',
        label: 'Mark as Sold',
        params: {'target_product': 'Chanderi Saree', 'status': 'sold'},
      ),
    );

    final chatNotifier = container.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Mark my Chanderi Saree as sold');

    // Verify product status in Hive changed to sold
    final updatedProduct = box.get('test_prod_chanderi');
    expect(updatedProduct, isNotNull);
    expect(updatedProduct!.status, equals(ProductStatus.sold));

    // Verify chat message recorded action execution
    final state = container.read(chatNotifierProvider);
    final lastMsg = state.messages.last;
    expect(lastMsg.action?.isExecuted, isTrue);
    expect(lastMsg.action?.updatedProductId, equals('test_prod_chanderi'));
    expect(lastMsg.action?.previousStatus, equals('live'));
    expect(lastMsg.action?.isUndone, isFalse);

    // Now test Undo
    await chatNotifier.undoProductStatusUpdate(
      lastMsg.id,
      lastMsg.action!.updatedProductId!,
      lastMsg.action!.previousStatus!,
    );

    // Verify product status restored to live
    final restoredProduct = box.get('test_prod_chanderi');
    expect(restoredProduct, isNotNull);
    expect(restoredProduct!.status, equals(ProductStatus.live));

    // Verify message marked as undone
    final stateAfterUndo = container.read(chatNotifierProvider);
    final undoneMsg = stateAfterUndo.messages.firstWhere((m) => m.id == lastMsg.id);
    expect(undoneMsg.action?.isUndone, isTrue);
  });

  test('Instant sync trigger executes sync and reports progress in chat', () async {
    final container = ProviderContainer(
      overrides: [
        chatServiceProvider.overrideWithValue(fakeService),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(container.dispose);

    fakeService.nextReply = ChatMessageModel.assistant(
      text: 'Syncing your pending offline products...',
      action: const ChatActionModel(
        type: 'sync_pending',
        destination: 'catalogue',
        label: 'Sync Pending Products Now',
      ),
    );

    final chatNotifier = container.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Sync my pending offline products now');

    final state = container.read(chatNotifierProvider);
    final lastMsg = state.messages.last;
    expect(lastMsg.action?.isSyncPending, isTrue);
    expect(lastMsg.action?.isExecuted, isTrue);
    expect(lastMsg.text, contains('synced'));
  });
}
