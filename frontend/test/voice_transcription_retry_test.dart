import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/request_session_context.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/pricing_service.dart';
import 'package:kalasetu/data/services/speech_service.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';
import 'package:kalasetu/features/add_product/widgets/step2_describe_widget.dart';
import 'package:kalasetu/features/add_product/widgets/step3_ai_review_widget.dart';
import 'package:kalasetu/data/models/ai_operation_record.dart';

class MockPricingServiceProbe extends MockPricingService {
  @override
  Future<PriceSuggestion> suggestPrice({
    String? description,
    required String category,
    required List<String> tags,
    String? imageUrl,
    double? rawMaterialCost,
    double? laborHours,
    double? hourlyWage,
    String? idempotencyKey,
  }) async {
    return const PriceSuggestion(
      minPrice: 100,
      maxPrice: 500,
      suggestedPrice: 300,
      floorPrice: 100,
      reasoning: 'fair price',
      reasoningHi: 'उचित मूल्य',
    );
  }
}

class FakeAuthNotifier extends StateNotifier<AuthState> implements AuthNotifier {
  FakeAuthNotifier(super.state);

  void overrideUser(String userId) => state = state.copyWith(userId: userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControllableSpeechService implements SpeechService {
  int transcribeAudioCallCount = 0;
  int generateListingCallCount = 0;
  final List<String?> transcribeIdempotencyKeys = [];
  final List<String?> listingIdempotencyKeys = [];
  Completer<void>? transcribeDelayCompleter;
  Completer<void>? listingDelayCompleter;

  TranscriptionResult? transcribeResultToReturn;
  Exception? transcribeExceptionToThrow;

  AiListingSuggestion? listingResultToReturn;
  Exception? listingExceptionToThrow;

  final List<RequestSessionContext?> capturedTranscribeSessionContexts = [];
  final List<RequestSessionContext?> capturedListingSessionContexts = [];

  @override
  Future<TranscriptionResult> transcribeAudio({
    required String audioPath,
    required String languageCode,
    String? idempotencyKey,
    RequestSessionContext? sessionContext,
  }) async {
    transcribeAudioCallCount++;
    transcribeIdempotencyKeys.add(idempotencyKey);
    capturedTranscribeSessionContexts.add(sessionContext);

    if (transcribeDelayCompleter != null) {
      await transcribeDelayCompleter!.future;
    }

    if (transcribeExceptionToThrow != null) {
      throw transcribeExceptionToThrow!;
    }

    return transcribeResultToReturn ??
        const TranscriptionResult(
          transcript: 'मिट्टी का घड़ा',
          confidence: 0.95,
          statusCode: TranscriptionStatusCode.success,
        );
  }

  @override
  Future<AiListingSuggestion> generateListingFromTranscript({
    required String transcript,
    required String languageCode,
    String? categoryHint,
    String? idempotencyKey,
    RequestSessionContext? sessionContext,
  }) async {
    generateListingCallCount++;
    listingIdempotencyKeys.add(idempotencyKey);
    capturedListingSessionContexts.add(sessionContext);

    if (listingDelayCompleter != null) {
      await listingDelayCompleter!.future;
    }

    if (listingExceptionToThrow != null) {
      throw listingExceptionToThrow!;
    }

    return listingResultToReturn ??
        const AiListingSuggestion(
          titleEn: 'Clay Pot',
          titleHi: 'मिट्टी का घड़ा',
          descriptionEn: 'Traditional clay pot made from natural riverbed clay.',
          descriptionHi: 'नदी की प्राकृतिक मिट्टी से बना पारंपरिक मिट्टी का घड़ा।',
          category: 'Pottery',
          tags: ['clay', 'pottery', 'handcrafted'],
          rawMaterialCost: 150.0,
          laborHours: 3.0,
          hourlyRate: 60.0,
          floorPrice: 330.0,
        );
  }
}

class FakeAddProductFlowNotifier extends StateNotifier<AddProductDraft>
    implements AddProductFlowNotifier {
  FakeAddProductFlowNotifier(super.state);

  int transcribeCalls = 0;
  int retryListingCalls = 0;

  @override
  Future<void> transcribeVoiceDirectly(File audioFile, {String languageCode = 'auto'}) async {
    transcribeCalls++;
  }

  @override
  Future<void> retryListingGeneration({String languageCode = 'auto'}) async {
    retryListingCalls++;
  }

  @override
  Future<void> setManualDescription(String text) async {
    state = state.copyWith(manualDescription: text);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<int> dummyM4aBytes([int length = 256, int fill = 42]) => [
  0x00, 0x00, 0x00, 0x20,
  0x66, 0x74, 0x79, 0x70, // 'ftyp'
  0x4d, 0x34, 0x41, 0x20, // 'M4A '
  ...List.filled(length > 12 ? length - 12 : 0, fill),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late ProviderContainer container;
  late ControllableSpeechService speechService;
  late MockPricingServiceProbe pricingService;
  late FakeAuthNotifier authNotifier;
  late File sampleAudioFile;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return <String, Object>{};
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'init') {
          return {'id': 'test_player'};
        }
        return {};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall methodCall) async {
        return true;
      },
    );
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kalasetu_voice_retry_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());

    final authBox = await Hive.openBox('auth_box');
    await authBox.put('user_id', 'artisan_voice_tester');
    await authBox.put('phone_number', '+919876543213');
    await authBox.put('is_authenticated', true);

    await Hive.openBox('draft_box');
    await Hive.openBox<String>('ai_operations_box');
    await Hive.openBox<UserProfile>('user_profile_box');
    await Hive.openBox<Product>('products_box');

    // Create a real audio file on disk with valid M4A container bytes
    sampleAudioFile = File('${tempDir.path}/sample_note.m4a');
    await sampleAudioFile.writeAsBytes(dummyM4aBytes(256, 42));

    speechService = ControllableSpeechService();
    pricingService = MockPricingServiceProbe();

    authNotifier = FakeAuthNotifier(const AuthState(
      isAuthenticated: true,
      userId: 'artisan_voice_tester',
      phoneNumber: '+919876543213',
    ));

