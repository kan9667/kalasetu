import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/core/widgets/motifs/mehrab_clipper.dart';
import 'package:kalasetu/data/models/chat_message.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/chat_service.dart';
import 'package:kalasetu/features/chatbot/providers/chat_provider.dart';
import 'package:kalasetu/features/chatbot/screens/chatbot_sheet.dart';
import 'package:kalasetu/features/chatbot/widgets/kalamitra_fab.dart';

class _FakeChatService implements ChatService {
  @override
  Future<List<Map<String, dynamic>>> getQuickTopics({String languageCode = 'en'}) async {
    return [
      {
        'id': 'schemes',
        'label': languageCode == 'hi' ? 'सरकारी योजनाएं' : 'Govt Schemes',
        'label_hi': 'सरकारी योजनाएं',
        'query': languageCode == 'hi' ? 'पीएम विश्वकर्मा योजना क्या है?' : 'What is PM Vishwakarma scheme?',
        'query_hi': 'पीएम विश्वकर्मा योजना क्या है?',
      }
    ];
  }

  @override
  Future<ChatMessageModel> sendMessage({
    required String message,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
    String? artisanCraft,
  }) async {
    return ChatMessageModel.assistant(text: 'Mock response');
  }

  @override
  Future<VoiceChatResult> sendVoiceMessage({
    required String audioPath,
    List<ChatMessageModel> history = const [],
    String languageCode = 'en',
    String? currentScreen,
    String? artisanCraft,
  }) async {
    return VoiceChatResult(
      userTranscript: 'voice question',
      assistantMessage: ChatMessageModel.assistant(text: 'Mock voice response'),
    );
  }
}

class _FakeUserProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return <String, Object>{};
        }
        return true;
      },
    );

    final tempDir = await Directory.systemTemp.createTemp('hive_kalamitra_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isBoxOpen('user_profile_box')) {
      await Hive.openBox<UserProfile>('user_profile_box');
    }
    if (!Hive.isBoxOpen('products_box')) {
      await Hive.openBox<Product>('products_box');
    }
    if (!Hive.isBoxOpen('pending_sync_box')) {
      await Hive.openBox<String>('pending_sync_box');
    }
  });

  group('KalaMitra FAB & Scalloped Bottom Sheet Tests', () {
    testWidgets('KalaMitraFab renders with consistent dimensions and triggers Mehrab sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWithValue(_FakeChatService()),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Meera Devi',
                phone: '+91 98765 43210',
                craftType: 'Blue Pottery',
                locationCluster: 'Jaipur',
                state: 'Rajasthan',
                preferredLanguage: 'en',
              ),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              floatingActionButton: KalaMitraFab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify FAB renders
      expect(find.byType(KalaMitraFab), findsOneWidget);
      expect(find.text('kalamitra_title'), findsOneWidget);

      // Tap FAB to open bottom sheet
      await tester.tap(find.byType(KalaMitraFab));
      await tester.pumpAndSettle();

      // Verify MehrabSheetContainer & MehrabClipper were used (scalloped top border treatment)
      expect(find.byType(MehrabSheetContainer), findsOneWidget);
      expect(find.byType(ChatbotSheet), findsOneWidget);
      expect(find.byType(ClipPath), findsWidgets);
    });

    testWidgets('Chatbot initial state localizes greeting and suggestion chips in Hindi', (tester) async {
      final fakeService = _FakeChatService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWithValue(fakeService),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Meera Devi',
                phone: '+91 98765 43210',
                craftType: 'Terracotta Pottery',
                locationCluster: 'Gorakhpur',
                state: 'Uttar Pradesh',
                preferredLanguage: 'hi',
              ),
            )),
          ],
          child: MaterialApp(
            locale: const Locale('hi'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => ChatbotSheet.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check Hindi welcome message and Hindi suggestions
      expect(find.textContaining('शिल्प व बाज़ार सहायक'), findsOneWidget);
      expect(find.text('पीएम विश्वकर्मा योजना क्या है?'), findsOneWidget);
      expect(find.text('टेराकोटा में दरारें कैसे रोकें?'), findsOneWidget);
      expect(find.text('माय कैटलॉग खोलें'), findsOneWidget);
    });

    testWidgets('Chatbot initial state localizes greeting and suggestion chips in English', (tester) async {
      final fakeService = _FakeChatService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWithValue(fakeService),
            userProfileProvider.overrideWith((ref) => _FakeUserProfileNotifier(
              UserProfile(
                id: 'artisan-1',
                name: 'Meera Devi',
                phone: '+91 98765 43210',
                craftType: 'Terracotta Pottery',
                locationCluster: 'Gorakhpur',
                state: 'Uttar Pradesh',
                preferredLanguage: 'en',
              ),
            )),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => ChatbotSheet.show(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check English welcome message and English suggestions
      expect(find.textContaining('artisan assistant and market guide'), findsOneWidget);
      expect(find.text('What is PM Vishwakarma scheme?'), findsOneWidget);
      expect(find.text('How to avoid cracks in terracotta pottery?'), findsOneWidget);
      expect(find.text('Take me to my catalogue'), findsOneWidget);
    });
  });
}
