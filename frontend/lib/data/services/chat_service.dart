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
    String? artisanCraft,
  });

  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    String languageCode = 'en',
    String? currentScreen,
    String? artisanCraft,
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
    String? artisanCraft,
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
        if (artisanCraft != null && artisanCraft.isNotEmpty) 'artisan_craft': artisanCraft,
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
    return _generateOfflineReply(message, languageCode, artisanCraft: artisanCraft);
  }

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    String languageCode = 'en',
    String? currentScreen,
    String? artisanCraft,
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
      if (artisanCraft != null && artisanCraft.isNotEmpty) {
        formData.fields.add(MapEntry('artisan_craft', artisanCraft));
      }

      debugPrint('[HttpChatService] POST $activeUrl/api/v1/chat/voice (lang: $languageCode, craft: $artisanCraft)');
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
      final response = await _dio.get(
        '/api/v1/chat/quick-topics',
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final list = data['topics'] as List<dynamic>?;
        if (list != null) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('[HttpChatService] Quick topics fetch timed out or offline ($e). Using local fallback topics.');
    }

    // Default fallback topics
    final isHi = languageCode == 'hi';
    return [
      {
        'id': 'schemes',
        'label': isHi ? 'सरकारी योजनाएं (विश्वकर्मा)' : 'Govt Schemes & Mudra',
        'query': isHi ? 'पीएम विश्वकर्मा योजना और कारीगर योजनाओं से क्या लाभ मिलेगा?' : 'What benefits do I get under PM Vishwakarma and artisan schemes?',
        'icon': 'account_balance',
      },
      {
        'id': 'craft_advice',
        'label': isHi ? 'शिल्प सुधार के सुझाव' : 'Improve My Craft',
        'query': isHi ? 'अपने शिल्प की गुणवत्ता और डिज़ाइन कैसे बेहतर करें?' : 'How can I improve the quality and modern appeal of my craft?',
        'icon': 'auto_awesome',
      },
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

  ChatMessageModel _generateOfflineReply(String query, String languageCode, {String? artisanCraft}) {
    final q = query.toLowerCase().trim();
    final isDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(query);
    final isQueryHindi = isDevanagari ||
        q.contains('kaise') ||
        q.contains('kahan') ||
        q.contains('mujhe') ||
        q.contains('saman') ||
        q.contains('mera') ||
        q.contains('meri') ||
        q.contains('batao') ||
        q.contains('karo') ||
        q.contains('hai');

    final isLangMismatch = (languageCode == 'en' && isQueryHindi) || (languageCode == 'hi' && !isQueryHindi && !isDevanagari);
    final suggestionPrefix = isLangMismatch
        ? (isQueryHindi
            ? 'सुझाव: यदि आप कलासेतु ऐप की भाषा हिंदी में बदलना चाहते हैं, तो आप भाषा सेटिंग्स में जाकर इसे बदल सकते हैं।\n\n'
            : 'Suggestion: If you prefer using KalaSetu in English, you can switch the app language in Language Settings.\n\n')
        : '';

    final defaultMismatchAction = isLangMismatch
        ? ChatActionModel(
            type: 'navigate',
            destination: 'language_settings',
            route: '/language-settings',
            label: isQueryHindi ? 'भाषा सेटिंग्स खोलें' : 'Open Language Settings',
          )
        : null;

    final craftLower = (artisanCraft ?? '').toLowerCase();
    final isWoodProfile = craftLower.contains('wood') || craftLower.contains('carv');
    final isTextileProfile = craftLower.contains('textile') || craftLower.contains('handloom') || craftLower.contains('weav');
    final isMetalProfile = craftLower.contains('metal') || craftLower.contains('brass');
    final isExplicitOther = q.contains('brass') || q.contains('wood') || q.contains('saree') || q.contains('textile') || q.contains('pottery');

    if (q.contains('vishwakarma') || q.contains('mudra') || q.contains('pehchan') || q.contains('yojana') || q.contains('scheme') || q.contains('subsidy')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'कारीगरों के लिए मुख्य सरकारी योजनाएं:\n\n1. पीएम विश्वकर्मा योजना: ₹15,000 टूलकिट सहायता और मात्र 5% रियायती ब्याज पर ₹3 लाख तक का उद्यम ऋण।\n2. पहचान कार्ड: वस्त्र मंत्रालय का आधिकारिक कार्ड, राष्ट्रीय हाट और मेलों में प्रदर्शनी की पात्रता।\n3. मुद्रा योजना: ₹50,000 से ₹5 लाख तक का आसान ऋण।'
                : 'Key Government Schemes for Artisans:\n\n1. PM Vishwakarma: Rs 15,000 toolkit incentive and up to Rs 3 Lakh collateral-free enterprise loan at subsidized 5% interest.\n2. Pehchan Artisan Card: Ministry of Textiles official ID card, eligibility for national exhibitions & craft haats.\n3. MUDRA Loans: Micro-credit from Rs 50,000 to Rs 5 Lakh for working capital.'),
        action: defaultMismatchAction,
        suggestedQueries: isQueryHindi
            ? ['शिल्प सुधार के सुझाव', 'मूल्य कैसे तय होता है?', 'माय कैटलॉग खोलें']
            : ['How to improve craft quality?', 'How does pricing work?', 'Show my catalogue'],
      );
    }

    if (q.contains('improve') || q.contains('quality') || q.contains('design') || q.contains('glaze') || q.contains('kiln') || q.contains('crack') || q.contains('darar')) {
      String craftAdviceHi;
      String craftAdviceEn;
      List<String> suggestedHi;
      List<String> suggestedEn;

      if (!isExplicitOther && isTextileProfile) {
        craftAdviceHi = 'हथकरघा व वस्त्र गुणवत्ता सुधार के सुझाव:\n\n• ताने का खिंचाव (Warp Tension) एकसमान रखें ताकि धागे टूटने और किनारों के मुड़ने से बचाव हो।\n• प्राकृतिक रंगों (नील, मजीठ) में फिटकरी का सही अनुपात मिलाएं ताकि रंग पक्का रहे।\n• कपड़ों को वाटरप्रूफ इनर पैकिंग और सिलिका जेल के साथ सुरक्षित पैक करें।';
        craftAdviceEn = 'Handloom & Textile Quality Improvement Tips:\n\n• Maintain uniform warp tension across the loom to prevent thread breakage and rippling.\n• Use precise mineral mordants (alum) with natural dyes for permanent colorfastness.\n• Wrap textiles in acid-free tissue with waterproof layer and silica gel for transit.';
        suggestedHi = ['बुनकरों के लिए सरकारी योजनाएं', 'बाज़ार के रुझान', 'नया उत्पाद जोड़ें'];
        suggestedEn = ['Govt schemes for weavers', 'Handicraft market trends', 'Add a product'];
      } else if (!isExplicitOther && isWoodProfile) {
        craftAdviceHi = 'काष्ठ नक्काशी गुणवत्ता सुधार के सुझाव:\n\n• हमेशा 8-12% नमी वाली भट्ठी में सुखाई गई (Seasoned) लकड़ी चुनें ताकि मुड़ने व दरार से बचाव हो।\n• नक्काशी से पहले पर्यावरण-अनुकूल एंटी-टर्माइट प्राइमर लगाएं।\n• छेनी की धार तेज़ रखें और प्राकृतिक मोम (Beeswax) की पॉलिश करें।';
        craftAdviceEn = 'Woodwork Quality Improvement Tips:\n\n• Use kiln-seasoned timber (8-12% moisture) to prevent seasonal warping and cracks.\n• Treat with eco-friendly anti-borer solutions before detailed carving.\n• Keep chisels razor-sharp and finish with pure beeswax polish.';
        suggestedHi = ['बढ़ई वर्ग के लिए टूलकिट सहायता', 'बाज़ार के रुझान', 'नया उत्पाद जोड़ें'];
        suggestedEn = ['PM Vishwakarma for carpenters', 'Handicraft market trends', 'Add a product'];
      } else if (!isExplicitOther && isMetalProfile) {
        craftAdviceHi = 'धातुशिल्प व पीतल कार्य सुधार के सुझाव:\n\n• ढलाई से पहले सांचे को गर्म करें ताकि हवा के बुलबुले न बनें।\n• कालेपन से बचाने के लिए माइक्रोक्रिस्टलाइन मोम या क्लियर लैकर लगाएं।\n• इमली के घोल से सफाई के बाद मुलायम कपड़े से बफिंग करें।';
        craftAdviceEn = 'Metalcraft & Brassware Quality Tips:\n\n• Preheat molds before pouring molten metal to avoid air pockets and surface voids.\n• Apply micro-crystalline protective wax to prevent atmospheric oxidation.\n• Clean with mild tamarind solution and buff using a soft felt wheel.';
        suggestedHi = ['धातु शिल्पकारों के लिए योजनाएं', 'बाज़ार के रुझान', 'नया उत्पाद जोड़ें'];
        suggestedEn = ['Govt schemes for metalcraft', 'Handicraft market trends', 'Add a product'];
      } else {
        craftAdviceHi = 'टेराकोटा व शिल्प गुणवत्ता सुधार के सुझाव:\n\n• मिट्टी व टेराकोटा में दरार रोकने के लिए छाया में धीरे-धीरे सुखाएं (Slow Air Drying)।\n• भट्ठी का तापमान धीरे-धीरे बढ़ाएं और पकाने के बाद 12-16 घंटे प्राकृतिक रूप से ठंडा होने दें।\n• कूरियर शिपिंग के लिए डबल-वॉल बॉक्स व हनीकॉम्ब पैडिंग का उपयोग करें।';
        craftAdviceEn = 'Terracotta & Pottery Quality Improvement Tips:\n\n• Always slow-dry terracotta in the shade to prevent warping and hairline cracking.\n• Ramp up kiln temperature gradually and allow natural cooling for 12-16 hours.\n• Use sturdy double-wall packaging and honeycomb padding for safe courier transit.';
        suggestedHi = ['कुम्हारों के लिए सरकारी योजनाएं', 'बाज़ार के रुझान', 'नया उत्पाद जोड़ें'];
        suggestedEn = ['PM Vishwakarma for potters', 'Handicraft market trends', 'Add a product'];
      }

      return ChatMessageModel.assistant(
        text: suggestionPrefix + (isQueryHindi ? craftAdviceHi : craftAdviceEn),
        action: defaultMismatchAction,
        suggestedQueries: isQueryHindi ? suggestedHi : suggestedEn,
      );
    }

    if (q.contains('market') || q.contains('bazar') || q.contains('mela') || q.contains('haat') || q.contains('surajkund') || q.contains('trend')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'बाज़ार के ताज़ा रुझान और मेले:\n\n• प्राकृतिक, हस्तनिर्मित और पर्यावरण-अनुकूल उत्पादों की शहरी बाज़ारों में अत्यधिक मांग है।\n• प्रमुख मेले: सूरजकुंड अंतरराष्ट्रीय शिल्प मेला, दिल्ली हाट, सरस आजीविका मेला, गांधी शिल्प बाज़ार।\n• जीआई टैग (GI Tag) वाले शिल्पों को 20-30% अधिक मूल्य मिलता है।'
                : 'Market Trends & Craft Melas:\n\n• Strong consumer demand for sustainable, eco-friendly lifestyle crafts and authentic artisan stories.\n• Key Exhibitions: Surajkund International Crafts Mela, Dilli Haat, SARAS Mela, Gandhi Shilp Bazaar.\n• Regional GI Tag certification commands premium export pricing.'),
        action: defaultMismatchAction,
        suggestedQueries: isQueryHindi
            ? ['पीएम विश्वकर्मा योजना', 'उचित मूल्य कैसे तय करें?', 'कैटलॉग खोलें']
            : ['PM Vishwakarma details', 'How does pricing work?', 'Open catalogue'],
      );
    }

    if (q.contains('add') || q.contains('naya') || q.contains('upload') || q.contains('bechna')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'आप अपने उत्पाद को 5 चरणों में जोड़ सकते हैं: फ़ोटो खींचें, बोलकर विवरण दें, और उचित मूल्य तय करें।'
                : 'You can add your craft in 5 steps: take photos, record a voice description, review details, and calculate fair pricing.'),
        action: ChatActionModel(
          type: 'navigate',
          destination: 'add_product',
          route: '/add-product',
          tabIndex: 0,
          label: isQueryHindi ? 'उत्पाद जोड़ें पर जाएं' : 'Go to Add Product',
        ),
        suggestedQueries: isQueryHindi
            ? ['मूल्य कैसे तय होता है?', 'कैटलॉग दिखाएं']
            : ['How does pricing work?', 'Show my catalogue'],
      );
    }

    if (q.contains('catalogue') || q.contains('items') || q.contains('stock') || q.contains('dukaan')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'आप अपने सभी उत्पाद कैटलॉग स्क्रीन में देख सकते हैं।'
                : 'You can view and manage all your craft listings in the Catalogue screen.'),
        action: ChatActionModel(
          type: 'navigate',
          destination: 'catalogue',
          route: '/catalogue',
          tabIndex: 1,
          label: isQueryHindi ? 'माय कैटलॉग खोलें' : 'Open My Catalogue',
        ),
        suggestedQueries: isQueryHindi
            ? ['नया सामान जोड़ें', 'कमाई दिखाएं']
            : ['Add a product', 'Show my stats'],
      );
    }

    if (q.contains('stat') || q.contains('kamai') || q.contains('earning') || q.contains('sale')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'आप अपनी कुल बिक्री और कमाई माय स्टैट्स में देख सकते हैं।'
                : 'You can view your sales, listed items, and revenue breakdown in My Stats.'),
        action: ChatActionModel(
          type: 'navigate',
          destination: 'my_stats',
          route: '/my-stats',
          label: isQueryHindi ? 'मेरी कमाई दिखाएं' : 'Open My Stats',
        ),
        suggestedQueries: isQueryHindi
            ? ['कैटलॉग खोलें', 'नया सामान जोड़ें']
            : ['Open catalogue', 'Add a product'],
      );
    }

    if (q.contains('language') || q.contains('bhasha')) {
      return ChatMessageModel.assistant(
        text: isQueryHindi
            ? 'आप ऐप की भाषा हिंदी, अंग्रेज़ी, तमिल या बांग्ला में बदल सकते हैं।'
            : 'You can switch the app language from Language Settings.',
        action: ChatActionModel(
          type: 'navigate',
          destination: 'language_settings',
          route: '/language-settings',
          label: isQueryHindi ? 'भाषा सेटिंग्स खोलें' : 'Language Settings',
        ),
      );
    }

    if (q.contains('price') || q.contains('kimat') || q.contains('keemat')) {
      return ChatMessageModel.assistant(
        text: suggestionPrefix +
            (isQueryHindi
                ? 'कलासेतु में मूल्य = कच्चा माल + (काम के घंटे × उचित मजदूरी) + बाज़ार का औसत मूल्य।'
                : 'KalaSetu Fair Pricing = Raw Materials + (Labor Hours × Fair Wage) + Market Benchmark Comparison.'),
        action: ChatActionModel(
          type: 'navigate',
          destination: 'add_product',
          route: '/add-product',
          tabIndex: 0,
          label: isQueryHindi ? 'उत्पाद जोड़ें' : 'Go to Add Product',
        ),
      );
    }

    return ChatMessageModel.assistant(
      text: suggestionPrefix +
          (isQueryHindi
              ? 'नमस्ते! मैं कला-मित्र हूँ, आपका शिल्प व बाज़ार सहायक। मैं आपको उत्पाद जोड़ने, मूल्य निर्धारण, सरकारी योजनाओं और किसी भी स्क्रीन पर ले जाने में मदद कर सकता हूँ।'
              : 'Namaste! I am KalaMitra, your artisan assistant and guide for KalaSetu. Ask me about craft improvement, govt schemes, pricing, or ask me to take you to any screen!'),
      action: defaultMismatchAction,
      suggestedQueries: isQueryHindi
          ? ['पीएम विश्वकर्मा योजना क्या है?', 'शिल्प सुधार के सुझाव', 'माय कैटलॉग खोलें', 'मेरी कमाई दिखाएं']
          : ['What is PM Vishwakarma scheme?', 'How to improve craft quality?', 'Take me to my catalogue', 'Show my stats'],
    );
  }
}