    container = ProviderContainer(overrides: [
      speechServiceProvider.overrideWithValue(speechService),
      pricingServiceProvider.overrideWithValue(pricingService),
      authStateProvider.overrideWith((ref) => authNotifier),
    ]);
  });

  tearDown(() async {
    final flow = container.read(addProductFlowProvider.notifier);
    await flow.awaitActiveBackgroundFutures();
    container.dispose();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Voice Transcription Flow & Single-Flight Retry Tests', () {
    test('REVIEW busy state clears after successful voice flow', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_busy', originalImagePath: '', enhancedImagePath: '', transcript: '');
      await flow.transcribeVoiceDirectly(sampleAudioFile);
      expect(container.read(addProductFlowProvider).isAiProcessing, isFalse,
        reason: 'Completed transcription/listing must clear the busy flag');
    });

    test('REVIEW changed bytes with same file metadata require a new key', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_identity', originalImagePath: '', enhancedImagePath: '', transcript: '');
      speechService.transcribeExceptionToThrow = const TranscriptionException('Unavailable', statusCode: TranscriptionStatusCode.serviceUnavailable);
      final modified = sampleAudioFile.lastModifiedSync();
      await flow.transcribeVoiceDirectly(sampleAudioFile);
      final firstKey = speechService.transcribeIdempotencyKeys.single;
      await sampleAudioFile.writeAsBytes(dummyM4aBytes(256, 43), flush: true);
      await sampleAudioFile.setLastModified(modified);
      await flow.transcribeVoiceDirectly(sampleAudioFile);
      expect(speechService.transcribeIdempotencyKeys.last, isNot(firstKey),
        reason: 'Different audio bytes must not reuse the earlier idempotency key');
    });

    test('REVIEW UI timeout does not release an active network flight', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_timeout', originalImagePath: '', enhancedImagePath: '', transcript: '');
      speechService.transcribeDelayCompleter = Completer<void>();
      await flow.transcribeVoiceDirectly(sampleAudioFile);
      final retry = flow.transcribeVoiceDirectly(sampleAudioFile);
      // A duplicate call must return immediately while the original network future is unresolved.
      try {
        await retry.timeout(const Duration(seconds: 1), onTimeout: () {});
        expect(speechService.transcribeAudioCallCount, 1,
          reason: 'UI timeout must not admit a second call while the first network future remains unresolved');
      } finally {
        speechService.transcribeDelayCompleter!.complete();
        await retry;
      }
    });

    test('Busy flag isAiProcessing clears on failure exit', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'fail_busy_test', originalImagePath: '', enhancedImagePath: '', transcript: '');
      speechService.transcribeExceptionToThrow = const TranscriptionException(
        'Server Error',
        statusCode: TranscriptionStatusCode.serviceUnavailable,
      );
      await flow.transcribeVoiceDirectly(sampleAudioFile);
      expect(container.read(addProductFlowProvider).isAiProcessing, isFalse,
        reason: 'Failed transcription must clear the busy flag');
    });

    test('Busy flag isAiProcessing clears on missing file exit', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'missing_busy_test', originalImagePath: '', enhancedImagePath: '', transcript: '');
      final missingFile = File('${tempDir.path}/absent_audio.m4a');
      await flow.transcribeVoiceDirectly(missingFile);
      expect(container.read(addProductFlowProvider).isAiProcessing, isFalse,
        reason: 'Missing audio file exit must clear the busy flag');
    });

    test('Busy flag isAiProcessing clears on stale-result exit', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'stale_busy_test_1', originalImagePath: '', enhancedImagePath: '', transcript: '');
      speechService.transcribeDelayCompleter = Completer<void>();
      final flight = flow.transcribeVoiceDirectly(sampleAudioFile);
      // Switch draft to render first flight stale
      await flow.loadSavedDraftState(draftId: 'stale_busy_test_2', originalImagePath: '', enhancedImagePath: '', transcript: '');
      speechService.transcribeDelayCompleter!.complete();
      await flight;
      expect(container.read(addProductFlowProvider).isAiProcessing, isFalse,
        reason: 'Stale result exit must clear the busy flag');
    });
    test('Duplicate transcribeVoiceDirectly while in-flight is locked and ignored', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_lock_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      // Set delay so first call stays in flight
      speechService.transcribeDelayCompleter = Completer<void>();

      // Launch first transcription call
      final firstFuture = flow.transcribeVoiceDirectly(sampleAudioFile);

      // Attempt second duplicate call immediately while first is in flight
      await flow.transcribeVoiceDirectly(sampleAudioFile);

      // Complete the delay and await first future
      speechService.transcribeDelayCompleter!.complete();
      await firstFuture;

      // Verify transcribeAudio was called only ONCE in total, not twice!
      expect(speechService.transcribeAudioCallCount, 1);
    });

    test('Durable draft persistence precedes network dispatch with deterministic opId', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_durable_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeDelayCompleter = Completer<void>();

      final future = flow.transcribeVoiceDirectly(sampleAudioFile);

      // Wait a microtask for persistence before network completes
      await Future.delayed(const Duration(milliseconds: 20));

      // Read snapshot from Hive draft_box
      final draftBox = Hive.box('draft_box');
      final rawSnapshot = draftBox.get(AddProductFlowNotifier.snapshotKey) as String?;
      expect(rawSnapshot, isNotNull);
      final snapshot = jsonDecode(rawSnapshot!) as Map<String, dynamic>;
      expect(snapshot['voice_listing_op_id'], isNotNull);
      expect(snapshot['voice_fingerprint'], isNotNull);
      expect(snapshot['voice_listing_op_id'].toString(), startsWith('voice_draft_durable_test_'));

      speechService.transcribeDelayCompleter!.complete();
      await future;

      final draft = container.read(addProductFlowProvider);
      expect(draft.voiceTranscript, 'मिट्टी का घड़ा');
      expect(draft.voiceDegradedCode, VoiceDegradedCode.none);
    });

    test('Missing audio file on disk fails safely without network call', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_missing_audio',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      final missingFile = File('${tempDir.path}/non_existent.m4a');
      await flow.transcribeVoiceDirectly(missingFile);

      expect(speechService.transcribeAudioCallCount, 0);

      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
      expect(draft.voiceDegradedReason, 'Recording file missing on disk');
    });

    test('ServiceUnavailable (503) sets typed degradation and preserves recording file', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_503_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeExceptionToThrow = const TranscriptionException(
        'Voice transcription service temporarily unavailable.',
        statusCode: TranscriptionStatusCode.serviceUnavailable,
        httpStatusCode: 503,
      );

      await flow.transcribeVoiceDirectly(sampleAudioFile);

      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.serviceUnavailable);
      expect(draft.voiceDegradedReason, 'Transcription failed—retry');
      expect(sampleAudioFile.existsSync(), isTrue, reason: 'Recording file must be preserved');
    });

    test('Network/Service timeout sets timedOut code and degradation reason', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_timeout_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeExceptionToThrow = const TranscriptionException(
        'Transcription connection timed out',
        statusCode: TranscriptionStatusCode.timedOut,
      );

      await flow.transcribeVoiceDirectly(sampleAudioFile);

      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.timedOut);
      expect(draft.voiceDegradedReason, 'Transcription failed—retry');
    });

    test('Genuine silence detection returns noSpeech code without error banner', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_silence_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeResultToReturn = const TranscriptionResult(
        transcript: '',
        confidence: 0.0,
        statusCode: TranscriptionStatusCode.noSpeech,
      );

      await flow.transcribeVoiceDirectly(sampleAudioFile);

      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.noSpeech);
      expect(draft.voiceDegradedReason, 'Transcription returned no audible speech.');
      expect(draft.voiceTranscript, isEmpty);
    });

    test('Late result is discarded if voice input generation or draft changes', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_stale_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeDelayCompleter = Completer<void>();

      final future = flow.transcribeVoiceDirectly(sampleAudioFile);

      // User retakes voice while in-flight
      final newAudioFile = File('${tempDir.path}/new_note.m4a');
      await newAudioFile.writeAsBytes(dummyM4aBytes(128, 99));
      await flow.queueVoiceRecording(newAudioFile);

      // Now complete the slow earlier call
      speechService.transcribeDelayCompleter!.complete();
      await future;

      final draft = container.read(addProductFlowProvider);
      // The transcript from earlier call ('मिट्टी का घड़ा') should NOT be applied
      expect(draft.voiceTranscript, isNot('मिट्टी का घड़ा'));
    });

    test('Successful transcription is preserved when subsequent listing generation fails', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_listing_fail_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      speechService.transcribeResultToReturn = const TranscriptionResult(
        transcript: 'हाथ से बना टेराकोटा वास',
        confidence: 0.95,
        statusCode: TranscriptionStatusCode.success,
      );

      speechService.listingExceptionToThrow = Exception('503 Service Unavailable for LLM listing');

      await flow.transcribeVoiceDirectly(sampleAudioFile);
      await flow.awaitActiveBackgroundFutures();

      final draft = container.read(addProductFlowProvider);
      // Voice transcription succeeded and MUST be preserved!
      expect(draft.voiceTranscript, 'हाथ से बना टेराकोटा वास');
      expect(draft.isVoiceDegraded, isFalse);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.none);

      // Listing generation failed
      expect(draft.isListingDegraded, isTrue);
      expect(draft.listingDegradedReason, 'Listing generation failed');

      // Now retry listing generation directly from preserved transcript
      speechService.listingExceptionToThrow = null; // Clear failure
      final initialTranscribeCalls = speechService.transcribeAudioCallCount;

      await flow.retryListingGeneration();

      expect(speechService.transcribeAudioCallCount, initialTranscribeCalls,
          reason: 'Must NOT retranscribe audio when retrying listing generation');
      expect(speechService.generateListingCallCount, 2);

      final retriedDraft = container.read(addProductFlowProvider);
      expect(retriedDraft.titleEn, 'Clay Pot');
      expect(retriedDraft.isListingDegraded, isFalse);
    });

    test('Safe Retry reuses deterministic key for unchanged input', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_retry_key_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      // First attempt fails
      speechService.transcribeExceptionToThrow = const TranscriptionException(
        'Server error',
        statusCode: TranscriptionStatusCode.serviceUnavailable,
      );

      await flow.transcribeVoiceDirectly(sampleAudioFile);
      expect(speechService.transcribeIdempotencyKeys.length, 1);
      final key1 = speechService.transcribeIdempotencyKeys[0];

      // Second attempt (retry) with unchanged audio file
      speechService.transcribeExceptionToThrow = null;
      await flow.transcribeVoiceDirectly(sampleAudioFile);

      expect(speechService.transcribeIdempotencyKeys.length, 2);
      final key2 = speechService.transcribeIdempotencyKeys[1];

      expect(key2, equals(key1), reason: 'Unchanged audio input must reuse the same idempotency key');
    });

    test('Restart between transcription success and listing completion preserves transcript and pending work', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      // Perform successful transcription
      speechService.transcribeResultToReturn = const TranscriptionResult(
        transcript: 'हाथ की कढ़ाई वाली साड़ी',
        confidence: 0.98,
        statusCode: TranscriptionStatusCode.success,
      );

      // Listing generation fails / throws network error
      speechService.listingExceptionToThrow = const SocketException('Connection lost during listing generation');

      await flow.transcribeVoiceDirectly(sampleAudioFile);
      await flow.awaitActiveBackgroundFutures();

      final preRestartDraft = container.read(addProductFlowProvider);
      expect(preRestartDraft.voiceTranscript, 'हाथ की कढ़ाई वाली साड़ी');
      expect(preRestartDraft.listingStatus, 'failed');

      // Now simulate app restart / rehydrating the saved draft
      final newDraft = AddProductDraft(
        draftId: 'draft_restart_test',
        voiceTranscript: 'हाथ की कढ़ाई वाली साड़ी',
        recordedAudioPath: preRestartDraft.recordedAudioPath,
        immutableAudioSnapshotPath: preRestartDraft.immutableAudioSnapshotPath,
        listingStatus: 'failed',
        listingInputGeneration: preRestartDraft.listingInputGeneration,
      );

      // Save operation record simulating completed listing operation that arrived in background
      final record = AiOperationRecord(
        id: 'listing_draft_restart_test_g1_abcdef1234567890',
        idempotencyKey: 'listing_draft_restart_test_g1_abcdef1234567890',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'listing_generate',
        draftId: 'draft_restart_test',
        inputGeneration: 1,
        inputFingerprint: 'abcdef1234567890',
        requestSnapshot: {'transcript': 'हाथ की कढ़ाई वाली साड़ी'},
        status: AiOperationRecord.statusCompleted,
        resultData: {
          'title_en': 'Hand Embroidered Saree',
          'title_hi': 'हाथ की कढ़ाई वाली साड़ी',
          'description_en': 'Traditional hand embroidered silk saree.',
          'description_hi': 'पारंपरिक हाथ की कढ़ाई वाली रेशमी साड़ी।',
          'category': 'Textiles',
          'tags': ['saree', 'embroidery'],
          'status': 'success',
          'is_degraded': false,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await AiOperationStorage.save(record);

      // Resume draft
      await flow.loadSavedDraftState(
        draftId: newDraft.draftId,
        originalImagePath: newDraft.originalImagePath,
        enhancedImagePath: newDraft.enhancedImagePath,
        transcript: newDraft.voiceTranscript,
        recordedAudioPath: newDraft.recordedAudioPath,
        immutableAudioSnapshotPath: newDraft.immutableAudioSnapshotPath,
        listingStatus: newDraft.listingStatus,
        listingInputGeneration: newDraft.listingInputGeneration,
      );
      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      final rehydrated = container.read(addProductFlowProvider);
      expect(rehydrated.voiceTranscript, 'हाथ की कढ़ाई वाली साड़ी', reason: 'Transcript must be preserved on restart');
      expect(rehydrated.titleEn, 'Hand Embroidered Saree');
      expect(rehydrated.listingStatus, 'success');
      expect(speechService.transcribeAudioCallCount, 1, reason: 'Must not create duplicate transcription request on restart');
    });

    test('Hindi edits, cost edits, and edit-then-revert are protected against late response', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_edits_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'कच्ची मिट्टी का खिलौना',
      );

      // Controlled delay for listing response
      speechService.listingDelayCompleter = Completer<void>();
      speechService.listingResultToReturn = const AiListingSuggestion(
        titleEn: 'AI Clay Toy',
        titleHi: 'एआई मिट्टी का खिलौना',
        descriptionEn: 'Traditional clay toy made by artisan.',
        descriptionHi: 'कारीगर द्वारा बनाया गया पारंपरिक मिट्टी का खिलौना।',
        category: 'Pottery',
        tags: ['clay', 'toy'],
        rawMaterialCost: 50.0,
        laborHours: 1.0,
        hourlyRate: 30.0,
        floorPrice: 80.0,
        status: 'success',
      );

      // When flow starts listing generation:
      final flight = flow.generateAiListing('hi');

      // Artisan edits Hindi title while request is in flight
      await flow.updateListingDetails(titleHi: 'मेरा हस्तनिर्मित खिलौना');

      // Artisan edits cost parameters
      await flow.updateCostParameters(materialCost: 250.0, laborHours: 4.0, hourlyRate: 100.0);

      // Artisan edits English title, then changes mind and reverts text
      await flow.updateListingDetails(titleEn: 'Temporary English Title');
      await flow.updateListingDetails(titleEn: 'Artisan Chosen English Title');

      // Release backend delay
      speechService.listingDelayCompleter!.complete();
      speechService.listingDelayCompleter = null;

      await flight;
      await flow.awaitActiveBackgroundFutures();

      final draft = container.read(addProductFlowProvider);

      // Artisan's manual edits MUST be protected!
      expect(draft.titleHi, 'मेरा हस्तनिर्मित खिलौना', reason: 'Artisan Hindi edit must not be overwritten by late AI response');
      expect(draft.titleEn, 'Artisan Chosen English Title', reason: 'Artisan English edit-then-revert must not be overwritten');
      expect(draft.rawMaterialCost, 250.0, reason: 'Artisan cost parameters must not be overwritten');
      expect(draft.laborHours, 4.0);
      expect(draft.hourlyRate, 100.0);

      // Unedited fields (description, category, tags) CAN be populated by AI
      expect(draft.category, 'Pottery');
      expect(draft.tags, contains('clay'));
    });

    test('Explicit regeneration after idempotently cached fallback creates fresh key', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_fallback_retry_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Traditional wooden toy',
      );

      // First run returns a degraded fallback
      speechService.listingResultToReturn = const AiListingSuggestion(
        titleEn: 'Draft Listing: Wooden Toy',
        titleHi: 'लकड़ी का खिलौना',
        descriptionEn: 'Template description',
        descriptionHi: 'टेम्पलेट विवरण',
        category: 'Woodcraft',
        tags: [],
        status: 'fallback',
        isDegraded: true,
        degradedReason: 'Model degraded fallback',
      );

      await flow.generateAiListing('en');
      await flow.awaitActiveBackgroundFutures();

      final firstDraft = container.read(addProductFlowProvider);
      expect(firstDraft.listingStatus, 'fallback');
      final firstKey = speechService.listingIdempotencyKeys.last;
      final firstGen = firstDraft.listingInputGeneration;

      // An explicit user regeneration must create a new durable operation identity
      speechService.listingResultToReturn = const AiListingSuggestion(
        titleEn: 'Handcrafted Wooden Toy',
        titleHi: 'हस्तनिर्मित लकड़ी का खिलौना',
        descriptionEn: 'Finely carved artisan toy.',
        descriptionHi: 'बारीकी से तराशा गया लकड़ी का खिलौना।',
        category: 'Woodcraft',
        tags: ['wooden', 'toy'],
        status: 'success',
        isDegraded: false,
      );

      await flow.retryListingGeneration(languageCode: 'en');
      await flow.awaitActiveBackgroundFutures();

      final retriedDraft = container.read(addProductFlowProvider);
      final secondKey = speechService.listingIdempotencyKeys.last;
      final secondGen = retriedDraft.listingInputGeneration;

      expect(secondGen, greaterThan(firstGen), reason: 'Explicit regeneration after fallback must bump generation');
      expect(secondKey, isNot(equals(firstKey)), reason: 'Explicit regeneration must create a fresh idempotency key to avoid caching loop');
      expect(retriedDraft.listingStatus, 'success');
      expect(retriedDraft.titleEn, 'Handcrafted Wooden Toy');
    });

    test('Snapshot preservation during retake and retry keeps immutable file intact', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_snap_test',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      await flow.transcribeVoiceDirectly(sampleAudioFile);
      await flow.awaitActiveBackgroundFutures();

      final draftAfterFirst = container.read(addProductFlowProvider);
      final firstSnapshotPath = draftAfterFirst.immutableAudioSnapshotPath;
      expect(firstSnapshotPath, isNotEmpty);
      final firstSnapFile = File(firstSnapshotPath);
      expect(firstSnapFile.existsSync(), isTrue);
      final firstBytes = firstSnapFile.readAsBytesSync();

      // Create a second audio file representing a re-recorded voice note
      final newAudioFile = File('${tempDir.path}/rerecorded.m4a');
      await newAudioFile.writeAsBytes(dummyM4aBytes(128, 77), flush: true);

      // Retake recording
      await flow.queueVoiceRecording(newAudioFile);
      await flow.transcribeVoiceDirectly(newAudioFile);
      await flow.awaitActiveBackgroundFutures();

      final draftAfterSecond = container.read(addProductFlowProvider);
      final secondSnapshotPath = draftAfterSecond.immutableAudioSnapshotPath;
      expect(secondSnapshotPath, isNot(equals(firstSnapshotPath)), reason: 'New recording must create a unique snapshot file');

      // The original snapshot must NOT have been deleted or overwritten!
      expect(firstSnapFile.existsSync(), isTrue, reason: 'First snapshot must be preserved for historical/active operations');
      expect(firstSnapFile.readAsBytesSync(), equals(firstBytes));
    });
  });

  group('Step2DescribeWidget UI Degradation & Retry Banner Tests', () {
    testWidgets('Renders Transcription failed—retry banner and Retry button on serviceUnavailable', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_ui_test',
        recordedAudioPath: sampleAudioFile.path,
        isVoiceDegraded: true,
        voiceDegradedCode: VoiceDegradedCode.serviceUnavailable,
        voiceDegradedReason: 'Transcription failed—retry',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step2DescribeWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Transcription failed—retry'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(fakeNotifier.transcribeCalls, 1);
    });

    testWidgets('Renders silence message and does NOT show Retry button on noSpeech', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_silence_ui',
        recordedAudioPath: sampleAudioFile.path,
        isVoiceDegraded: true,
        voiceDegradedCode: VoiceDegradedCode.noSpeech,
        voiceDegradedReason: 'No audible speech detected.',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step2DescribeWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No audible speech detected. Speak closer to the microphone or enter text below.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('Renders listing failure with saved transcript and Retry button', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_listing_fail_ui',
        voiceTranscript: 'Handcrafted wooden toy',
        isListingDegraded: true,
        listingDegradedReason: 'Listing generation failed',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step2DescribeWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AI listing generation failed. Your transcript was saved.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(fakeNotifier.retryListingCalls, 1);
    });
  });

  group('Step3AiReviewWidget UI State Distinctions', () {
    testWidgets('Renders pending banner when listingStatus is pending', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_step3_pending',
        voiceTranscript: 'Terracotta Pot',
        listingStatus: 'pending',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step3AiReviewWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('listing_pending_banner')), findsOneWidget);
    });

    testWidgets('Renders clarification banner when listingStatus is needs_clarification', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_step3_clarify',
        voiceTranscript: 'Hello hello',
        listingStatus: 'needs_clarification',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step3AiReviewWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('listing_needs_clarification_banner')), findsOneWidget);
    });

    testWidgets('Renders fallback banner when listingStatus is fallback', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_step3_fallback',
        voiceTranscript: 'Wooden Spoon',
        listingStatus: 'fallback',
        listingDegradedReason: 'AI generation degraded. Please review.',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step3AiReviewWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('listing_fallback_banner')), findsOneWidget);
    });

    testWidgets('Renders failure banner with Retry button when listingStatus is failed', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testDraft = AddProductDraft(
        draftId: 'draft_step3_failed',
        voiceTranscript: 'Brass Lamp',
        listingStatus: 'failed',
      );
      final fakeNotifier = FakeAddProductFlowNotifier(testDraft);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addProductFlowProvider.overrideWith((ref) => fakeNotifier),
            speechServiceProvider.overrideWithValue(speechService),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            useOnlyLangCode: true,
            child: const MaterialApp(
              home: Scaffold(
                body: Step3AiReviewWidget(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('listing_failed_banner')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(fakeNotifier.retryListingCalls, 1);
    });
  });

  group('Diagnostic Review Regressions & Disk-Backed Recovery Tests', () {
    test('REVIEW synchronous double listing calls dispatch only once', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_listing', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingDelayCompleter = Completer<void>();
      final a = flow.generateAiListing('en');
      final b = flow.generateAiListing('en');
      speechService.listingDelayCompleter!.complete();
      await Future.wait([a, b]);
      expect(speechService.generateListingCallCount, 1);
    });

    test('REVIEW retaking voice invalidates old listing response', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_listing_retake', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingDelayCompleter = Completer<void>();
      final flight = flow.generateAiListing('en');
      for (var n = 0; n < 100 && speechService.generateListingCallCount == 0; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(speechService.generateListingCallCount, 1);
      await flow.retakeDescription();
      speechService.listingDelayCompleter!.complete();
      await flight;
      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
          reason: 'Retaken voice cannot receive a listing generated from the discarded recording');
    });

    test('REVIEW switching draft during preparation must not dispatch old transcript', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_listing_switch', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      final flight = flow.generateAiListing('en');
      flow.discardPreviousDraft();
      await flight;
      expect(speechService.generateListingCallCount, 0,
          reason: 'Preparation awaits must validate originating draft before dispatch');
      expect(container.read(addProductFlowProvider).voiceListingOpId, isNull);
    });

    test('REVIEW response-lost retry preserves listing idempotency key', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_listing_retry', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingExceptionToThrow = const SocketException('Response lost');
      await flow.generateAiListing('en');
      final originalKey = speechService.listingIdempotencyKeys.single;
      speechService.listingExceptionToThrow = null;
      await flow.retryListingGeneration(languageCode: 'en');
      expect(speechService.listingIdempotencyKeys.last, originalKey,
          reason: 'An ambiguous transport failure must replay the original operation, not pay for a new one');
    });

    test('Account change during preparation aborts before dispatch and carries bound session context', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_account_change', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingDelayCompleter = Completer<void>();
      final flight = flow.generateAiListing('en');

      // Switch user identity during in-flight preparation
      authNotifier.overrideUser('different_user_123');

      speechService.listingDelayCompleter!.complete();
      await flight;

      // Initiating session context was bound at entry and never mutated by replacement user
      if (speechService.capturedListingSessionContexts.isNotEmpty) {
        final ctx = speechService.capturedListingSessionContexts.first;
        expect(ctx?.userId, 'artisan_voice_tester');
      }
    });

    test('Backend origin change during preparation aborts before dispatch', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_backend_change', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingDelayCompleter = Completer<void>();
      final flight = flow.generateAiListing('en');

      final originalUrl = ApiConfig.baseUrl;
      try {
        ApiConfig.setBaseUrl('http://10.0.0.99:8000');
        speechService.listingDelayCompleter!.complete();
        await flight;
      } finally {
        ApiConfig.setBaseUrl(originalUrl);
      }

      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
          reason: 'Backend change during flight must reject stale response');
    });

    test('Active session generation increment aborts stale response', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_session_bump', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
      speechService.listingDelayCompleter = Completer<void>();
      final flight = flow.generateAiListing('en');
      for (var n = 0; n < 100 && speechService.generateListingCallCount == 0; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(speechService.generateListingCallCount, 1);

      // Bump active session generation
      ActiveSessionManager.bumpSessionGeneration();

      speechService.listingDelayCompleter!.complete();
      await flight;

      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
          reason: 'Response must be rejected after session generation change');
    });

    test('Audio snapshot rejects invalid format raw ADTS AAC frames', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_raw_aac', originalImagePath: '', enhancedImagePath: '', transcript: '');

      final rawAacFile = File('${tempDir.path}/raw_stream.aac');
      // 0xFF 0xF1 is raw ADTS header without container
      await rawAacFile.writeAsBytes([0xFF, 0xF1, 0x50, 0x80, 0x00, 0x00, 0x00, 0x00]);

      await flow.transcribeVoiceDirectly(rawAacFile);
      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
    });

    test('Unknown listing status values map to degraded fallback, not success', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(draftId: 'review_unknown_status', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');

      speechService.listingResultToReturn = const AiListingSuggestion(
        titleEn: 'Unknown Status Product',
        titleHi: 'उत्पाद',
        descriptionEn: 'Test description',
        descriptionHi: 'विवरण',
        category: 'Pottery',
        tags: ['clay'],
        rawMaterialCost: 100,
        laborHours: 2,
        hourlyRate: 50,
        floorPrice: 200,
        status: 'fabricated_unknown_status',
        isDegraded: false,
      );

      await flow.generateAiListing('en');
      final draft = container.read(addProductFlowProvider);
      expect(draft.listingStatus, 'fallback', reason: 'Unknown status must map to fallback');
      expect(draft.isListingDegraded, isTrue, reason: 'Unknown status must be marked degraded');
    });

    test('True restart boundary: pending transcription generated via production path recovered after Hive close/reopen and continues to listing', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_transcription',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
      );

      final audioFile = File('${tempDir.path}/audio.wav');
      await audioFile.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);

      // Process 1: Start transcription with delay so operation is in-flight on disk
      speechService.transcribeDelayCompleter = Completer<void>();
      final flight1 = flow.transcribeVoiceDirectly(audioFile);

      // Wait for snapshot creation and AiOperationRecord save to disk
      for (var n = 0; n < 100 && speechService.transcribeAudioCallCount == 0; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(speechService.transcribeAudioCallCount, 1);

      // Verify record is saved in-flight on disk
      final aiBox = Hive.box<String>('ai_operations_box');
      expect(aiBox.isNotEmpty, isTrue);

      // Interrupt Process 1 at this persistence boundary: invalidate context to preserve disk record
      authNotifier.overrideUser('different_user_to_abort_flight_1');
      speechService.transcribeDelayCompleter!.complete();
      try {
        await flight1;
      } catch (_) {}

      container.dispose();
      await Hive.close();

      // Process 2: Fresh startup reopening existing Hive directory
      Hive.init(tempDir.path);
      await Hive.openBox('auth_box');
      await Hive.openBox('draft_box');
      await Hive.openBox<String>('ai_operations_box');
      await Hive.openBox<UserProfile>('user_profile_box');
      await Hive.openBox<Product>('products_box');

      final freshSpeech = ControllableSpeechService();
      final freshContainer = ProviderContainer(overrides: [
        speechServiceProvider.overrideWithValue(freshSpeech),
        pricingServiceProvider.overrideWithValue(pricingService),
        authStateProvider.overrideWith((ref) => FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
      ]);
      container = freshContainer;

      final freshFlow = freshContainer.read(addProductFlowProvider.notifier);
      // Restore draft through the normal startup/resume path
      await freshFlow.resumeExistingDraft();
      await freshFlow.awaitActiveBackgroundFutures();

      expect(freshSpeech.transcribeAudioCallCount, 1,
          reason: 'Pending transcription must be replayed across restart boundary');
      expect(freshSpeech.generateListingCallCount, 1,
          reason: 'Recovered transcript must durably proceed into listing generation across restart');
      final recoveredDraft = freshContainer.read(addProductFlowProvider);
      expect(recoveredDraft.voiceTranscript, isNotEmpty);
      expect(recoveredDraft.titleEn, 'Clay Pot');
    });

    test('True restart boundary: pending listing generated via production path recovered after Hive close/reopen', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Terracotta Vase',
      );

      // Process 1: Start listing generation with delay so it is persisted in-flight
      speechService.listingDelayCompleter = Completer<void>();
      final flight1 = flow.generateAiListing('en');

      for (var n = 0; n < 100 && speechService.generateListingCallCount == 0; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(speechService.generateListingCallCount, 1);

      // Interrupt Process 1 at this persistence boundary: invalidate context to preserve disk record
      authNotifier.overrideUser('different_user_to_abort_flight_1');
      speechService.listingDelayCompleter!.complete();
      try {
        await flight1;
      } catch (_) {}

      container.dispose();
      await Hive.close();

      // Process 2: Fresh startup reopening existing Hive directory
      Hive.init(tempDir.path);
      await Hive.openBox('auth_box');
      await Hive.openBox('draft_box');
      await Hive.openBox<String>('ai_operations_box');
      await Hive.openBox<UserProfile>('user_profile_box');
      await Hive.openBox<Product>('products_box');

      final freshSpeech = ControllableSpeechService();
      final freshContainer = ProviderContainer(overrides: [
        speechServiceProvider.overrideWithValue(freshSpeech),
        pricingServiceProvider.overrideWithValue(pricingService),
        authStateProvider.overrideWith((ref) => FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
      ]);
      container = freshContainer;

      final freshFlow = freshContainer.read(addProductFlowProvider.notifier);
      // Restore draft through normal startup/resume path
      await freshFlow.resumeExistingDraft();
      await freshFlow.awaitActiveBackgroundFutures();

      final recoveredDraft = freshContainer.read(addProductFlowProvider);
      expect(recoveredDraft.titleEn, 'Clay Pot');
      expect(recoveredDraft.category, 'Pottery');
      expect(recoveredDraft.listingStatus, 'success');
    });

    test('True restart boundary: response-lost retry after manual title edit reuses original wire key and preserves title edit across restart', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_retry',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handloom scarf',
      );

      // Process 1: Network response lost on first attempt
      speechService.listingExceptionToThrow = const SocketException('Connection lost');
      await flow.generateAiListing('en');
      final originalKey = speechService.listingIdempotencyKeys.single;

      // Artisan edits title after transport failure
      await flow.updateListingDetails(titleEn: 'My Handloom Scarf Title');
      await flow.awaitActiveBackgroundFutures();

      // Simulate crash & restart
      container.dispose();
      await Hive.close();

      // Process 2: Reopen Hive and create fresh container
      Hive.init(tempDir.path);
      await Hive.openBox('auth_box');
      await Hive.openBox('draft_box');
      await Hive.openBox<String>('ai_operations_box');
      await Hive.openBox<UserProfile>('user_profile_box');
      await Hive.openBox<Product>('products_box');

      final freshSpeech = ControllableSpeechService();
      final freshContainer = ProviderContainer(overrides: [
        speechServiceProvider.overrideWithValue(freshSpeech),
        pricingServiceProvider.overrideWithValue(pricingService),
        authStateProvider.overrideWith((ref) => FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
      ]);
      container = freshContainer;

      final freshFlow = freshContainer.read(addProductFlowProvider.notifier);
      // Restore draft through normal startup/resume path
      await freshFlow.resumeExistingDraft();
      await freshFlow.awaitActiveBackgroundFutures();

      // User triggers retry after restart
      await freshFlow.retryListingGeneration(languageCode: 'en');
      await freshFlow.awaitActiveBackgroundFutures();

      expect(freshSpeech.listingIdempotencyKeys.last, originalKey,
          reason: 'Retry after restart must replay the original idempotency key, not generate a new one');
      final recoveredDraft = freshContainer.read(addProductFlowProvider);
      expect(recoveredDraft.titleEn, 'My Handloom Scarf Title',
          reason: 'Artisan manual title edit must survive recovery over AI suggestion');
    });

    test('True restart boundary: persisted degraded/fallback result hydrates draft with degradation indicators intact', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_degraded',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Clay bowl',
      );

      // Process 1: Server completes with degraded fallback
      speechService.listingResultToReturn = const AiListingSuggestion(
        titleEn: 'Fallback Bowl',
        titleHi: 'कटोरा',
        descriptionEn: 'Degraded description',
        descriptionHi: 'विवरण',
        category: 'Pottery',
        tags: ['clay'],
        rawMaterialCost: 60,
        laborHours: 1,
        hourlyRate: 40,
        floorPrice: 100,
        status: 'fallback',
        isDegraded: true,
        degradedReason: 'Model timed out, used local fallback',
      );

      await flow.generateAiListing('en');
      await flow.awaitActiveBackgroundFutures();

      // Simulate crash & restart
      container.dispose();
      await Hive.close();

      // Process 2: Reopen Hive and create fresh container
      Hive.init(tempDir.path);
      await Hive.openBox('auth_box');
      await Hive.openBox('draft_box');
      await Hive.openBox<String>('ai_operations_box');
      await Hive.openBox<UserProfile>('user_profile_box');
      await Hive.openBox<Product>('products_box');

      final freshSpeech = ControllableSpeechService();
      final freshContainer = ProviderContainer(overrides: [
        speechServiceProvider.overrideWithValue(freshSpeech),
        pricingServiceProvider.overrideWithValue(pricingService),
        authStateProvider.overrideWith((ref) => FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
      ]);
      container = freshContainer;

      final freshFlow = freshContainer.read(addProductFlowProvider.notifier);
      // Restore draft through normal startup/resume path
      await freshFlow.resumeExistingDraft();
      await freshFlow.awaitActiveBackgroundFutures();

      final recoveredDraft = freshContainer.read(addProductFlowProvider);
      expect(recoveredDraft.titleEn, 'Fallback Bowl');
      expect(recoveredDraft.listingStatus, 'fallback');
      expect(recoveredDraft.isListingDegraded, isTrue);
      expect(recoveredDraft.listingDegradedReason, 'Model timed out, used local fallback');
    });

    test('True restart boundary: combined completed transcription and pending Hindi listing recovers via resumeExistingDraft with exactly one wire request and original key', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'draft_restart_combined',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
      );

      // Process 1: Network response lost on Hindi listing attempt
      speechService.listingExceptionToThrow = const SocketException('Response lost');
      await flow.generateAiListing('hi');
      final originalKey = speechService.listingIdempotencyKeys.single;

      final listing = (await AiOperationStorage.findOperation('draft_restart_combined', 'listing_generate'))!;
      await AiOperationStorage.save(listing.copyWith(status: AiOperationRecord.statusInFlight));
      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_completed_op',
        idempotencyKey: 'voice_completed_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 0,
        draftId: 'draft_restart_combined',
        status: AiOperationRecord.statusCompleted,
        inputFingerprint: 'completed_fp',
        requestSnapshot: {'language_code': 'hi'},
        resultData: {'transcript': 'Handmade clay pot', 'confidence': 0.95},
        createdAt: listing.createdAt.subtract(const Duration(seconds: 1)),
        updatedAt: DateTime.now(),
      ));

      await flow.awaitActiveBackgroundFutures();

      container.dispose();
      await Hive.close();

      // Process 2: Fresh startup reopening existing Hive directory
      Hive.init(tempDir.path);
      await Hive.openBox('auth_box');
      await Hive.openBox('draft_box');
      await Hive.openBox<String>('ai_operations_box');
      await Hive.openBox<UserProfile>('user_profile_box');
      await Hive.openBox<Product>('products_box');

      final freshSpeech = ControllableSpeechService();
      final freshContainer = ProviderContainer(overrides: [
        speechServiceProvider.overrideWithValue(freshSpeech),
        pricingServiceProvider.overrideWithValue(pricingService),
        authStateProvider.overrideWith((ref) => FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
      ]);
      container = freshContainer;

      final freshFlow = freshContainer.read(addProductFlowProvider.notifier);
      await freshFlow.resumeExistingDraft();
      await freshFlow.awaitActiveBackgroundFutures();

      expect(freshSpeech.listingIdempotencyKeys, [originalKey],
          reason: 'Combined recovery across restart must issue exactly one request using the original listing key');
      final recoveredDraft = freshContainer.read(addProductFlowProvider);
      expect(recoveredDraft.titleEn, 'Clay Pot');
      expect(recoveredDraft.listingStatus, 'success');
    });

    test('Audio fingerprint replay: valid fingerprint executes replay to transport', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      final audio = File('${tempDir.path}/pending_valid.wav');
      await audio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      await flow.loadSavedDraftState(
        draftId: 'draft_fp_valid',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        voiceInputGeneration: 1,
        voiceListingOpId: 'voice_fp_valid_op',
        recordedAudioPath: audio.path,
        immutableAudioSnapshotPath: audio.path,
      );

      final validFp = await AiOperationRecord.computeFingerprint(
        operationType: 'voice_transcribe',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        inputs: {'draft_id': 'draft_fp_valid', 'language_code': 'hi'},
        files: [audio],
      );

      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_fp_valid_op',
        idempotencyKey: 'voice_fp_valid_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 1,
        draftId: 'draft_fp_valid',
        status: AiOperationRecord.statusInFlight,
        inputFingerprint: validFp,
        requestSnapshot: {'audio_path': audio.path, 'language_code': 'hi'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      expect(speechService.transcribeAudioCallCount, 1, reason: 'Valid fingerprint must allow replay dispatch');
      expect(container.read(addProductFlowProvider).isVoiceDegraded, isFalse);
    });

    test('Audio fingerprint replay: missing fingerprint fails closed without transport call', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      final audio = File('${tempDir.path}/pending_missing.wav');
      await audio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      await flow.loadSavedDraftState(
        draftId: 'draft_fp_missing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        voiceInputGeneration: 1,
        voiceListingOpId: 'voice_fp_missing_op',
        recordedAudioPath: audio.path,
        immutableAudioSnapshotPath: audio.path,
      );

      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_fp_missing_op',
        idempotencyKey: 'voice_fp_missing_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 1,
        draftId: 'draft_fp_missing',
        status: AiOperationRecord.statusInFlight,
        inputFingerprint: '', // empty fingerprint
        requestSnapshot: {'audio_path': audio.path, 'language_code': 'hi'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      expect(speechService.transcribeAudioCallCount, 0, reason: 'Missing fingerprint must not call transport');
      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
    });

    test('Audio fingerprint replay: former test_fixture sentinel fails closed without transport call', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      final audio = File('${tempDir.path}/pending_sentinel.wav');
      await audio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      await flow.loadSavedDraftState(
        draftId: 'draft_fp_sentinel',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        voiceInputGeneration: 1,
        voiceListingOpId: 'voice_fp_sentinel_op',
        recordedAudioPath: audio.path,
        immutableAudioSnapshotPath: audio.path,
      );

      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_fp_sentinel_op',
        idempotencyKey: 'voice_fp_sentinel_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 1,
        draftId: 'draft_fp_sentinel',
        status: AiOperationRecord.statusInFlight,
        inputFingerprint: 'test_fixture', // former sentinel
        requestSnapshot: {'audio_path': audio.path, 'language_code': 'hi'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      expect(speechService.transcribeAudioCallCount, 0, reason: 'Sentinel string must fail closed as mismatched fingerprint');
      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
    });

    test('Audio fingerprint replay: tampered audio bytes fail closed without transport call', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      final audio = File('${tempDir.path}/pending_tampered.wav');
      await audio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45]);
      await flow.loadSavedDraftState(
        draftId: 'draft_fp_tampered',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        voiceInputGeneration: 1,
        voiceListingOpId: 'voice_fp_tampered_op',
        recordedAudioPath: audio.path,
        immutableAudioSnapshotPath: audio.path,
      );

      final validFp = await AiOperationRecord.computeFingerprint(
        operationType: 'voice_transcribe',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        inputs: {'draft_id': 'draft_fp_tampered', 'language_code': 'hi'},
        files: [audio],
      );

      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_fp_tampered_op',
        idempotencyKey: 'voice_fp_tampered_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 1,
        draftId: 'draft_fp_tampered',
        status: AiOperationRecord.statusInFlight,
        inputFingerprint: validFp,
        requestSnapshot: {'audio_path': audio.path, 'language_code': 'hi'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Tamper audio bytes on disk after fingerprint was computed!
      await audio.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0xFF, 0xFF, 0xFF, 0xFF, 0x57, 0x41, 0x56, 0x45]);

      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      expect(speechService.transcribeAudioCallCount, 0, reason: 'Tampered audio bytes must mismatch fingerprint and prevent dispatch');
      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
    });

    test('Audio fingerprint replay: missing audio file fails closed and preserves operation', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      final audioPath = '${tempDir.path}/missing_audio.wav';
      await flow.loadSavedDraftState(
        draftId: 'draft_fp_missing_file',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        voiceInputGeneration: 1,
        voiceListingOpId: 'voice_fp_missing_file_op',
        recordedAudioPath: audioPath,
        immutableAudioSnapshotPath: audioPath,
      );

      await AiOperationStorage.save(AiOperationRecord(
        id: 'voice_fp_missing_file_op',
        idempotencyKey: 'voice_fp_missing_file_op',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 1,
        draftId: 'draft_fp_missing_file',
        status: AiOperationRecord.statusInFlight,
        inputFingerprint: 'some_fp',
        requestSnapshot: {'audio_path': audioPath, 'language_code': 'hi'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await flow.reconcileDraftOperations();
      await flow.awaitActiveBackgroundFutures();

      expect(speechService.transcribeAudioCallCount, 0, reason: 'Missing audio file must prevent dispatch');
      final draft = container.read(addProductFlowProvider);
      expect(draft.isVoiceDegraded, isTrue);
      expect(draft.voiceDegradedCode, VoiceDegradedCode.invalidAudio);
      // Verify operation is preserved in storage with failed status (not deleted!)
      final op = await AiOperationStorage.get('voice_fp_missing_file_op');
      expect(op, isNotNull);
      expect(op!.status, AiOperationRecord.statusFailed);
    });

    test('Reconciliation isolation: account switch prevents applying cached listing and preserves persisted draft', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      await flow.generateAiListing('hi');
      expect(speechService.generateListingCallCount, 1);
      final record = await AiOperationStorage.findOperation('review_listing', 'listing_generate');
      expect(record, isNotNull);
      expect(record!.resultData, isNotNull);
      expect(record.resultData!['title_en'], 'Clay Pot');

      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      final before = Hive.box('draft_box').get('active_draft_snapshot');
      expect(container.read(addProductFlowProvider).titleEn, isEmpty);
      final reconciliation = flow.reconcileDraftOperations();
      authNotifier.overrideUser('artisan_b');
      await reconciliation;
      await flow.awaitActiveBackgroundFutures();

      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
        reason: 'Owner A cached content must not be applied after active account becomes B');

      expect(Hive.box('draft_box').get('active_draft_snapshot'), before,
        reason: 'Persisted draft must not be updated by stale cached listing of previous owner');

      final op = await AiOperationStorage.get(record.id);
      expect(op, isNotNull);
      expect(op!.resultData!['title_en'], 'Clay Pot');
      expect(op.owner, 'artisan_voice_tester');
    });

    test('Reconciliation isolation: session generation increment prevents applying cached listing and preserves persisted draft', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      await flow.generateAiListing('hi');
      expect(speechService.generateListingCallCount, 1);
      final record = await AiOperationStorage.findOperation('review_listing', 'listing_generate');
      expect(record, isNotNull);
      expect(record!.resultData, isNotNull);
      expect(record.resultData!['title_en'], 'Clay Pot');

      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      final before = Hive.box('draft_box').get('active_draft_snapshot');
      expect(container.read(addProductFlowProvider).titleEn, isEmpty);

      final reconciliation = flow.reconcileDraftOperations();
      ActiveSessionManager.bumpSessionGeneration();
      await reconciliation;
      await flow.awaitActiveBackgroundFutures();

      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
        reason: 'Cached listing must not be applied after session generation increments');

      expect(Hive.box('draft_box').get('active_draft_snapshot'), before,
        reason: 'Persisted draft must remain clean after session generation increment');

      expect((await AiOperationStorage.get(record.id))!.resultData!['title_en'], 'Clay Pot',
        reason: 'Original operation record must remain available in storage');
    });

    test('Reconciliation isolation: backend origin change prevents applying cached listing and preserves persisted draft', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      await flow.generateAiListing('hi');
      expect(speechService.generateListingCallCount, 1);
      final record = await AiOperationStorage.findOperation('review_listing', 'listing_generate');
      expect(record, isNotNull);
      expect(record!.resultData, isNotNull);
      expect(record.resultData!['title_en'], 'Clay Pot');

      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      final before = Hive.box('draft_box').get('active_draft_snapshot');
      expect(container.read(addProductFlowProvider).titleEn, isEmpty);

      final origin = ApiConfig.baseUrl;
      final reconciliation = flow.reconcileDraftOperations();
      try {
        ApiConfig.setBaseUrl('http://127.0.0.1:8999');
        await reconciliation;
        await flow.awaitActiveBackgroundFutures();

        expect(container.read(addProductFlowProvider).titleEn, isEmpty,
          reason: 'Cached listing from different backend must not be applied');

        expect(Hive.box('draft_box').get('active_draft_snapshot'), before,
          reason: 'Persisted draft must remain clean after backend origin change');

        expect((await AiOperationStorage.get(record.id))!.resultData!['title_en'], 'Clay Pot',
          reason: 'Original operation record must remain available in storage');
      } finally {
        ApiConfig.setBaseUrl(origin);
      }
    });

    test('Reconciliation isolation: draft switch during reconciliation prevents applying cached listing and preserves persisted draft', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      await flow.generateAiListing('hi');
      expect(speechService.generateListingCallCount, 1);
      final record = await AiOperationStorage.findOperation('review_listing', 'listing_generate');
      expect(record, isNotNull);
      expect(record!.resultData, isNotNull);
      expect(record.resultData!['title_en'], 'Clay Pot');

      await flow.loadSavedDraftState(
        draftId: 'review_listing',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Handmade clay pot',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      expect(container.read(addProductFlowProvider).titleEn, isEmpty);

      final reconciliation = flow.reconcileDraftOperations();
      await flow.loadSavedDraftState(
        draftId: 'switched_draft',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: 'Different draft',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      await reconciliation;
      await flow.awaitActiveBackgroundFutures();

      expect(container.read(addProductFlowProvider).draftId, 'switched_draft');
      expect(container.read(addProductFlowProvider).titleEn, isEmpty,
        reason: 'Cached listing from previous draft must not contaminate the switched draft');

      final draftBox = Hive.box('draft_box');
      final raw = draftBox.get('active_draft_snapshot');
      final snapshot = raw != null ? jsonDecode(raw.toString()) as Map<String, dynamic> : <String, dynamic>{};
      expect((snapshot['title_en'] as String?)?.isEmpty ?? true, isTrue,
        reason: 'Persisted draft for switched draft must not have old draft listing');

      expect((await AiOperationStorage.get(record.id))!.resultData!['title_en'], 'Clay Pot',
        reason: 'Original operation record must remain available in storage');
    });

    test('Reconciliation isolation: cached transcription cannot apply after account switch and does not dispatch listing', () async {
      final flow = container.read(addProductFlowProvider.notifier);
      await AiOperationStorage.save(AiOperationRecord(
        id: 'completed_voice_iso',
        idempotencyKey: 'completed_voice_iso',
        owner: 'artisan_voice_tester',
        backend: ApiConfig.baseUrl,
        operationType: 'voice_transcribe',
        inputGeneration: 0,
        draftId: 'draft_voice_iso',
        status: AiOperationRecord.statusCompleted,
        inputFingerprint: 'voice_iso_fp',
        requestSnapshot: {'language_code': 'hi'},
        resultData: {'transcript': 'Handmade clay pot', 'confidence': 0.9},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await flow.loadSavedDraftState(
        draftId: 'draft_voice_iso',
        originalImagePath: '',
        enhancedImagePath: '',
        transcript: '',
        listingInputGeneration: 1,
        listingStatus: 'pending',
      );
      expect(container.read(addProductFlowProvider).voiceTranscript, isEmpty);

      final reconciliation = flow.reconcileDraftOperations();
      authNotifier.overrideUser('artisan_b');
      await reconciliation;
      await flow.awaitActiveBackgroundFutures();

      expect(container.read(addProductFlowProvider).voiceTranscript, isEmpty,
        reason: 'Cached voice transcription must not apply after account switch to artisan_b');
      expect(speechService.generateListingCallCount, 0,
        reason: 'No listing generation must be dispatched under replacement session');

      final draftBox = Hive.box('draft_box');
      final raw = draftBox.get('active_draft_snapshot');
      final snapshot = raw != null ? jsonDecode(raw.toString()) as Map<String, dynamic> : <String, dynamic>{};
      expect((snapshot['voice_transcript'] as String?)?.isEmpty ?? true, isTrue,
        reason: 'Persisted draft must not have voice transcript applied');

      final op = await AiOperationStorage.get('completed_voice_iso');
      expect(op, isNotNull);
      expect(op!.owner, 'artisan_voice_tester');
    });
  });
}
