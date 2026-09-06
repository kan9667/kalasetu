import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';
import '../models/chat_message.dart';

class VoiceChatResult {
  final String userTranscript;
  final ChatMessageModel assistantMessage;

  const VoiceChatResult({
    required this.userTranscript,
    required this.assistantMessage,
  });
}

abstract class ChatService {
  Future<ChatMessageModel> sendMessage({
    required String message,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
  });

  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    String languageCode = 'en',
    String? currentScreen,
  });

  Future<List<Map<String, dynamic>>> getQuickTopics({String languageCode = 'en'});
}

class HttpChatService implements ChatService {
  final Dio _dio;

  HttpChatService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 25),
                sendTimeout: const Duration(seconds: 15),
                headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
              ),
            );

  @override
  Future<ChatMessageModel> sendMessage({
    required String message,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    final activeUrl = ApiConfig.baseUrl;
    _dio.options.baseUrl = activeUrl;

    try {
      final historyPayload = history.take(6).map((m) {
        return {
          'role': m.isUser ? 'user' : 'assistant',
          'content': m.text,
        };
      }).toList();

      final payload = {
        'message': message,
        'history': historyPayload,
        'language_code': languageCode,
        'current_screen': currentScreen,
      };

      debugPrint('[HttpChatService] POST $activeUrl/api/v1/chat/message');
      final response = await _dio.post('/api/v1/chat/message', data: payload);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return ChatMessageModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('[HttpChatService] Backend chat failed or offline: $e. Using local rule fallback.');
    }

    // Offline / Network Fallback
    return _generateOfflineReply(message, languageCode);
  }

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    String languageCode = 'en',
    String? currentScreen,
  }) async {
    final activeUrl = ApiConfig.baseUrl;
    _dio.options.baseUrl = activeUrl;

    try {
      final fileName = audioPath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioPath,
          filename: fileName.isNotEmpty ? fileName : 'chat_voice.m4a',
        ),
        'language_code': languageCode,
      });
      if (currentScreen != null) {
        formData.fields.add(MapEntry('current_screen', currentScreen));
      }

      debugPrint('[HttpChatService] POST $activeUrl/api/v1/chat/voice (lang: $languageCode)');
      final response = await _dio.post('/api/v1/chat/voice', data: formData);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final transcript = (data['user_transcript'] as String? ?? '').trim();
        final assistantMsg = ChatMessageModel.fromJson(data);
        return VoiceChatResult(
          userTranscript: transcript,
          assistantMessage: assistantMsg,
        );
      }
    } catch (e) {
      debugPrint('[HttpChatService] Backend voice chat failed or offline: $e');
    }

    // Fallback if offline
    final isHi = languageCode == 'hi';
    return VoiceChatResult(
      userTranscript: isHi ? 'आवाज़ से पूछा गया सवाल' : 'Voice question',
      assistantMessage: ChatMessageModel.assistant(
        text: isHi
            ? 'ऑफ़लाइन स्थिति में आवाज़ पहचानी नहीं जा सकी। कृपया टाइप करें या इंटरनेट कनेक्शन जांचें।'
            : 'Could not process voice query offline. Please type your question or check your connection.',
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getQuickTopics({String languageCode = 'en'}) async {
    final activeUrl = ApiConfig.baseUrl;
    _dio.options.baseUrl = activeUrl;

    try {
      final response = await _dio.get('/api/v1/chat/quick-topics');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final list = data['topics'] as List<dynamic>?;
        if (list != null) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('[HttpChatService] Failed to fetch quick topics: $e');
    }

    // Default fallback topics
    final isHi = languageCode == 'hi';
    return [
      {
        'id': 'add_product',
        'label': isHi ? 'नया उत्पाद जोड़ें' : 'Add a Product',
        'query': isHi ? 'नया सामान कैसे जोड़ें?' : 'How do I add a new product to my catalogue?',
        'icon': 'plus_circle',
      },
      {
        'id': 'pricing',
        'label': isHi ? 'उचित मूल्य' : 'Fair Pricing',
        'query': isHi ? 'सामान की कीमत कैसे तय होती है?' : 'How does fair pricing work?',
        'icon': 'currency_inr',
      },
      {
        'id': 'catalogue',
        'label': isHi ? 'माय कैटलॉग' : 'My Catalogue',
        'query': isHi ? 'माय कैटलॉग खोलें' : 'Take me to my catalogue',
        'icon': 'grid_view',
      },
      {
        'id': 'stats',
        'label': isHi ? 'मेरी कमाई व बिक्री' : 'My Stats & Sales',
        'query': isHi ? 'मेरी कमाई और बिक्री दिखाएं' : 'Where are my earnings and sales stats?',
        'icon': 'chart_bar',
      },
      {
        'id': 'language',
        'label': isHi ? 'भाषा बदलें' : 'Change Language',
        'query': isHi ? 'भाषा कैसे बदलें?' : 'How do I change the language?',
        'icon': 'translate',
      },
    ];
  }

  ChatMessageModel _generateOfflineReply(String query, String languageCode) {
    final q = query.toLowerCase().trim();
    final isHi = languageCode == 'hi' ||
        q.contains('kaise') ||
        q.contains('kahan') ||
        q.contains('mujhe') ||
        q.contains('saman') ||
        q.contains('hai');

    if (q.contains('add') || q.contains('naya') || q.contains('upload') || q.contains('bechna')) {
      return ChatMessageModel.assistant(
        text: isHi
            ? 'आप अपने उत्पाद को 5 चरणों में जोड़ सकते हैं: फ़ोटो खींचें, बोलकर विवरण दें, और उचित मूल्य तय करें।'
            : 'You can add your craft in 5 steps: take photos, record a voice description, review details, and calculate fair pricing.',
        action: ChatActionModel(
          type: 'navigate',
          destination: 'add_product',
          route: '/add-product',
          tabIndex: 0,
          label: isHi ? 'उत्पाद जोड़ें पर जाएं' : 'Go to Add Product',
        ),
        suggestedQueries: isHi
            ? ['मूल्य कैसे तय होता है?', 'कैटलॉग दिखाएं']
            : ['How does pricing work?', 'Show my catalogue'],
      );
    }

    if (q.contains('catalogue') || q.contains('items') || q.contains('stock') || q.contains('dukaan')) {
      return ChatMessageModel.assistant(
        text: isHi
            ? 'आप अपने सभी उत्पाद कैटलॉग स्क्रीन में देख सकते हैं।'
            : 'You can view and manage all your craft listings in the Catalogue screen.',
        action: ChatActionModel(
          type: 'navigate',
          destination: 'catalogue',
          route: '/catalogue',
          tabIndex: 1,
          label: isHi ? 'माय कैटलॉग खोलें' : 'Open My Catalogue',
        ),
        suggestedQueries: isHi
            ? ['नया सामान जोड़ें', 'कमाई दिखाएं']
            : ['Add a product', 'Show my stats'],
      );
    }

    if (q.contains('stat') || q.contains('kamai') || q.contains('earning') || q.contains('sale')) {
      return ChatMessageModel.assistant(
        text: isHi
            ? 'आप अपनी कुल बिक्री और कमाई माय स्टैट्स में देख सकते हैं।'
            : 'You can view your sales, listed items, and revenue breakdown in My Stats.',
        action: const ChatActionModel(
          type: 'navigate',
          destination: 'my_stats',
          route: '/my-stats',
          label: 'Open My Stats',
        ),
        suggestedQueries: isHi
            ? ['कैटलॉग खोलें', 'नया सामान जोड़ें']
            : ['Open catalogue', 'Add a product'],
      );
    }

    if (q.contains('language') || q.contains('bhasha')) {
      return ChatMessageModel.assistant(
        text: isHi
            ? 'आप ऐप की भाषा हिंदी, अंग्रेज़ी, तमिल या बांग्ला में बदल सकते हैं।'
            : 'You can switch the app language from Language Settings.',
        action: const ChatActionModel(
          type: 'navigate',
          destination: 'language_settings',
          route: '/language-settings',
          label: 'Language Settings',
        ),
      );
    }

    if (q.contains('price') || q.contains('kimat') || q.contains('keemat')) {
      return ChatMessageModel.assistant(
        text: isHi
            ? 'कलासेतु में मूल्य = कच्चा माल + (काम के घंटे × उचित मजदूरी) + बाज़ार का औसत मूल्य।'
            : 'KalaSetu Fair Pricing = Raw Materials + (Labor Hours × Fair Wage) + Market Benchmark Comparison.',
        action: ChatActionModel(
          type: 'navigate',
          destination: 'add_product',
          route: '/add-product',
          tabIndex: 0,
          label: isHi ? 'उत्पाद जोड़ें' : 'Go to Add Product',
        ),
      );
    }

    return ChatMessageModel.assistant(
      text: isHi
          ? 'नमस्ते! मैं कला-मित्र हूँ। मैं आपको उत्पाद जोड़ने, मूल्य निर्धारण करने और किसी भी स्क्रीन पर ले जाने में मदद कर सकता हूँ।'
          : 'Namaste! I am KalaMitra, your guide for KalaSetu. Ask me anything or ask me to take you to any screen!',
      suggestedQueries: isHi
          ? ['नया उत्पाद कैसे जोड़ें?', 'मूल्य निर्धारण कैसे होता है?', 'माय कैटलॉग खोलें', 'मेरी कमाई दिखाएं']
          : ['How to add a product?', 'How does fair pricing work?', 'Take me to my catalogue', 'Show my stats'],
    );
  }
}
