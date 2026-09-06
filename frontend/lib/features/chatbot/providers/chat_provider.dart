import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/models/product.dart';
import '../../../data/services/chat_service.dart';
import '../../catalogue/providers/catalogue_filter_provider.dart';
import '../../home/screens/home_shell.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return HttpChatService();
});

class ChatState {
  final List<ChatMessageModel> messages;
  final bool isLoading;
  final List<Map<String, dynamic>> quickTopics;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.quickTopics = const [],
  });

  ChatState copyWith({
    List<ChatMessageModel>? messages,
    bool? isLoading,
    List<Map<String, dynamic>>? quickTopics,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      quickTopics: quickTopics ?? this.quickTopics,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatService _service;
  final Ref _ref;

  ChatNotifier(this._service, this._ref) : super(const ChatState()) {
    init();
  }

  Future<void> init({String languageCode = 'en'}) async {
    final welcomeMsg = languageCode == 'hi'
        ? 'नमस्ते! मैं कला-मित्र (KalaMitra) हूँ, कलासेतु में आपका डिजिटल सहायक।\n\nमैं आपको उत्पाद जोड़ने, उचित मूल्य निर्धारण समझने, कैटलॉग प्रबंधित करने या किसी भी स्क्रीन पर ले जाने में मदद कर सकता हूँ। आप क्या करना चाहते हैं?'
        : 'Namaste! I am KalaMitra, your guide for KalaSetu.\n\nI can help you add products, understand fair pricing, update product status, sync offline items, or navigate you to any screen. How can I help you today?';

    final topics = await _service.getQuickTopics(languageCode: languageCode);

    state = state.copyWith(
      messages: [
        ChatMessageModel.assistant(
          text: welcomeMsg,
          suggestedQueries: languageCode == 'hi'
              ? ['नया उत्पाद कैसे जोड़ें?', 'मूल्य कैसे तय होता है?', 'माय कैटलॉग खोलें', 'मेरी कमाई दिखाएं']
              : ['How to add a product?', 'How does fair pricing work?', 'Take me to my catalogue', 'Open my stats'],
        ),
      ],
      quickTopics: topics,
    );
  }

  Future<void> sendMessage(
    String text, {
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty || state.isLoading) return;

    final userMsg = ChatMessageModel.user(clean);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
    );

    try {
      final reply = await _service.sendMessage(
        message: clean,
        history: state.messages,
        languageCode: languageCode,
        currentScreen: currentScreen,
      );

      await _handleIncomingAssistantReply(reply, languageCode);
    } catch (e) {
      final errorMsg = ChatMessageModel.assistant(
        text: languageCode == 'hi'
            ? 'माफ़ कीजिए, उत्तर प्राप्त करने में समस्या हुई। कृपया पुनः प्रयास करें।'
            : 'Sorry, I encountered an issue retrieving an answer. Please try again.',
      );
      state = state.copyWith(
        messages: [...state.messages, errorMsg],
        isLoading: false,
      );
    }
  }

  Future<void> sendVoiceMessage(
    String audioPath, {
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    if (state.isLoading) return;

    final isHi = languageCode == 'hi';
    final placeholder = ChatMessageModel.user(
      isHi ? '🎙️ आवाज़ सुन रहे हैं...' : '🎙️ Processing voice note...',
    );

    state = state.copyWith(
      messages: [...state.messages, placeholder],
      isLoading: true,
    );

    try {
      final result = await _service.sendVoiceMessage(
        audioPath: audioPath,
        languageCode: languageCode,
        currentScreen: currentScreen,
      );

      final updatedList = List<ChatMessageModel>.from(state.messages);
      if (updatedList.isNotEmpty && updatedList.last.id == placeholder.id) {
        updatedList.removeLast();
      }

      final realUserMsg = ChatMessageModel.user(
        result.userTranscript.isNotEmpty
            ? '🎙️ ${result.userTranscript}'
            : (isHi ? '🎙️ आवाज़ संदेश' : '🎙️ Voice message'),
      );

      state = state.copyWith(
        messages: [...updatedList, realUserMsg],
      );

      await _handleIncomingAssistantReply(result.assistantMessage, languageCode);
    } catch (e) {
      debugPrint('[ChatNotifier] Voice message error: $e');
      final errorMsg = ChatMessageModel.assistant(
        text: isHi
            ? 'माफ़ कीजिए, आवाज़ समझने में समस्या हुई। कृपया पुनः प्रयास करें।'
            : 'Sorry, I encountered an issue transcribing your voice note. Please try again.',
      );
      state = state.copyWith(
        messages: [...state.messages, errorMsg],
        isLoading: false,
      );
    }
  }

  /// Process incoming assistant reply and auto-execute direct actions if applicable
  Future<void> _handleIncomingAssistantReply(
    ChatMessageModel reply,
    String languageCode,
  ) async {
    final action = reply.action;

    // 1. Direct Status Update Execution (e.g., "Mark my Chanderi Saree as sold")
    if (action != null && action.isStatusUpdate) {
      final processedMsg = await _executeDirectStatusUpdate(reply, languageCode);
      state = state.copyWith(
        messages: [...state.messages, processedMsg],
        isLoading: false,
      );
      return;
    }

    // 2. Instant Sync Trigger Execution (e.g., "Sync my pending offline products now")
    if (action != null && action.isSyncPending) {
      await _executeDirectSync(reply, languageCode);
      return;
    }

    // 3. Normal reply or Navigation / Catalogue Filter action
    state = state.copyWith(
      messages: [...state.messages, reply],
      isLoading: false,
    );
  }

  /// Finds target product in local catalogue and updates status directly, attaching undo metadata
  Future<ChatMessageModel> _executeDirectStatusUpdate(
    ChatMessageModel reply,
    String languageCode,
  ) async {
    final action = reply.action;
    if (action == null) return reply;

    final target = (action.targetProduct ?? '').trim().toLowerCase();
    final statusStr = (action.targetStatus ?? 'sold').trim().toLowerCase();
    final isHi = languageCode == 'hi';

    try {
      final repo = _ref.read(productRepositoryProvider);
      final products = await repo.getProducts();

      Product? matchedProduct;
      if (target.isNotEmpty) {
        // Try exact match first
        for (final p in products) {
          if (p.title.toLowerCase() == target || p.titleHi.toLowerCase() == target) {
            matchedProduct = p;
            break;
          }
        }
        // Substring / fuzzy match
        if (matchedProduct == null) {
          for (final p in products) {
            if (p.title.toLowerCase().contains(target) ||
                p.titleHi.toLowerCase().contains(target) ||
                target.contains(p.title.toLowerCase())) {
              matchedProduct = p;
              break;
            }
          }
        }
      }

      // Default to single product if only one exists in catalogue and user said "this" / "product"
      if (matchedProduct == null && products.isNotEmpty) {
        if (products.length == 1 || target.isEmpty || target == 'this' || target == 'it') {
          matchedProduct = products.first;
        }
      }

      if (matchedProduct == null) {
        final notFoundText = isHi
            ? 'कैटलॉग में "${action.targetProduct ?? 'यह'}" नाम का कोई उत्पाद नहीं मिला। कृपया उत्पाद का नाम जांचें।'
            : 'Could not find a product matching "${action.targetProduct ?? 'this'}" in your catalogue.';
        return reply.copyWith(
          text: notFoundText,
          action: null,
        );
      }

      final previousStatus = matchedProduct.status;
      ProductStatus newStatus;
      switch (statusStr) {
        case 'sold':
          newStatus = ProductStatus.sold;
          break;
        case 'live':
          newStatus = ProductStatus.live;
          break;
        case 'draft':
          newStatus = ProductStatus.draft;
          break;
        default:
          newStatus = ProductStatus.sold;
      }

      final updatedProduct = matchedProduct.copyWith(status: newStatus);
      await _ref.read(productListProvider.notifier).updateProduct(updatedProduct);

      final statusDisplay = isHi
          ? (newStatus == ProductStatus.sold ? 'बिक गया (Sold)' : newStatus.name)
          : (newStatus == ProductStatus.sold ? 'Sold' : newStatus.name);

      final updatedAction = action.copyWith(
        updatedProductId: matchedProduct.id,
        previousStatus: previousStatus.name,
        isExecuted: true,
        label: isHi ? 'स्थिति: $statusDisplay' : 'Marked as $statusDisplay',
      );

      final confirmationText = isHi
          ? '✅ "${matchedProduct.title}" का स्टेटस बदलकर "$statusDisplay" कर दिया गया है।'
          : '✅ Successfully marked "${matchedProduct.title}" as $statusDisplay directly in your catalogue.';

      return reply.copyWith(
        text: confirmationText,
        action: updatedAction,
      );
    } catch (e) {
      debugPrint('[ChatNotifier] Direct status update error: $e');
      return reply;
    }
  }

  /// Reverts a direct product status update back to its previous state
  Future<void> undoProductStatusUpdate(
    String messageId,
    String productId,
    String previousStatusStr,
  ) async {
    try {
      final repo = _ref.read(productRepositoryProvider);
      final products = await repo.getProducts();
      final prodIndex = products.indexWhere((p) => p.id == productId);
      if (prodIndex == -1) return;

      final prod = products[prodIndex];
      ProductStatus prevStatus = ProductStatus.live;
      for (final s in ProductStatus.values) {
        if (s.name.toLowerCase() == previousStatusStr.toLowerCase()) {
          prevStatus = s;
          break;
        }
      }

      final revertedProduct = prod.copyWith(status: prevStatus);
      await _ref.read(productListProvider.notifier).updateProduct(revertedProduct);

      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId && m.action != null) {
          return m.copyWith(
            text: '${m.text}\n\n↺ Undo successful: "${prod.title}" status restored to ${prevStatus.name.toUpperCase()}.',
            action: m.action!.copyWith(
              isUndone: true,
              label: 'Restored to ${prevStatus.name.toUpperCase()}',
            ),
          );
        }
        return m;
      }).toList();

      state = state.copyWith(messages: updatedMessages);
    } catch (e) {
      debugPrint('[ChatNotifier] Error undoing product status: $e');
    }
  }

  /// Executes instant synchronization of offline pending products and reports progress in chat
  Future<void> _executeDirectSync(
    ChatMessageModel initialReply,
    String languageCode,
  ) async {
    final isHi = languageCode == 'hi';

    final pendingMsg = initialReply.copyWith(
      text: isHi
          ? '🔄 ऑफ़लाइन उत्पादों को क्लाउड पर सिंक किया जा रहा है...'
          : '🔄 Syncing pending offline products with KalaSetu cloud...',
    );

    state = state.copyWith(
      messages: [...state.messages, pendingMsg],
      isLoading: false,
    );

    final isOnline = _ref.read(connectivityProvider).value ?? true;
    if (!isOnline) {
      final offlineText = isHi
          ? '⚠️ आप वर्तमान में ऑफ़लाइन हैं। इंटरनेट बहाल होते ही आपके लंबित उत्पाद स्वतः सिंक हो जाएंगे।'
          : '⚠️ You are currently offline. Your pending offline products will automatically sync once internet connection is restored.';

      final updatedMsg = pendingMsg.copyWith(
        text: offlineText,
        action: initialReply.action?.copyWith(isExecuted: true),
      );
      _updateMessageById(initialReply.id, updatedMsg);
      return;
    }

    try {
      final count = await _ref.read(productListProvider.notifier).syncQueue();
      String outcomeText;
      if (count > 0) {
        outcomeText = isHi
            ? '✅ $count ऑफ़लाइन उत्पाद सफलतापूर्वक सिंक हो गए हैं!'
            : '✅ Successfully synced $count offline product${count > 1 ? 's' : ''} to KalaSetu cloud!';
      } else {
        outcomeText = isHi
            ? '✅ आपका कैटलॉग पूरी तरह सिंक है! कोई लंबित उत्पाद नहीं है।'
            : '✅ All caught up! Your catalogue is already fully synced with no pending offline products.';
      }

      final updatedMsg = pendingMsg.copyWith(
        text: outcomeText,
        action: initialReply.action?.copyWith(
          isExecuted: true,
          label: isHi ? 'कैटलॉग देखें' : 'View Catalogue',
        ),
      );
      _updateMessageById(initialReply.id, updatedMsg);
    } catch (e) {
      final errorText = isHi
          ? 'सिंक करने में समस्या आई। कृपया पुनः प्रयास करें।'
          : 'Failed to sync offline products. Please try again.';
      final updatedMsg = pendingMsg.copyWith(
        text: '⚠️ $errorText',
      );
      _updateMessageById(initialReply.id, updatedMsg);
    }
  }

  void _updateMessageById(String id, ChatMessageModel updated) {
    final updatedList = state.messages.map((m) => m.id == id ? updated : m).toList();
    state = state.copyWith(messages: updatedList);
  }

  void executeAction(BuildContext context, ChatActionModel action) {
    debugPrint('[ChatNotifier] Executing action: ${action.type}, destination: ${action.destination}, route: ${action.route}, tabIndex: ${action.tabIndex}');

    // 1. Pre-filtered catalogue navigation
    if (action.isCatalogueFilter) {
      final query = action.filterQuery ?? '';
      final category = action.filterCategory;
      _ref.read(catalogueFilterProvider.notifier).setFilter(
        query: query,
        category: category,
      );
      _ref.read(homeTabIndexProvider.notifier).state = 1;

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }

    // 2. Direct status update action tap -> jump to catalogue to see it
    if (action.isStatusUpdate) {
      _ref.read(homeTabIndexProvider.notifier).state = 1;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }

    // 3. Close bottom sheet if open
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // 4. Handle Tab-based destinations in HomeShell
    if (action.tabIndex != null) {
      _ref.read(homeTabIndexProvider.notifier).state = action.tabIndex!;
      return;
    }

    // 5. Handle specific route destinations
    final route = action.route;
    if (route != null && route.isNotEmpty) {
      try {
        if (route == '/home') {
          context.go('/home');
        } else {
          context.push(route);
        }
      } catch (e) {
        debugPrint('[ChatNotifier] GoRouter navigation error: $e');
        context.go(route);
      }
    } else {
      // Destination mapping fallback
      switch (action.destination) {
        case 'add_product':
          _ref.read(homeTabIndexProvider.notifier).state = 0;
          break;
        case 'catalogue':
          _ref.read(homeTabIndexProvider.notifier).state = 1;
          break;
        case 'notifications':
          _ref.read(homeTabIndexProvider.notifier).state = 2;
          break;
        case 'profile':
          _ref.read(homeTabIndexProvider.notifier).state = 3;
          break;
        case 'my_stats':
          context.push('/my-stats');
          break;
        case 'language_settings':
          context.push('/language-settings');
          break;
      }
    }
  }

  void clearChat(String languageCode) {
    init(languageCode: languageCode);
  }
}

final chatNotifierProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final service = ref.watch(chatServiceProvider);
  return ChatNotifier(service, ref);
});

