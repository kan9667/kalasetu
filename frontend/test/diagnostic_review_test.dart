import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/features/auth/providers/auth_provider.dart';
import 'package:kalasetu/data/models/ai_operation_record.dart';
import 'package:kalasetu/core/config/api_config.dart';
import 'package:kalasetu/core/network/active_session_manager.dart';
import 'voice_transcription_retry_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;
  late fixture.ControllableSpeechService speech;
  late AddProductFlowNotifier flow;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('listing_review_storage_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());
    final auth = await Hive.openBox('auth_box');
    await auth.put('user_id', 'artisan_voice_tester');
    await auth.put('is_authenticated', true);
    await Hive.openBox('draft_box');
    await Hive.openBox<String>('ai_operations_box');
    await Hive.openBox<UserProfile>('user_profile_box');
    await Hive.openBox<Product>('products_box');
    speech = fixture.ControllableSpeechService();
    container = ProviderContainer(overrides: [
      speechServiceProvider.overrideWithValue(speech),
      pricingServiceProvider.overrideWithValue(fixture.MockPricingServiceProbe()),
      authStateProvider.overrideWith((ref) => fixture.FakeAuthNotifier(const AuthState(isAuthenticated: true, userId: 'artisan_voice_tester'))),
    ]);
    flow = container.read(addProductFlowProvider.notifier);
    await flow.loadSavedDraftState(draftId: 'review_listing', originalImagePath: '', enhancedImagePath: '', transcript: 'Handmade clay pot');
  });
  tearDown(() async {
    if (speech.listingDelayCompleter != null && !speech.listingDelayCompleter!.isCompleted) speech.listingDelayCompleter!.complete();
    if (speech.transcribeDelayCompleter != null && !speech.transcribeDelayCompleter!.isCompleted) speech.transcribeDelayCompleter!.complete();
    await flow.awaitActiveBackgroundFutures();
    container.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('REVIEW synchronous double listing calls dispatch only once', () async {
    speech.listingDelayCompleter = Completer<void>();
    final a = flow.generateAiListing('en');
    final b = flow.generateAiListing('en');
    speech.listingDelayCompleter!.complete();
    await Future.wait([a,b]);
    expect(speech.generateListingCallCount, 1);
  });
  test('REVIEW retaking voice invalidates old listing response', () async {
    speech.listingDelayCompleter = Completer<void>();
    final flight = flow.generateAiListing('en');
    for (var n=0; n<100 && speech.generateListingCallCount==0; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(speech.generateListingCallCount, 1);
    await flow.retakeDescription();
    speech.listingDelayCompleter!.complete();
    await flight;
    expect(container.read(addProductFlowProvider).titleEn, isEmpty,
      reason: 'Retaken voice cannot receive a listing generated from the discarded recording');
  });
  test('REVIEW switching draft during preparation must not dispatch old transcript', () async {
    final flight = flow.generateAiListing('en');
    flow.discardPreviousDraft();
    await flight;
    expect(speech.generateListingCallCount, 0,
      reason: 'Preparation awaits must validate originating draft before dispatch');
    expect(container.read(addProductFlowProvider).voiceListingOpId, isNull);
  });
  test('REVIEW response-lost retry preserves listing idempotency key', () async {
    speech.listingExceptionToThrow = const SocketException('Response lost');
    await flow.generateAiListing('en');
    final originalKey = speech.listingIdempotencyKeys.single;
    speech.listingExceptionToThrow = null;
    await flow.retryListingGeneration(languageCode: 'en');
    expect(speech.listingIdempotencyKeys.last, originalKey,
      reason: 'An ambiguous transport failure must replay the original operation, not pay for a new one');
  });
  test('REVIEW retry after a manual title edit reuses original wire operation', () async {
    speech.listingExceptionToThrow = const SocketException('Response lost');
    await flow.generateAiListing('en');
    final originalKey = speech.listingIdempotencyKeys.single;
    await flow.updateListingDetails(titleEn: 'My artisan title');
    speech.listingExceptionToThrow = null;
    await flow.retryListingGeneration(languageCode: 'en');
    expect(speech.listingIdempotencyKeys.last, originalKey);
    expect(container.read(addProductFlowProvider).titleEn, 'My artisan title');
  });
  test('REVIEW reconciliation joins active direct listing', () async {
    speech.listingDelayCompleter = Completer<void>();
    final direct = flow.generateAiListing('en');
    for (var n=0; n<100 && speech.generateListingCallCount==0; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    await flow.reconcileDraftOperations();
    speech.listingDelayCompleter!.complete();
    await direct;
    await flow.awaitActiveBackgroundFutures();
    expect(speech.generateListingCallCount, 1);
  });
  test('REVIEW MPEG1 layer3 frame must not be rejected as raw AAC', () async {
    final mp3 = File('${dir.path}/recording.mp3');
    await mp3.writeAsBytes([0xff, 0xfb, 0x90, 0x64, ...List.filled(100,0)]);
    await flow.transcribeVoiceDirectly(mp3);
    expect(speech.transcribeAudioCallCount, 1,
      reason: 'FF FB is an MPEG1 Layer III header, not an ADTS header');
  });
  Future<void> seedPendingVoice() async {
    final audio = File('${dir.path}/pending.wav');
    await audio.writeAsBytes([0x52,0x49,0x46,0x46,0,0,0,0,0x57,0x41,0x56,0x45]);
    await flow.loadSavedDraftState(draftId: 'pending_voice', originalImagePath: '', enhancedImagePath: '', transcript: '', voiceInputGeneration: 1, voiceListingOpId: 'voice_op', recordedAudioPath: audio.path, immutableAudioSnapshotPath: audio.path);
    await AiOperationStorage.save(AiOperationRecord(
      id: 'voice_op', idempotencyKey: 'voice_op', owner: 'artisan_voice_tester', backend: ApiConfig.baseUrl,
      operationType: 'voice_transcribe', inputGeneration: 1, draftId: 'pending_voice',
      status: AiOperationRecord.statusInFlight,
      inputFingerprint: await AiOperationRecord.computeFingerprint(operationType: 'voice_transcribe', owner: 'artisan_voice_tester', backend: ApiConfig.baseUrl, inputs: {'draft_id':'pending_voice', 'language_code':'hi'}, files: [audio]),
      requestSnapshot: {'audio_path': audio.path, 'language_code':'hi'},
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
  }
  test('REVIEW recovered pending voice proceeds to listing on first resume', () async {
    await seedPendingVoice();
    await flow.reconcileDraftOperations();
    await flow.awaitActiveBackgroundFutures();
    expect(speech.transcribeAudioCallCount, 1);
    expect(speech.generateListingCallCount, 1);
  });
  test('REVIEW late voice replay must not apply after account switch', () async {
    await seedPendingVoice();
    speech.transcribeDelayCompleter = Completer<void>();
    await flow.reconcileDraftOperations();
    for (var n=0; n<100 && speech.transcribeAudioCallCount==0; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(speech.transcribeAudioCallCount, 1);
    final auth = container.read(authStateProvider.notifier) as fixture.FakeAuthNotifier;
    auth.overrideUser('artisan_b');
    speech.transcribeDelayCompleter!.complete();
    await flow.awaitActiveBackgroundFutures();
    expect(container.read(addProductFlowProvider).voiceTranscript, isEmpty);
  });
  test('REVIEW missing voice fingerprint must fail closed', () async {
    await seedPendingVoice();
    final original = (await AiOperationStorage.get('voice_op'))!;
    await AiOperationStorage.save(AiOperationRecord.fromJson({...original.toJson(), 'input_fingerprint': ''}));
    await flow.reconcileDraftOperations();
    await flow.awaitActiveBackgroundFutures();
    expect(speech.transcribeAudioCallCount, 0, reason: 'No verified fingerprint means no authorization to replay these audio bytes');
  });
  test('REVIEW completed voice must reuse existing pending listing identity', () async {
    speech.listingExceptionToThrow = const SocketException('Response lost');
    await flow.generateAiListing('hi');
    final originalKey = speech.listingIdempotencyKeys.single;
    final listing = (await AiOperationStorage.findOperation('review_listing', 'listing_generate'))!;
    await AiOperationStorage.save(listing.copyWith(status: AiOperationRecord.statusInFlight));
    await AiOperationStorage.save(AiOperationRecord(
      id:'completed_voice', idempotencyKey:'completed_voice', owner:'artisan_voice_tester', backend:ApiConfig.baseUrl,
      operationType:'voice_transcribe', inputGeneration:0, draftId:'review_listing', status:AiOperationRecord.statusCompleted,
      inputFingerprint:'unused_completed_fixture', requestSnapshot:{'language_code':'hi'},
      resultData:{'transcript':'Handmade clay pot','confidence':0.9},
      createdAt:listing.createdAt.subtract(const Duration(seconds:1)), updatedAt:DateTime.now(),
    ));
    await flow.loadSavedDraftState(draftId:'review_listing', originalImagePath:'', enhancedImagePath:'', transcript:'Handmade clay pot', listingInputGeneration:1, listingStatus:'pending', voiceListingOpId:listing.id, listingFingerprint:listing.inputFingerprint);
    speech.listingExceptionToThrow = null;
    speech.listingIdempotencyKeys.clear();
    await flow.reconcileDraftOperations();
    await flow.awaitActiveBackgroundFutures();
    expect(speech.listingIdempotencyKeys, [originalKey], reason:'Completed transcription must not regenerate the pending listing with auto language and a new key');
  });
  test('REVIEW cached listing cannot apply after account switch during reconciliation', () async {
    await flow.generateAiListing('hi');
    await flow.loadSavedDraftState(draftId:'review_listing', originalImagePath:'', enhancedImagePath:'', transcript:'Handmade clay pot', listingInputGeneration:1, listingStatus:'pending');
    expect(container.read(addProductFlowProvider).titleEn, isEmpty);
    final reconciliation = flow.reconcileDraftOperations();
    final auth = container.read(authStateProvider.notifier) as fixture.FakeAuthNotifier;
    auth.overrideUser('artisan_b');
    await reconciliation;
    await flow.awaitActiveBackgroundFutures();
    expect(container.read(addProductFlowProvider).titleEn, isEmpty,
      reason:'Owner A cached content must not be applied after the active account becomes B');
  });
  for (final transition in ['session', 'backend', 'draft']) {
    test('REVIEW populated cached listing rejects $transition transition', () async {
      await flow.generateAiListing('hi');
      expect(speech.generateListingCallCount, 1);
      final record = await AiOperationStorage.findOperation('review_listing', 'listing_generate');
      expect(record!.resultData!['title_en'], 'Clay Pot');
      await flow.loadSavedDraftState(draftId:'review_listing', originalImagePath:'', enhancedImagePath:'', transcript:'Handmade clay pot', listingInputGeneration:1, listingStatus:'pending');
      final before = Hive.box('draft_box').get('active_draft_snapshot');
      final origin = ApiConfig.baseUrl;
      final reconciliation = flow.reconcileDraftOperations();
      try {
        if (transition == 'session') ActiveSessionManager.bumpSessionGeneration();
        if (transition == 'backend') ApiConfig.setBaseUrl('http://127.0.0.1:8999');
        if (transition == 'draft') await flow.loadSavedDraftState(draftId:'new_draft', originalImagePath:'', enhancedImagePath:'', transcript:'New draft');
        await reconciliation;
        await flow.awaitActiveBackgroundFutures();
        expect(container.read(addProductFlowProvider).titleEn, isEmpty);
        if (transition != 'draft') expect(Hive.box('draft_box').get('active_draft_snapshot'), before);
        expect((await AiOperationStorage.get(record.id))!.resultData!['title_en'], 'Clay Pot');
      } finally {
        if (transition == 'backend') ApiConfig.setBaseUrl(origin);
      }
    });
  }
}

