import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/product.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/services/api_service.dart';
import '../../data/services/image_enhancer_service.dart';
import '../../data/services/speech_service.dart';
import '../../data/services/pricing_service.dart';
import '../../data/services/sync_service.dart';
import '../offline_sync/models/queue_item.dart';
import '../offline_sync/offline_sync_service.dart';
import '../storage/secure_token_storage.dart';
import '../config/api_config.dart';
import '../../data/models/ai_operation_record.dart';
import '../../features/auth/providers/auth_provider.dart';

// --- Dev/test bypass ---------------------------------------------------
// Lets you build and run the app WITHOUT the backend running, so you can
// test the frontend (navigation, UI, state transitions) end-to-end.
// Turn on with:
//   flutter run --dart-define=MOCK_AI_BACKEND=true
//   flutter build apk --dart-define=MOCK_AI_BACKEND=true   (a throwaway
//   test build — never pass this flag on the build you actually ship)
// When true, image enhancement, transcription, and listing generation are
// all faked locally with a short delay instead of calling the real
// backend, so Step 2 → 3 (and the pricing step, if you extend the same
// pattern to PricingService) resolve instantly regardless of whether a
// server is reachable.
const bool kMockAiBackend =
    bool.fromEnvironment('MOCK_AI_BACKEND', defaultValue: false);

// --- Language Selection Provider ---
class HasSelectedLanguageNotifier extends StateNotifier<bool> {
  static const String _boxName = 'app_settings_box';
  static const String _keySelected = 'has_selected_language';

  HasSelectedLanguageNotifier() : super(false) {
    _loadState();
  }

  void _loadState() {
    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box(_boxName);
      state = box.get(_keySelected, defaultValue: false) as bool;
    }
  }

  Future<void> markLanguageSelected() async {
    state = true;
    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box(_boxName);
      await box.put(_keySelected, true);
    }
  }
}

final hasSelectedLanguageProvider =
    StateNotifierProvider<HasSelectedLanguageNotifier, bool>((ref) {
      return HasSelectedLanguageNotifier();
    });

// --- Listing Tutorial Provider ---
class ListingTutorialNotifier extends StateNotifier<bool> {
  static const String _boxName = 'app_settings_box';
  static const String _keyPrefix = 'has_seen_listing_tutorial_';

  ListingTutorialNotifier() : super(false);

  bool hasSeenTutorial(String userId) {
    if (!Hive.isBoxOpen(_boxName)) return false;
    final box = Hive.box(_boxName);
    return box.get('$_keyPrefix$userId', defaultValue: false) as bool;
  }

  /// Checks if tutorial is needed for [userId]. If not seen yet, marks it seen immediately and returns true (indicating it should launch).
  Future<bool> checkAndMarkTutorialSeen(String userId) async {
    if (!Hive.isBoxOpen(_boxName)) return false;
    final box = Hive.box(_boxName);
    final key = '$_keyPrefix$userId';
    final alreadySeen = box.get(key, defaultValue: false) as bool;
    if (!alreadySeen) {
      await box.put(key, true);
      state = true;
      return true;
    }
    return false;
  }

  Future<void> resetTutorial(String userId) async {
    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box(_boxName);
      await box.delete('$_keyPrefix$userId');
      state = false;
    }
  }
}

final listingTutorialProvider =
    StateNotifierProvider<ListingTutorialNotifier, bool>((ref) {
  return ListingTutorialNotifier();
});

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return SecureTokenStorage();
});

// --- Services Providers ---
final apiServiceProvider = Provider<ApiService>((ref) {
  if (kMockAiBackend) {
    return MockApiService();
  }
  return HttpApiService();
});

final imageEnhancerServiceProvider = Provider<ImageEnhancerService>((ref) {
  final tokenStorage = ref.watch(secureTokenStorageProvider);
  return HttpImageEnhancerService(tokenStorage: tokenStorage);
});

final speechServiceProvider = Provider<SpeechService>((ref) {
  final tokenStorage = ref.watch(secureTokenStorageProvider);
  return HttpSpeechService(tokenStorage: tokenStorage);
});

final pricingServiceProvider = Provider<PricingService>((ref) {
  if (kMockAiBackend) {
    return MockPricingService();
  }
  final tokenStorage = ref.watch(secureTokenStorageProvider);
  return HttpPricingService(tokenStorage: tokenStorage);
});

// --- Repository Providers ---
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return ProductRepository(apiService: apiService);
});

// --- Sync Service Provider ---
final syncServiceProvider = Provider<SyncService>((ref) {
  final repo = ref.watch(productRepositoryProvider);
  final service = SyncService(productRepository: repo);
  ref.onDispose(() => service.dispose());
  return service;
});

// --- Connectivity Provider ---
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);

  await for (final results in connectivity.onConnectivityChanged) {
    yield results.any((r) => r != ConnectivityResult.none);
  }
});

const _unset = Object();

List<String> _stringList(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : <String>[];

List<String>? _stringListOrNull(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : null;

QueueStatus? _queueStatus(dynamic value) {
  if (value is int && value >= 0 && value < QueueStatus.values.length) {
    return QueueStatus.values[value];
  }
  return null;
}

// --- Product List State Notifier ---
class ProductListNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  final ProductRepository _repository;
  final Ref _ref;
  final SyncService _syncService;
  late final VoidCallback _syncListener;

  ProductListNotifier(this._repository, this._ref)
    : _syncService = _ref.read(syncServiceProvider),
      super(const AsyncValue.loading()) {
    _syncListener = () {
      final syncState = _syncService.syncState.value;
      if (syncState == SyncState.completed || syncState == SyncState.idle) {
        unawaited(loadProducts(forceRefresh: true));
      }
    };
    _syncService.syncState.addListener(_syncListener);
    loadProducts();
  }

  Future<void> loadProducts({bool forceRefresh = false}) async {
    state = const AsyncValue.loading();
    try {
      final isOnline = _ref.read(connectivityProvider).value ?? true;
      final products = await _repository.getProducts(
        forceRefresh: forceRefresh,
        isOnline: isOnline,
      );
      state = AsyncValue.data(products);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Product> addProduct(Product product) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    final artisanId = _ref.read(userProfileProvider).id;
    final created = await _repository.addProduct(
      product,
      isOnline: isOnline,
      artisanId: artisanId.isNotEmpty ? artisanId : null,
    );
    await loadProducts();
    return created;
  }

  Future<Product> updateProduct(Product product, {String? idempotencyKey}) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    final updated = await _repository.updateProduct(
      product,
      isOnline: isOnline,
      idempotencyKey: idempotencyKey,
    );
    await loadProducts();
    return updated;
  }

  Future<void> deleteProduct(String id) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    await _repository.deleteProduct(id, isOnline: isOnline);
    await loadProducts();
  }

  Future<Product> approveAndPublishProduct(
    String productId, {
    int? revision,
    String? contentHash,
    String? idempotencyKey,
    String? reviewedChecksum,
  }) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    final published = await _repository.approveAndPublishProduct(
      productId,
      revision: revision,
      contentHash: contentHash,
      isOnline: isOnline,
      idempotencyKey: idempotencyKey,
      reviewedChecksum: reviewedChecksum,
    );
    await loadProducts();
    return published;
  }

  Future<Product> unpublishProduct(
    String productId, {
    String? idempotencyKey,
  }) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    final unpublished = await _repository.unpublishProduct(
      productId,
      isOnline: isOnline,
      idempotencyKey: idempotencyKey,
    );
    await loadProducts();
    return unpublished;
  }

  Future<int> syncQueue() async {
    final count = await _syncService.triggerSync();
    await loadProducts();
    return count;
  }

  @override
  void dispose() {
    _syncService.syncState.removeListener(_syncListener);
    super.dispose();
  }
}

final productListProvider =
    StateNotifierProvider<ProductListNotifier, AsyncValue<List<Product>>>((
      ref,
    ) {
      final repository = ref.watch(productRepositoryProvider);
      final notifier = ProductListNotifier(repository, ref);
      ref.watch(syncServiceProvider);
      ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
        if (next.value == true && previous?.value != true) {
          unawaited(notifier.syncQueue());
        }
      });
      return notifier;
    });

// --- User Profile Provider ---
class UserProfileNotifier extends StateNotifier<UserProfile> {
  static const String _boxName = 'user_profile_box';
  static const String _keyProfile = 'current_profile';

  UserProfileNotifier()
    : super(
        UserProfile(
          id: 'artisan_01',
          name: 'Rameshwar Lal Kumhar',
          phone: '+91 98765 43210',
          craftType: 'Terracotta Pottery',
          locationCluster: 'Kumhar Gram, Delhi NCR',
          preferredLanguage: 'en',
        ),
      ) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box<UserProfile>(_boxName);
      final saved = box.get(_keyProfile);
      if (saved != null) {
        state = saved;
      }
    }
  }

  Future<void> reloadProfile() async {
    await _loadProfile();
  }

  Future<void> updateProfile(UserProfile profile) async {
    state = profile;
    if (Hive.isBoxOpen(_boxName)) {
      final box = Hive.box<UserProfile>(_boxName);
      await box.put(_keyProfile, profile);
    }
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
      return UserProfileNotifier();
    });

// --- Add Product Flow Draft Model & Notifier ---
class AddProductDraft {
  final String draftId;
  final int currentStep; // 0 to 4
  final String originalImagePath;
  final String enhancedImagePath;
  final bool isEnhanced;
  final String immutablePhotoSnapshotPath;
  final String? immutablePhotoSnapshotSha256;
  final String recordedAudioPath;
  final String voiceTranscript;
  final double transcriptionConfidence;
  final String manualDescription;
  final String titleEn;
  final String titleHi;
  final String descriptionEn;
  final String descriptionHi;
  final String category;
  final List<String> tags;
  final double rawMaterialCost;
  final double laborHours;
  final double hourlyRate;
  final double floorPrice;
  final double suggestedPrice;
  final double minPrice;
  final double maxPrice;
  final double finalPrice;
  final String pricingReasoning;
  final String pricingReasoningHi;
  final double confidenceScore;
  final String marketPosition;
  final List<ComparableProduct> comparableProducts;
  final bool isAiProcessing;
  final bool isPricingProcessing;
  final bool isRegenerating; // true only during an in-place Regenerate on Step 3
  final List<String> additionalImagePaths;
  final bool isRetakeFlow;
  final bool hasExistingDraft;
  final bool resumePromptHandled;
  final bool hasCorruptedDraft;
  final String? imageQueueItemId;
  final String? voiceQueueItemId;
  final QueueStatus imageQueueStatus;
  final QueueStatus voiceQueueStatus;
  final String? mediaId;
  final String? originalMediaId;
  final String? sha256Checksum;
  final bool isDegraded;
  final String? degradedReason;
  final String? imageEnhanceOpId;
  final String? voiceListingOpId;
  final String? pricingOpId;
  final bool isVoiceDegraded;
  final String? voiceDegradedReason;
  final bool isListingDegraded;
  final String? listingDegradedReason;
  final bool isPricingDegraded;
  final String? pricingDegradedReason;
  final int imageInputGeneration;
  final int? boundMediaGeneration;
  final int pricingInputGeneration;
  final String? pricingFingerprint;
  final int voiceInputGeneration;
  final String? voiceFingerprint;
  final int listingInputGeneration;
  final String? listingFingerprint;

  const AddProductDraft({
    this.draftId = '',
    this.currentStep = 0,
    this.originalImagePath = '',
    this.enhancedImagePath = '',
    this.isEnhanced = false,
    this.immutablePhotoSnapshotPath = '',
    this.immutablePhotoSnapshotSha256,
    this.recordedAudioPath = '',
    this.voiceTranscript = '',
    this.transcriptionConfidence = 1.0,
    this.manualDescription = '',
    this.titleEn = '',
    this.titleHi = '',
    this.descriptionEn = '',
    this.descriptionHi = '',
    this.category = '',
    this.tags = const [],
    this.rawMaterialCost = 0.0,
    this.laborHours = 0.0,
    this.hourlyRate = 0.0,
    this.floorPrice = 0.0,
    this.suggestedPrice = 0.0,
    this.minPrice = 0.0,
    this.maxPrice = 0.0,
    this.finalPrice = 0.0,
    this.pricingReasoning = '',
    this.pricingReasoningHi = '',
    this.confidenceScore = 0.0,
    this.marketPosition = '',
    this.comparableProducts = const [],
    this.isAiProcessing = false,
    this.isPricingProcessing = false,
    this.isRegenerating = false,
    this.additionalImagePaths = const [],
    this.isRetakeFlow = false,
    this.hasExistingDraft = false,
    this.resumePromptHandled = false,
    this.hasCorruptedDraft = false,
    this.imageQueueItemId,
    this.voiceQueueItemId,
    this.imageQueueStatus = QueueStatus.completed,
    this.voiceQueueStatus = QueueStatus.completed,
    this.mediaId,
    this.originalMediaId,
    this.sha256Checksum,
    this.isDegraded = false,
    this.degradedReason,
    this.imageEnhanceOpId,
    this.voiceListingOpId,
    this.pricingOpId,
    this.isVoiceDegraded = false,
    this.voiceDegradedReason,
    this.isListingDegraded = false,
    this.listingDegradedReason,
    this.isPricingDegraded = false,
    this.pricingDegradedReason,
    this.imageInputGeneration = 0,
    this.boundMediaGeneration,
    this.pricingInputGeneration = 0,
    this.pricingFingerprint,
    this.voiceInputGeneration = 0,
    this.voiceFingerprint,
    this.listingInputGeneration = 0,
    this.listingFingerprint,
  });

  AddProductDraft copyWith({
    String? draftId,
    int? currentStep,
    String? originalImagePath,
    String? enhancedImagePath,
    bool? isEnhanced,
    String? immutablePhotoSnapshotPath,
    Object? immutablePhotoSnapshotSha256 = _unset,
    String? recordedAudioPath,
    String? voiceTranscript,
    double? transcriptionConfidence,
    String? manualDescription,
    String? titleEn,
    String? titleHi,
    String? descriptionEn,
    String? descriptionHi,
    String? category,
    List<String>? tags,
    double? rawMaterialCost,
    double? laborHours,
    double? hourlyRate,
    double? floorPrice,
    double? suggestedPrice,
    double? minPrice,
    double? maxPrice,
    double? finalPrice,
    String? pricingReasoning,
    String? pricingReasoningHi,
    double? confidenceScore,
    String? marketPosition,
    List<ComparableProduct>? comparableProducts,
    bool? isAiProcessing,
    bool? isPricingProcessing,
    bool? isRegenerating,
    List<String>? additionalImagePaths,
    bool? isRetakeFlow,
    bool? hasExistingDraft,
    bool? resumePromptHandled,
    bool? hasCorruptedDraft,
    Object? imageQueueItemId = _unset,
    Object? voiceQueueItemId = _unset,
    QueueStatus? imageQueueStatus,
    QueueStatus? voiceQueueStatus,
    Object? mediaId = _unset,
    Object? originalMediaId = _unset,
    Object? sha256Checksum = _unset,
    bool? isDegraded,
    Object? degradedReason = _unset,
    Object? imageEnhanceOpId = _unset,
    Object? voiceListingOpId = _unset,
    Object? pricingOpId = _unset,
    bool? isVoiceDegraded,
    Object? voiceDegradedReason = _unset,
    bool? isListingDegraded,
    Object? listingDegradedReason = _unset,
    bool? isPricingDegraded,
    Object? pricingDegradedReason = _unset,
    int? imageInputGeneration,
    Object? boundMediaGeneration = _unset,
    int? pricingInputGeneration,
    Object? pricingFingerprint = _unset,
    int? voiceInputGeneration,
    Object? voiceFingerprint = _unset,
    int? listingInputGeneration,
    Object? listingFingerprint = _unset,
  }) {
    return AddProductDraft(
      draftId: draftId ?? this.draftId,
      currentStep: currentStep ?? this.currentStep,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      enhancedImagePath: enhancedImagePath ?? this.enhancedImagePath,
      isEnhanced: isEnhanced ?? this.isEnhanced,
      immutablePhotoSnapshotPath:
          immutablePhotoSnapshotPath ?? this.immutablePhotoSnapshotPath,
      immutablePhotoSnapshotSha256:
          identical(immutablePhotoSnapshotSha256, _unset)
              ? this.immutablePhotoSnapshotSha256
              : immutablePhotoSnapshotSha256 as String?,
      recordedAudioPath: recordedAudioPath ?? this.recordedAudioPath,
      voiceTranscript: voiceTranscript ?? this.voiceTranscript,
      transcriptionConfidence:
          transcriptionConfidence ?? this.transcriptionConfidence,
      manualDescription: manualDescription ?? this.manualDescription,
      titleEn: titleEn ?? this.titleEn,
      titleHi: titleHi ?? this.titleHi,
      descriptionEn: descriptionEn ?? this.descriptionEn,
      descriptionHi: descriptionHi ?? this.descriptionHi,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      rawMaterialCost: rawMaterialCost ?? this.rawMaterialCost,
      laborHours: laborHours ?? this.laborHours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      floorPrice: floorPrice ?? this.floorPrice,
      suggestedPrice: suggestedPrice ?? this.suggestedPrice,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      finalPrice: finalPrice ?? this.finalPrice,
      pricingReasoning: pricingReasoning ?? this.pricingReasoning,
      pricingReasoningHi: pricingReasoningHi ?? this.pricingReasoningHi,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      marketPosition: marketPosition ?? this.marketPosition,
      comparableProducts: comparableProducts ?? this.comparableProducts,
      isAiProcessing: isAiProcessing ?? this.isAiProcessing,
      isPricingProcessing: isPricingProcessing ?? this.isPricingProcessing,
      isRegenerating: isRegenerating ?? this.isRegenerating,
      additionalImagePaths: additionalImagePaths ?? this.additionalImagePaths,
      isRetakeFlow: isRetakeFlow ?? this.isRetakeFlow,
      hasExistingDraft: hasExistingDraft ?? this.hasExistingDraft,
      resumePromptHandled: resumePromptHandled ?? this.resumePromptHandled,
      hasCorruptedDraft: hasCorruptedDraft ?? this.hasCorruptedDraft,
      imageQueueItemId: identical(imageQueueItemId, _unset)
          ? this.imageQueueItemId
          : imageQueueItemId as String?,
      voiceQueueItemId: identical(voiceQueueItemId, _unset)
          ? this.voiceQueueItemId
          : voiceQueueItemId as String?,
      imageQueueStatus: imageQueueStatus ?? this.imageQueueStatus,
      voiceQueueStatus: voiceQueueStatus ?? this.voiceQueueStatus,
      mediaId: identical(mediaId, _unset) ? this.mediaId : mediaId as String?,
      originalMediaId: identical(originalMediaId, _unset)
          ? this.originalMediaId
          : originalMediaId as String?,
      sha256Checksum: identical(sha256Checksum, _unset)
          ? this.sha256Checksum
          : sha256Checksum as String?,
      isDegraded: isDegraded ?? this.isDegraded,
      degradedReason: identical(degradedReason, _unset)
          ? this.degradedReason
          : degradedReason as String?,
      imageEnhanceOpId: identical(imageEnhanceOpId, _unset)
          ? this.imageEnhanceOpId
          : imageEnhanceOpId as String?,
      voiceListingOpId: identical(voiceListingOpId, _unset)
          ? this.voiceListingOpId
          : voiceListingOpId as String?,
      pricingOpId: identical(pricingOpId, _unset)
          ? this.pricingOpId
          : pricingOpId as String?,
      isVoiceDegraded: isVoiceDegraded ?? this.isVoiceDegraded,
      voiceDegradedReason: identical(voiceDegradedReason, _unset)
          ? this.voiceDegradedReason
          : voiceDegradedReason as String?,
      isListingDegraded: isListingDegraded ?? this.isListingDegraded,
      listingDegradedReason: identical(listingDegradedReason, _unset)
          ? this.listingDegradedReason
          : listingDegradedReason as String?,
      isPricingDegraded: isPricingDegraded ?? this.isPricingDegraded,
      pricingDegradedReason: identical(pricingDegradedReason, _unset)
          ? this.pricingDegradedReason
          : pricingDegradedReason as String?,
      imageInputGeneration: imageInputGeneration ?? this.imageInputGeneration,
      boundMediaGeneration: identical(boundMediaGeneration, _unset)
          ? this.boundMediaGeneration
          : boundMediaGeneration as int?,
      pricingInputGeneration: pricingInputGeneration ?? this.pricingInputGeneration,
      pricingFingerprint: identical(pricingFingerprint, _unset)
          ? this.pricingFingerprint
          : pricingFingerprint as String?,
      voiceInputGeneration: voiceInputGeneration ?? this.voiceInputGeneration,
      voiceFingerprint: identical(voiceFingerprint, _unset)
          ? this.voiceFingerprint
          : voiceFingerprint as String?,
      listingInputGeneration: listingInputGeneration ?? this.listingInputGeneration,
      listingFingerprint: identical(listingFingerprint, _unset)
          ? this.listingFingerprint
          : listingFingerprint as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'draft_id': draftId,
      'current_step': currentStep,
      'original_image_path': originalImagePath,
      'enhanced_image_path': enhancedImagePath,
      'is_enhanced': isEnhanced,
      'immutable_photo_snapshot_path': immutablePhotoSnapshotPath,
      'immutable_photo_snapshot_sha256': immutablePhotoSnapshotSha256,
      'recorded_audio_path': recordedAudioPath,
      'voice_transcript': voiceTranscript,
      'transcription_confidence': transcriptionConfidence,
      'manual_description': manualDescription,
      'title_en': titleEn,
      'title_hi': titleHi,
      'description_en': descriptionEn,
      'description_hi': descriptionHi,
      'category': category,
      'tags': tags,
      'raw_material_cost': rawMaterialCost,
      'labor_hours': laborHours,
      'hourly_rate': hourlyRate,
      'floor_price': floorPrice,
      'suggested_price': suggestedPrice,
      'min_price': minPrice,
      'max_price': maxPrice,
      'final_price': finalPrice,
      'pricing_reasoning': pricingReasoning,
      'pricing_reasoning_hi': pricingReasoningHi,
      'confidence_score': confidenceScore,
      'market_position': marketPosition,
      'comparable_products': comparableProducts.map((c) => c.toJson()).toList(),
      'additional_image_paths': additionalImagePaths,
      'image_queue_item_id': imageQueueItemId,
      'voice_queue_item_id': voiceQueueItemId,
      'image_queue_status': imageQueueStatus.name,
      'voice_queue_status': voiceQueueStatus.name,
      'media_id': mediaId,
      'original_media_id': originalMediaId,
      'sha256_checksum': sha256Checksum,
      'is_degraded': isDegraded,
      'degraded_reason': degradedReason,
      'image_enhance_op_id': imageEnhanceOpId,
      'voice_listing_op_id': voiceListingOpId,
      'pricing_op_id': pricingOpId,
      'is_voice_degraded': isVoiceDegraded,
      'voice_degraded_reason': voiceDegradedReason,
      'is_listing_degraded': isListingDegraded,
      'listing_degraded_reason': listingDegradedReason,
      'is_pricing_degraded': isPricingDegraded,
      'pricing_degraded_reason': pricingDegradedReason,
      'image_input_generation': imageInputGeneration,
      'bound_media_generation': boundMediaGeneration,
      'pricing_input_generation': pricingInputGeneration,
      'pricing_fingerprint': pricingFingerprint,
      'voice_input_generation': voiceInputGeneration,
      'voice_fingerprint': voiceFingerprint,
      'listing_input_generation': listingInputGeneration,
      'listing_fingerprint': listingFingerprint,
    };
  }

  factory AddProductDraft.fromJson(Map<String, dynamic> json) {
    return AddProductDraft(
      draftId: json['draft_id'] as String? ?? '',
      currentStep: (json['current_step'] as num?)?.toInt() ?? 0,
      originalImagePath: json['original_image_path'] as String? ?? '',
      enhancedImagePath: json['enhanced_image_path'] as String? ?? '',
      isEnhanced: json['is_enhanced'] as bool? ?? false,
      immutablePhotoSnapshotPath: json['immutable_photo_snapshot_path'] as String? ?? '',
      immutablePhotoSnapshotSha256: json['immutable_photo_snapshot_sha256'] as String?,
      recordedAudioPath: json['recorded_audio_path'] as String? ?? '',
      voiceTranscript: json['voice_transcript'] as String? ?? '',
      transcriptionConfidence: (json['transcription_confidence'] as num?)?.toDouble() ?? 1.0,
      manualDescription: json['manual_description'] as String? ?? '',
      titleEn: json['title_en'] as String? ?? '',
      titleHi: json['title_hi'] as String? ?? '',
      descriptionEn: json['description_en'] as String? ?? '',
      descriptionHi: json['description_hi'] as String? ?? '',
      category: json['category'] as String? ?? '',
      tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : const [],
      rawMaterialCost: (json['raw_material_cost'] as num?)?.toDouble() ?? 0.0,
      laborHours: (json['labor_hours'] as num?)?.toDouble() ?? 0.0,
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      floorPrice: (json['floor_price'] as num?)?.toDouble() ?? 0.0,
      suggestedPrice: (json['suggested_price'] as num?)?.toDouble() ?? 0.0,
      minPrice: (json['min_price'] as num?)?.toDouble() ?? 0.0,
      maxPrice: (json['max_price'] as num?)?.toDouble() ?? 0.0,
      finalPrice: (json['final_price'] as num?)?.toDouble() ?? 0.0,
      pricingReasoning: json['pricing_reasoning'] as String? ?? '',
      pricingReasoningHi: json['pricing_reasoning_hi'] as String? ?? '',
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      marketPosition: json['market_position'] as String? ?? '',
      comparableProducts: json['comparable_products'] != null
          ? (json['comparable_products'] as List)
              .whereType<Map>()
              .map((c) => ComparableProduct.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : const [],
      additionalImagePaths: json['additional_image_paths'] != null
          ? List<String>.from(json['additional_image_paths'] as List)
          : const [],
      imageQueueItemId: json['image_queue_item_id'] as String?,
      voiceQueueItemId: json['voice_queue_item_id'] as String?,
      imageQueueStatus: QueueStatus.values.firstWhere(
        (e) => e.name == json['image_queue_status'],
        orElse: () => QueueStatus.completed,
      ),
      voiceQueueStatus: QueueStatus.values.firstWhere(
        (e) => e.name == json['voice_queue_status'],
        orElse: () => QueueStatus.completed,
      ),
      mediaId: json['media_id'] as String?,
      originalMediaId: json['original_media_id'] as String?,
      sha256Checksum: json['sha256_checksum'] as String?,
      isDegraded: json['is_degraded'] as bool? ?? false,
      degradedReason: json['degraded_reason'] as String?,
      imageEnhanceOpId: json['image_enhance_op_id'] as String?,
      voiceListingOpId: json['voice_listing_op_id'] as String?,
      pricingOpId: json['pricing_op_id'] as String?,
      isVoiceDegraded: json['is_voice_degraded'] as bool? ?? false,
      voiceDegradedReason: json['voice_degraded_reason'] as String?,
      isListingDegraded: json['is_listing_degraded'] as bool? ?? false,
      listingDegradedReason: json['listing_degraded_reason'] as String?,
      isPricingDegraded: json['is_pricing_degraded'] as bool? ?? false,
      pricingDegradedReason: json['pricing_degraded_reason'] as String?,
      imageInputGeneration: (json['image_input_generation'] as num?)?.toInt() ?? 0,
      boundMediaGeneration: (json['bound_media_generation'] as num?)?.toInt(),
      pricingInputGeneration: (json['pricing_input_generation'] as num?)?.toInt() ?? 0,
      pricingFingerprint: json['pricing_fingerprint'] as String?,
      voiceInputGeneration: (json['voice_input_generation'] as num?)?.toInt() ?? 0,
      voiceFingerprint: json['voice_fingerprint'] as String?,
      listingInputGeneration: (json['listing_input_generation'] as num?)?.toInt() ?? 0,
      listingFingerprint: json['listing_fingerprint'] as String?,
    );
  }

  static void validateSnapshotSchema(Map<String, dynamic> json) {
    if (json['__version'] != 1) {
      throw FormatException('Unsupported draft snapshot version: ${json['__version']}');
    }
    final draftId = json['draft_id'];
    if (draftId is! String || draftId.trim().isEmpty) {
      throw const FormatException('Missing or invalid draft_id in snapshot schema');
    }
    if (json['current_step'] != null && json['current_step'] is! int) {
      throw const FormatException('Invalid current_step in snapshot schema');
    }
    if (json['tags'] != null && json['tags'] is! List) {
      throw const FormatException('Invalid tags in snapshot schema');
    }
    if (json['additional_image_paths'] != null && json['additional_image_paths'] is! List) {
      throw const FormatException('Invalid additional_image_paths in snapshot schema');
    }
  }
}

class AddProductFlowNotifier extends StateNotifier<AddProductDraft> {
  static const String snapshotKey = 'active_draft_snapshot';
  final Ref _ref;
  final Lock _draftLock = Lock();
  int _draftSaveSeq = 0;
  bool _isReconciling = false;
  bool _isMigrating = false;
  bool get isMigrating => _isMigrating;
  StreamSubscription<List<QueueItem>>? _imageQueueSubscription;
  StreamSubscription<List<QueueItem>>? _voiceQueueSubscription;
  bool _processingSubmissionInProgress = false;
  Completer<bool>? _imageEnhancingCompleter;
  Map<String, dynamic>? _pendingDraft;
  Map<String, dynamic>? _pendingDraftSnapshot;

  // Tracks whether an image-enhancement request is actually in flight right
  // now. This is distinct from `state.isEnhanced`, which only tells us
  // whether enhancement has ever *succeeded* — when the backend is down,
  // isEnhanced stays false forever even after the request has given up,
  // which is what caused the AI-processing spinner to hang indefinitely.
  bool _imageEnhancementInFlight = false;

  // Tracks whether a listing-generation request (from manual description or
  // from a transcribed voice note) is actually in flight right now.
  bool _listingGenerationInFlight = false;

  // isAiProcessing used to be written independently by several different
  // async completions (image enhancement, listing generation, the voice
  // queue watcher), each one clobbering whatever the others had just set.
  // That's what caused the spinner to flap on/off — e.g. image enhancement
  // finishes and turns it off, then an unrelated voice-queue update arrives
  // a moment later and turns it back on — which tore down and rebuilt the
  // full-screen loader (resetting its "go back" timer and flashing the
  // screen behind it). Instead, isAiProcessing is now always derived from
  // the full set of "is anything still pending" signals in one place.
  void _recomputeAiProcessing() {
    final imageQueuePending = state.imageQueueItemId != null &&
        state.imageQueueItemId!.isNotEmpty &&
        state.imageQueueStatus != QueueStatus.completed &&
        state.imageQueueStatus != QueueStatus.failed;
    final voiceQueuePending = state.voiceQueueItemId != null &&
        state.voiceQueueItemId!.isNotEmpty &&
        state.voiceQueueStatus != QueueStatus.completed &&
        state.voiceQueueStatus != QueueStatus.failed;
    final stillProcessing = _imageEnhancementInFlight ||
        _listingGenerationInFlight ||
        imageQueuePending ||
        voiceQueuePending;

    // Once the watchdog has forcibly closed the loader for this generation,
    // don't let it flip back on. imageQueuePending/voiceQueuePending have no
    // timeout of their own — they just mirror whatever OfflineSyncService's
    // background retry loop reports — so if the backend never responds, that
    // loop can keep reporting "pending" indefinitely, and every one of those
    // updates used to re-trigger this method and re-open the full-screen
    // loader right after the watchdog had just closed it. The item keeps
    // syncing in the background regardless; it just can't hold the UI open
    // anymore once we've already given up waiting on it.
    if (_watchdogFiredForGen == _aiProcessingGen) return;

    if (state.isAiProcessing != stillProcessing) {
      state = state.copyWith(isAiProcessing: stillProcessing);
    }
  }

  // Bumped every time submitForAiProcessing() starts a new submission or the
  // user backs out via cancelAiProcessing(). Async callbacks capture the
  // generation they were started with and no-op if it's gone stale, so a
  // slow response can't resurrect the full-screen loader after the user has
  // already navigated away from it.
  int _aiProcessingGen = 0;

  // Protect against duplicate or concurrent replays of the same in-flight operation.
  final Set<String> _inFlightReplayOpIds = {};

  // Hard backstop: no matter what combination of timeouts/queue states is in
  // play, the AI-processing spinner is never allowed to stay on forever.
  Timer? _aiProcessingWatchdog;

  // Generation the watchdog last forced the spinner off for. See the check
  // at the top of _recomputeAiProcessing — this is what stops a stale
  // queue-status update from re-opening the loader after the watchdog has
  // already given up on this submission.
  int? _watchdogFiredForGen;

  void _startAiProcessingWatchdog(int gen) {
    _aiProcessingWatchdog?.cancel();
    _aiProcessingWatchdog = Timer(const Duration(seconds: 32), () {
      if (gen != _aiProcessingGen) return;
      _watchdogFiredForGen = gen;
      if (state.isAiProcessing) {
        debugPrint(
          '[AddProductFlow] AI-processing watchdog fired — forcing spinner off.',
        );
        state = state.copyWith(isAiProcessing: false);
        _persistDraft();
      }
    });
  }

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  final List<Future<void>> _activeBackgroundFutures = [];

  void _trackBackgroundFuture(Future<void> future) {
    _activeBackgroundFutures.add(future);
    future.whenComplete(() {
      _activeBackgroundFutures.remove(future);
    }).ignore();
  }

  /// Awaits all currently active background futures.
  /// Useful for deterministic teardown in tests or clean shutdowns.
  Future<void> awaitActiveBackgroundFutures() async {
    while (_activeBackgroundFutures.isNotEmpty) {
      final futures = List<Future<void>>.from(_activeBackgroundFutures);
      await Future.wait(futures).catchError((_) => <void>[]);
    }
  }

  AddProductFlowNotifier(this._ref)
    : super(
        AddProductDraft(
          draftId: 'draft_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ) {
    _loadDraft();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _imageQueueSubscription?.cancel();
    _voiceQueueSubscription?.cancel();
    _aiProcessingWatchdog?.cancel();
    super.dispose();
  }

  void _loadDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');

      // 1. Single source of truth: active_draft_snapshot
      if (box.containsKey(snapshotKey)) {
        final raw = box.get(snapshotKey);
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw.toString());
            if (decoded is Map<String, dynamic>) {
              AddProductDraft.validateSnapshotSchema(decoded);
              _pendingDraftSnapshot = decoded;
              state = state.copyWith(
                hasExistingDraft: true,
                resumePromptHandled: false,
              );
              return;
            } else {
              throw const FormatException('Snapshot payload is not a JSON object');
            }
          } catch (e) {
            debugPrint('[AddProductFlow] Corrupt active draft snapshot detected: $e');
            // INVARIANT: A corrupt new snapshot must trigger recovery, not silently fall back to older legacy values.
            state = state.copyWith(
              hasCorruptedDraft: true,
              hasExistingDraft: true,
              resumePromptHandled: false,
            );
            return;
          }
        }
      }

      // 2. Check for legacy multi-key writes for non-destructive migration
      final legacyKeys = ['draft_id', 'draft_original_image', 'draft_image'];
      final hasLegacy = legacyKeys.any((k) => box.containsKey(k));
      if (hasLegacy) {
        final values = <String, dynamic>{
          for (final key in box.keys) key.toString(): box.get(key),
        };
        if (values.isNotEmpty &&
            (values['draft_id'] != null ||
                values['draft_original_image'] != null ||
                values['draft_image'] != null)) {
          unawaited(_migrateLegacyDraft(box, values));
        }
      }
    }
  }

  Future<void> _migrateLegacyDraft(Box box, Map<String, dynamic> legacyValues) async {
    _isMigrating = true;
    try {
      await _draftLock.synchronized(() async {
        final draftId = legacyValues['draft_id'] as String? ??
            'draft_${DateTime.now().microsecondsSinceEpoch}';
        final legacyImage = legacyValues['draft_image'] as String? ?? '';
        final origImage =
            legacyValues['draft_original_image'] as String? ?? legacyImage;

        final imageQueueItemId = legacyValues['draft_image_queue_id'] as String? ??
            legacyValues['draft_image_queue_item_id'] as String?;
        final voiceQueueItemId = legacyValues['draft_voice_queue_id'] as String? ??
            legacyValues['draft_voice_queue_item_id'] as String?;
        final imageQueueStatus = _queueStatus(legacyValues['draft_image_queue_status']) ??
            QueueStatus.completed;
        final voiceQueueStatus = _queueStatus(legacyValues['draft_voice_queue_status']) ??
            QueueStatus.completed;
        final additionalImages = _stringList(
          legacyValues['draft_additional_images'] ?? legacyValues['draft_additional_image_paths'],
        );
        final immutableSnapshotPath =
            legacyValues['draft_immutable_photo_snapshot_path'] as String? ?? '';
        final immutableSnapshotSha256 =
            legacyValues['draft_immutable_photo_snapshot_sha256'] as String?;

        final migratedDraft = AddProductDraft(
          draftId: draftId,
          currentStep: (legacyValues['draft_step'] as num?)?.toInt() ?? 0,
          originalImagePath: origImage,
          enhancedImagePath: legacyValues['draft_enhanced_image'] as String? ?? '',
          isEnhanced:
              (legacyValues['draft_enhanced_image'] as String?)?.isNotEmpty == true &&
                  legacyValues['draft_enhanced_image'] != origImage,
          recordedAudioPath: legacyValues['draft_audio'] as String? ?? '',
          voiceTranscript: legacyValues['draft_transcript'] as String? ?? '',
          manualDescription:
              legacyValues['draft_manual_description'] as String? ?? '',
          titleEn: legacyValues['draft_title_en'] as String? ?? '',
          titleHi: legacyValues['draft_title_hi'] as String? ?? '',
          descriptionEn: legacyValues['draft_description_en'] as String? ?? '',
          descriptionHi: legacyValues['draft_description_hi'] as String? ?? '',
          category: legacyValues['draft_category'] as String? ?? '',
          tags: _stringListOrNull(legacyValues['draft_tags']) ?? const [],
          rawMaterialCost:
              (legacyValues['draft_raw_material_cost'] as num?)?.toDouble() ?? 0.0,
          laborHours:
              (legacyValues['draft_labor_hours'] as num?)?.toDouble() ?? 0.0,
          hourlyRate:
              (legacyValues['draft_hourly_rate'] as num?)?.toDouble() ?? 0.0,
          floorPrice:
              (legacyValues['draft_floor_price'] as num?)?.toDouble() ?? 0.0,
          suggestedPrice:
              (legacyValues['draft_suggested_price'] as num?)?.toDouble() ?? 0.0,
          minPrice: (legacyValues['draft_min_price'] as num?)?.toDouble() ?? 0.0,
          maxPrice: (legacyValues['draft_max_price'] as num?)?.toDouble() ?? 0.0,
          finalPrice:
              (legacyValues['draft_final_price'] as num?)?.toDouble() ?? 0.0,
          pricingReasoning:
              legacyValues['draft_pricing_reasoning'] as String? ?? '',
          pricingReasoningHi:
              legacyValues['draft_pricing_reasoning_hi'] as String? ?? '',
          confidenceScore:
              (legacyValues['draft_confidence_score'] as num?)?.toDouble() ?? 0.0,
          marketPosition:
              legacyValues['draft_market_position'] as String? ?? '',
          additionalImagePaths: additionalImages,
          imageQueueItemId: imageQueueItemId,
          voiceQueueItemId: voiceQueueItemId,
          imageQueueStatus: imageQueueStatus,
          voiceQueueStatus: voiceQueueStatus,
          immutablePhotoSnapshotPath: immutableSnapshotPath,
          immutablePhotoSnapshotSha256: immutableSnapshotSha256,
          mediaId: legacyValues['draft_media_id'] as String?,
          originalMediaId: legacyValues['draft_original_media_id'] as String?,
          sha256Checksum: legacyValues['draft_sha256_checksum'] as String?,
          isDegraded: legacyValues['draft_is_degraded'] as bool? ?? false,
          degradedReason: legacyValues['draft_degraded_reason'] as String?,
          imageEnhanceOpId: legacyValues['draft_image_enhance_op_id'] as String?,
          voiceListingOpId: legacyValues['draft_voice_listing_op_id'] as String?,
          pricingOpId: legacyValues['draft_pricing_op_id'] as String?,
          isVoiceDegraded:
              legacyValues['draft_is_voice_degraded'] as bool? ?? false,
          voiceDegradedReason:
              legacyValues['draft_voice_degraded_reason'] as String?,
          isListingDegraded:
              legacyValues['draft_is_listing_degraded'] as bool? ?? false,
          listingDegradedReason:
              legacyValues['draft_listing_degraded_reason'] as String?,
          isPricingDegraded:
              legacyValues['draft_is_pricing_degraded'] as bool? ?? false,
          pricingDegradedReason:
              legacyValues['draft_pricing_degraded_reason'] as String?,
          imageInputGeneration:
              (legacyValues['draft_image_input_generation'] as num?)?.toInt() ?? 0,
          boundMediaGeneration:
              (legacyValues['draft_bound_media_generation'] as num?)?.toInt(),
          pricingInputGeneration:
              (legacyValues['draft_pricing_input_generation'] as num?)?.toInt() ?? 0,
          pricingFingerprint:
              legacyValues['draft_pricing_fingerprint'] as String?,
          voiceInputGeneration:
              (legacyValues['draft_voice_input_generation'] as num?)?.toInt() ?? 0,
          voiceFingerprint: legacyValues['draft_voice_fingerprint'] as String?,
          listingInputGeneration:
              (legacyValues['draft_listing_input_generation'] as num?)?.toInt() ?? 0,
          listingFingerprint:
              legacyValues['draft_listing_fingerprint'] as String?,
        );

        final snapshotData = migratedDraft.toJson();
        snapshotData['__version'] = 1;
        snapshotData['__save_seq'] = ++_draftSaveSeq;
        final jsonStr = jsonEncode(snapshotData);

        // Write snapshot and await durable persistence
        await box.put(snapshotKey, jsonStr);
        await box.flush();

        // Complete semantic readback verification
        final readBack = box.get(snapshotKey) as String?;
        if (readBack == null) {
          throw StateError(
            'Readback verification failed: snapshotKey was null after put',
          );
        }
        final decodedReadBack = jsonDecode(readBack) as Map<String, dynamic>;
        AddProductDraft.validateSnapshotSchema(decodedReadBack);
        if (decodedReadBack['draft_id'] != draftId) {
          throw StateError('Readback verification failed: draft_id mismatch');
        }
        if (decodedReadBack['image_queue_item_id'] != imageQueueItemId) {
          throw StateError('Readback verification failed: image_queue_item_id mismatch');
        }
        if (decodedReadBack['voice_queue_item_id'] != voiceQueueItemId) {
          throw StateError('Readback verification failed: voice_queue_item_id mismatch');
        }
        if (decodedReadBack['image_queue_status'] != imageQueueStatus.name) {
          throw StateError('Readback verification failed: image_queue_status mismatch');
        }
        if (decodedReadBack['voice_queue_status'] != voiceQueueStatus.name) {
          throw StateError('Readback verification failed: voice_queue_status mismatch');
        }
        final readBackAdditional = _stringList(decodedReadBack['additional_image_paths']);
        if (!listEquals(readBackAdditional, additionalImages)) {
          throw StateError('Readback verification failed: additional_image_paths mismatch');
        }

        // Verified! Clean up legacy multi-keys
        for (final k in legacyValues.keys) {
          if (k != snapshotKey) {
            await box.delete(k);
          }
        }
        await box.flush();

        _pendingDraftSnapshot = snapshotData;
        if (mounted) {
          state = state.copyWith(
            hasExistingDraft: true,
            resumePromptHandled: false,
          );
        }
      });
    } catch (e) {
      debugPrint(
        '[AddProductFlow] Legacy draft migration failed; preserving legacy data: $e',
      );
      _pendingDraft = legacyValues;
      if (mounted) {
        state = state.copyWith(
          hasExistingDraft: true,
          resumePromptHandled: false,
        );
      }
    } finally {
      _isMigrating = false;
    }
  }

  Future<void> loadSavedDraftState({
    required String draftId,
    required String originalImagePath,
    required String enhancedImagePath,
    required String transcript,
    String manualDescription = '',
    String titleEn = '',
    String titleHi = '',
    String descriptionEn = '',
    String descriptionHi = '',
    List<String> additionalImagePaths = const [],
    int? savedStep,
    String? recordedAudioPath,
    double? transcriptionConfidence,
    String? category,
    List<String>? tags,
    double? rawMaterialCost,
    double? laborHours,
    double? hourlyRate,
    double? floorPrice,
    double? suggestedPrice,
    double? minPrice,
    double? maxPrice,
    double? finalPrice,
    String? pricingReasoning,
    String? pricingReasoningHi,
    double? confidenceScore,
    String? marketPosition,
    List<ComparableProduct>? comparableProducts,
    String? imageQueueItemId,
    String? voiceQueueItemId,
    QueueStatus? imageQueueStatus,
    QueueStatus? voiceQueueStatus,
    String? mediaId,
    String? originalMediaId,
    String? sha256Checksum,
    bool? isDegraded,
    String? degradedReason,
    String? imageEnhanceOpId,
    String? voiceListingOpId,
    String? pricingOpId,
    bool? isVoiceDegraded,
    String? voiceDegradedReason,
    bool? isListingDegraded,
    String? listingDegradedReason,
    bool? isPricingDegraded,
    String? pricingDegradedReason,
    int? imageInputGeneration,
    int? boundMediaGeneration,
    int? pricingInputGeneration,
    String? pricingFingerprint,
    int? voiceInputGeneration,
    String? voiceFingerprint,
    int? listingInputGeneration,
    String? listingFingerprint,
    String? immutablePhotoSnapshotPath,
    String? immutablePhotoSnapshotSha256,
  }) async {
    final hasImage =
        (originalImagePath.isNotEmpty || enhancedImagePath.isNotEmpty);
    final hasCompletedListing =
        titleEn.isNotEmpty ||
        titleHi.isNotEmpty ||
        descriptionEn.isNotEmpty ||
        descriptionHi.isNotEmpty;

    int computedStep;
    if (!hasImage) {
      computedStep = 0;
    } else if (hasCompletedListing) {
      computedStep = 2;
    } else if (transcript.isNotEmpty || manualDescription.isNotEmpty) {
      computedStep = 1;
    } else {
      computedStep = 0;
    }

    final resolvedStep = savedStep != null && savedStep >= 0 && savedStep <= 4
        ? savedStep
        : computedStep;

    final resolvedImageGen = imageInputGeneration ?? 0;
    final resolvedBoundGen = boundMediaGeneration ?? (mediaId != null ? resolvedImageGen : null);

    state = state.copyWith(
      draftId: draftId,
      originalImagePath: originalImagePath,
      enhancedImagePath: enhancedImagePath,
      isEnhanced:
          enhancedImagePath.isNotEmpty &&
          enhancedImagePath != originalImagePath,
      immutablePhotoSnapshotPath: immutablePhotoSnapshotPath,
      immutablePhotoSnapshotSha256: immutablePhotoSnapshotSha256,
      voiceTranscript: transcript,
      recordedAudioPath: recordedAudioPath ?? '',
      transcriptionConfidence: transcriptionConfidence ?? 1.0,
      manualDescription: manualDescription,
      titleEn: titleEn,
      titleHi: titleHi,
      descriptionEn: descriptionEn,
      descriptionHi: descriptionHi,
      category: category ?? state.category,
      tags: tags ?? state.tags,
      rawMaterialCost: rawMaterialCost ?? state.rawMaterialCost,
      laborHours: laborHours ?? state.laborHours,
      hourlyRate: hourlyRate ?? state.hourlyRate,
      floorPrice: floorPrice ?? state.floorPrice,
      suggestedPrice: suggestedPrice ?? state.suggestedPrice,
      minPrice: minPrice ?? state.minPrice,
      maxPrice: maxPrice ?? state.maxPrice,
      finalPrice: finalPrice ?? state.finalPrice,
      pricingReasoning: pricingReasoning ?? state.pricingReasoning,
      pricingReasoningHi: pricingReasoningHi ?? state.pricingReasoningHi,
      confidenceScore: confidenceScore ?? state.confidenceScore,
      marketPosition: marketPosition ?? state.marketPosition,
      comparableProducts: comparableProducts ?? state.comparableProducts,
      currentStep: resolvedStep,
      additionalImagePaths: additionalImagePaths,
      imageQueueItemId: imageQueueItemId,
      voiceQueueItemId: voiceQueueItemId,
      imageQueueStatus: imageQueueStatus ?? QueueStatus.completed,
      voiceQueueStatus: voiceQueueStatus ?? QueueStatus.completed,
      mediaId: mediaId,
      originalMediaId: originalMediaId,
      sha256Checksum: sha256Checksum,
      isDegraded: isDegraded ?? false,
      degradedReason: degradedReason,
      imageEnhanceOpId: imageEnhanceOpId,
      voiceListingOpId: voiceListingOpId,
      pricingOpId: pricingOpId,
      isVoiceDegraded: isVoiceDegraded ?? false,
      voiceDegradedReason: voiceDegradedReason,
      isListingDegraded: isListingDegraded ?? false,
      listingDegradedReason: listingDegradedReason,
      isPricingDegraded: isPricingDegraded ?? false,
      pricingDegradedReason: pricingDegradedReason,
      imageInputGeneration: resolvedImageGen,
      boundMediaGeneration: resolvedBoundGen,
      pricingInputGeneration: pricingInputGeneration ?? 0,
      pricingFingerprint: pricingFingerprint,
      voiceInputGeneration: voiceInputGeneration ?? 0,
      voiceFingerprint: voiceFingerprint,
      listingInputGeneration: listingInputGeneration ?? 0,
      listingFingerprint: listingFingerprint,
      hasExistingDraft: true,
      resumePromptHandled: false,
      isAiProcessing: false,
    );
    if (imageQueueItemId != null && imageQueueItemId.isNotEmpty) {
      _watchImageQueue(imageQueueItemId);
    }
    if (voiceQueueItemId != null && voiceQueueItemId.isNotEmpty) {
      _watchVoiceQueue(voiceQueueItemId);
    }
    await _persistDraft();
  }

  void markResumePromptVisible() {
    state = state.copyWith(resumePromptHandled: true);
  }

  Future<void> resumeExistingDraft() async {
    if (_pendingDraftSnapshot != null) {
      final snapshot = _pendingDraftSnapshot!;
      final restoredDraft = AddProductDraft.fromJson(snapshot);
      await loadSavedDraftState(
        draftId: restoredDraft.draftId,
        originalImagePath: restoredDraft.originalImagePath,
        enhancedImagePath: restoredDraft.enhancedImagePath,
        transcript: restoredDraft.voiceTranscript,
        recordedAudioPath: restoredDraft.recordedAudioPath,
        manualDescription: restoredDraft.manualDescription,
        titleEn: restoredDraft.titleEn,
        titleHi: restoredDraft.titleHi,
        descriptionEn: restoredDraft.descriptionEn,
        descriptionHi: restoredDraft.descriptionHi,
        additionalImagePaths: restoredDraft.additionalImagePaths,
        savedStep: restoredDraft.currentStep,
        category: restoredDraft.category,
        tags: restoredDraft.tags,
        rawMaterialCost: restoredDraft.rawMaterialCost,
        laborHours: restoredDraft.laborHours,
        hourlyRate: restoredDraft.hourlyRate,
        floorPrice: restoredDraft.floorPrice,
        suggestedPrice: restoredDraft.suggestedPrice,
        minPrice: restoredDraft.minPrice,
        maxPrice: restoredDraft.maxPrice,
        finalPrice: restoredDraft.finalPrice,
        pricingReasoning: restoredDraft.pricingReasoning,
        pricingReasoningHi: restoredDraft.pricingReasoningHi,
        confidenceScore: restoredDraft.confidenceScore,
        marketPosition: restoredDraft.marketPosition,
        imageQueueItemId: restoredDraft.imageQueueItemId,
        voiceQueueItemId: restoredDraft.voiceQueueItemId,
        imageQueueStatus: restoredDraft.imageQueueStatus,
        voiceQueueStatus: restoredDraft.voiceQueueStatus,
        mediaId: restoredDraft.mediaId,
        originalMediaId: restoredDraft.originalMediaId,
        sha256Checksum: restoredDraft.sha256Checksum,
        isDegraded: restoredDraft.isDegraded,
        degradedReason: restoredDraft.degradedReason,
        imageEnhanceOpId: restoredDraft.imageEnhanceOpId,
        voiceListingOpId: restoredDraft.voiceListingOpId,
        pricingOpId: restoredDraft.pricingOpId,
        isVoiceDegraded: restoredDraft.isVoiceDegraded,
        voiceDegradedReason: restoredDraft.voiceDegradedReason,
        isListingDegraded: restoredDraft.isListingDegraded,
        listingDegradedReason: restoredDraft.listingDegradedReason,
        isPricingDegraded: restoredDraft.isPricingDegraded,
        pricingDegradedReason: restoredDraft.pricingDegradedReason,
        imageInputGeneration: restoredDraft.imageInputGeneration,
        boundMediaGeneration: restoredDraft.boundMediaGeneration,
        pricingInputGeneration: restoredDraft.pricingInputGeneration,
        pricingFingerprint: restoredDraft.pricingFingerprint,
        voiceInputGeneration: restoredDraft.voiceInputGeneration,
        voiceFingerprint: restoredDraft.voiceFingerprint,
        listingInputGeneration: restoredDraft.listingInputGeneration,
        listingFingerprint: restoredDraft.listingFingerprint,
        immutablePhotoSnapshotPath: restoredDraft.immutablePhotoSnapshotPath,
        immutablePhotoSnapshotSha256: restoredDraft.immutablePhotoSnapshotSha256,
      );
      _pendingDraftSnapshot = null;
      _pendingDraft = null;
      _hydrateQueueState();
      _trackBackgroundFuture(_reconcileDraftOperations());
      if (mounted) {
        state = state.copyWith(
          hasExistingDraft: false,
          resumePromptHandled: true,
          isAiProcessing: false,
        );
      }
      return;
    }

    final pending = _pendingDraft;
    if (pending != null) {
      final legacyImage = pending['draft_image'] as String? ?? '';
      loadSavedDraftState(
        draftId:
            pending['draft_id'] as String? ??
            'draft_${DateTime.now().microsecondsSinceEpoch}',
        originalImagePath:
            pending['draft_original_image'] as String? ?? legacyImage,
        enhancedImagePath: pending['draft_enhanced_image'] as String? ?? '',
        transcript: pending['draft_transcript'] as String? ?? '',
        recordedAudioPath: pending['draft_audio'] as String? ?? '',
        manualDescription: pending['draft_manual_description'] as String? ?? '',
        titleEn: pending['draft_title_en'] as String? ?? '',
        titleHi: pending['draft_title_hi'] as String? ?? '',
        descriptionEn: pending['draft_description_en'] as String? ?? '',
        descriptionHi: pending['draft_description_hi'] as String? ?? '',
        additionalImagePaths: _stringList(pending['draft_additional_images']),
        savedStep: pending['draft_step'] as int?,
        category: pending['draft_category'] as String?,
        tags: _stringListOrNull(pending['draft_tags']),
        rawMaterialCost: (pending['draft_raw_material_cost'] as num?)
            ?.toDouble(),
        laborHours: (pending['draft_labor_hours'] as num?)?.toDouble(),
        hourlyRate: (pending['draft_hourly_rate'] as num?)?.toDouble(),
        floorPrice: (pending['draft_floor_price'] as num?)?.toDouble(),
        suggestedPrice: (pending['draft_suggested_price'] as num?)?.toDouble(),
        minPrice: (pending['draft_min_price'] as num?)?.toDouble(),
        maxPrice: (pending['draft_max_price'] as num?)?.toDouble(),
        finalPrice: (pending['draft_final_price'] as num?)?.toDouble(),
        pricingReasoning: pending['draft_pricing_reasoning'] as String?,
        pricingReasoningHi: pending['draft_pricing_reasoning_hi'] as String?,
        confidenceScore: (pending['draft_confidence_score'] as num?)?.toDouble(),
        marketPosition: pending['draft_market_position'] as String?,
        comparableProducts: (pending['draft_comparable_products'] as List?)
            ?.map((e) => ComparableProduct.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        imageQueueItemId: pending['draft_image_queue_id'] as String?,
        voiceQueueItemId: pending['draft_voice_queue_id'] as String?,
        imageQueueStatus: _queueStatus(pending['draft_image_queue_status']),
        voiceQueueStatus: _queueStatus(pending['draft_voice_queue_status']),
        mediaId: pending['draft_media_id'] as String?,
        originalMediaId: pending['draft_original_media_id'] as String?,
        sha256Checksum: pending['draft_sha256_checksum'] as String?,
        isDegraded: pending['draft_is_degraded'] as bool? ?? false,
        degradedReason: pending['draft_degraded_reason'] as String?,
        imageEnhanceOpId: pending['draft_image_enhance_op_id'] as String?,
        voiceListingOpId: pending['draft_voice_listing_op_id'] as String?,
        pricingOpId: pending['draft_pricing_op_id'] as String?,
        isVoiceDegraded: pending['draft_is_voice_degraded'] as bool? ?? false,
        voiceDegradedReason: pending['draft_voice_degraded_reason'] as String?,
        isListingDegraded: pending['draft_is_listing_degraded'] as bool? ?? false,
        listingDegradedReason: pending['draft_listing_degraded_reason'] as String?,
        isPricingDegraded: pending['draft_is_pricing_degraded'] as bool? ?? false,
        pricingDegradedReason: pending['draft_pricing_degraded_reason'] as String?,
        imageInputGeneration: (pending['draft_image_input_generation'] as num?)?.toInt(),
        boundMediaGeneration: (pending['draft_bound_media_generation'] as num?)?.toInt(),
        pricingInputGeneration: (pending['draft_pricing_input_generation'] as num?)?.toInt(),
        pricingFingerprint: pending['draft_pricing_fingerprint'] as String?,
        voiceInputGeneration: (pending['draft_voice_input_generation'] as num?)?.toInt(),
        voiceFingerprint: pending['draft_voice_fingerprint'] as String?,
        listingInputGeneration: (pending['draft_listing_input_generation'] as num?)?.toInt(),
        listingFingerprint: pending['draft_listing_fingerprint'] as String?,
      );
      _hydrateQueueState();
      _trackBackgroundFuture(_reconcileDraftOperations());
    }
    _pendingDraft = null;
    if (mounted) {
      state = state.copyWith(
        hasExistingDraft: false,
        resumePromptHandled: true,
        isAiProcessing: false,
      );
    }
  }

  Future<void> _reconcileDraftOperations() async {
    if (!mounted) return;
    if (state.draftId.isEmpty) return;
    if (_isReconciling) {
      debugPrint('[AddProductFlow] Reconcile skipped: already in progress.');
      return;
    }
    _isReconciling = true;

    try {
      if (!mounted) return;
      final currentOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final currentBackend = ApiConfig.baseUrl;

      final ops = await AiOperationStorage.getOperationsForDraft(state.draftId);
      if (!mounted) return;
      for (final op in ops) {
        if (!mounted) return;
        // INVARIANT: Check owner and backend before applying or replaying
        if (op.owner != currentOwner ||
            op.backend != currentBackend ||
            op.draftId != state.draftId) {
          debugPrint(
            '[AddProductFlow] Skipping op ${op.id}: owner/backend/draft mismatch.',
          );
          continue;
        }

        if (op.status == AiOperationRecord.statusCompleted && op.resultData != null) {
          if (op.operationType == 'image_enhance' &&
              op.inputGeneration == state.imageInputGeneration &&
              (state.mediaId == null || state.mediaId!.isEmpty)) {
            final res = op.resultData!;
            final mediaId = res['mediaId'] as String? ?? res['media_id'] as String?;
            final origId = res['originalMediaId'] as String? ?? res['original_media_id'] as String?;
            final checksum = res['sha256Checksum'] as String? ?? res['sha256_checksum'] as String?;
            final displayPath = res['displayPath'] as String? ?? res['enhanced_url'] as String?;
            if (mediaId != null && mediaId.isNotEmpty) {
              if (!mounted) return;
              state = state.copyWith(
                mediaId: mediaId,
                originalMediaId: origId,
                sha256Checksum: checksum,
                enhancedImagePath: (displayPath != null && displayPath.isNotEmpty)
                    ? displayPath
                    : state.enhancedImagePath,
                isEnhanced: displayPath != null &&
                    displayPath.isNotEmpty &&
                    displayPath != state.originalImagePath,
                boundMediaGeneration: op.inputGeneration,
              );
              await _persistDraft();
            }
          } else if (op.operationType == 'pricing_suggest' &&
                     op.inputGeneration == state.pricingInputGeneration &&
                     state.suggestedPrice == 0) {
            final res = op.resultData!;
            final rawFloor = (res['floor_price'] as num?)?.toDouble() ?? state.floorPrice;
            final currentCostFloor = state.floorPrice > 0
                ? state.floorPrice
                : (state.rawMaterialCost + (state.laborHours * state.hourlyRate));
            final effectiveFloor = rawFloor < currentCostFloor ? currentCostFloor : rawFloor;
            final sugPrice = (res['suggested_price'] as num?)?.toDouble() ?? state.suggestedPrice;
            if (!mounted) return;
            state = state.copyWith(
              floorPrice: effectiveFloor,
              suggestedPrice: sugPrice < effectiveFloor ? effectiveFloor : sugPrice,
              minPrice: (res['min_price'] as num?)?.toDouble() ?? state.minPrice,
              maxPrice: (res['max_price'] as num?)?.toDouble() ?? state.maxPrice,
              finalPrice: sugPrice < effectiveFloor ? effectiveFloor : sugPrice,
              confidenceScore: (res['confidence_score'] as num?)?.toDouble() ?? state.confidenceScore,
              marketPosition: res['market_position'] as String? ?? state.marketPosition,
              comparableProducts: res['comparable_products'] != null
                  ? (res['comparable_products'] as List)
                      .whereType<Map>()
                      .map((c) => ComparableProduct.fromJson(Map<String, dynamic>.from(c)))
                      .toList()
                  : state.comparableProducts,
              pricingReasoning: res['reasoning'] as String? ?? state.pricingReasoning,
              pricingReasoningHi: res['reasoning_hi'] as String? ?? state.pricingReasoningHi,
              isPricingDegraded: res['is_degraded'] as bool? ?? state.isPricingDegraded,
              pricingDegradedReason: res['degraded_reason'] as String? ?? state.pricingDegradedReason,
            );
            await _persistDraft();
          } else if (op.operationType == 'listing_generate' &&
                     op.inputGeneration == state.listingInputGeneration &&
                     state.titleEn.isEmpty) {
            final res = op.resultData!;
            if (!mounted) return;
            state = state.copyWith(
              titleEn: res['title_en'] as String? ?? state.titleEn,
              titleHi: res['title_hi'] as String? ?? state.titleHi,
              descriptionEn: res['description_en'] as String? ?? state.descriptionEn,
              descriptionHi: res['description_hi'] as String? ?? state.descriptionHi,
              category: (res['category'] as String?)?.isNotEmpty == true
                  ? res['category'] as String
                  : state.category,
              tags: res['tags'] != null ? List<String>.from(res['tags'] as List) : state.tags,
              isListingDegraded: res['is_degraded'] as bool? ?? state.isListingDegraded,
              listingDegradedReason: res['degraded_reason'] as String? ?? state.listingDegradedReason,
            );
            await _persistDraft();
          }
        } else if (op.status == AiOperationRecord.statusInFlight ||
                   op.status == AiOperationRecord.statusPending) {
          // Replay pending/in-flight operations using original persisted request & idempotency key
          if (op.operationType == 'pricing_suggest' &&
              op.inputGeneration == state.pricingInputGeneration &&
              (state.pricingOpId == null || state.pricingOpId == op.id)) {
            if (state.pricingFingerprint == null || state.pricingFingerprint == op.inputFingerprint) {
              if (!_inFlightReplayOpIds.contains(op.id)) {
                _inFlightReplayOpIds.add(op.id);
                debugPrint('[AddProductFlow] Replaying in-flight pricing operation: ${op.id}');
                final fut = _replayPricingOperation(op).whenComplete(() {
                  _inFlightReplayOpIds.remove(op.id);
                });
                _trackBackgroundFuture(fut);
              }
            }
          } else if (op.operationType == 'listing_generate' &&
                     op.inputGeneration == state.listingInputGeneration &&
                     (state.voiceListingOpId == null || state.voiceListingOpId == op.id)) {
            if (state.listingFingerprint == null || state.listingFingerprint == op.inputFingerprint) {
              if (!_inFlightReplayOpIds.contains(op.id)) {
                _inFlightReplayOpIds.add(op.id);
                debugPrint('[AddProductFlow] Replaying in-flight listing operation: ${op.id}');
                final fut = _replayListingOperation(op).whenComplete(() {
                  _inFlightReplayOpIds.remove(op.id);
                });
                _trackBackgroundFuture(fut);
              }
            }
          } else if (op.operationType == 'image_enhance' &&
                     op.inputGeneration == state.imageInputGeneration &&
                     (state.imageEnhanceOpId == null || state.imageEnhanceOpId == op.id)) {
            if (!_inFlightReplayOpIds.contains(op.id)) {
              _inFlightReplayOpIds.add(op.id);
              debugPrint('[AddProductFlow] Replaying in-flight image enhancement operation: ${op.id}');
              final fut = _replayImageEnhanceOperation(op).whenComplete(() {
                _inFlightReplayOpIds.remove(op.id);
              });
              _trackBackgroundFuture(fut);
            }
          }
        }
      }
    } on CorruptAiOperationException catch (e) {
      debugPrint('[AddProductFlow] Corrupt AI operation storage detected: $e');
      if (mounted) {
        state = state.copyWith(hasCorruptedDraft: true);
      }
    } catch (e) {
      debugPrint('[AddProductFlow] Error reconciling draft operations: $e');
    } finally {
      _isReconciling = false;
    }
  }

  Future<void> _replayImageEnhanceOperation(AiOperationRecord op) async {
    final enhancerService = _ref.read(imageEnhancerServiceProvider);
    final req = op.requestSnapshot;
    final opId = op.id;
    final opGeneration = op.inputGeneration;
    final owner = op.owner;

    // 1. Validate identity preconditions before dispatch
    final preOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
    final preBackend = ApiConfig.baseUrl;
    if (preOwner != owner ||
        preBackend != op.backend ||
        state.draftId != op.draftId ||
        (state.imageEnhanceOpId != null && state.imageEnhanceOpId != op.id) ||
        state.imageInputGeneration != opGeneration) {
      debugPrint('[AddProductFlow] Replay precondition mismatch for op $opId (owner, backend, draft, opId, or gen). Aborting replay.');
      return;
    }

    // 2. Validate immutable image input path (never silently substitute mutable draft image)
    final imagePath = req['image_path'] as String? ?? req['originalImagePath'] as String?;
    if (imagePath == null || imagePath.isEmpty) {
      debugPrint('[AddProductFlow] Cannot replay image enhancement without immutable persisted image path.');
      await AiOperationStorage.updateResult(
        opId,
        status: AiOperationRecord.statusFailed,
        resultData: {'error': 'Missing persisted image path in request snapshot'},
      );
      if (mounted) {
        state = state.copyWith(
          isDegraded: true,
          degradedReason: 'Persisted source image path is missing for enhancement replay',
        );
        await _persistDraft();
      }
      return;
    }

    // 3. Verify disk existence and exact input fingerprint
    final file = File(imagePath);
    if (!file.existsSync()) {
      debugPrint('[AddProductFlow] Source image file missing on disk: $imagePath');
      await AiOperationStorage.updateResult(
        opId,
        status: AiOperationRecord.statusFailed,
        resultData: {'error': 'Source image file missing on disk: $imagePath'},
      );
      if (mounted) {
        state = state.copyWith(
          isDegraded: true,
          degradedReason: 'Original image file is missing from disk for enhancement replay',
        );
        await _persistDraft();
      }
      return;
    }

    if (op.inputFingerprint.isNotEmpty) {
      final currentFingerprint = await AiOperationRecord.computeFingerprint(
        operationType: op.operationType,
        owner: op.owner,
        backend: op.backend,
        inputs: {'draft_id': op.draftId, 'generation': op.inputGeneration},
        files: [file],
      );
      if (currentFingerprint != op.inputFingerprint) {
        debugPrint('[AddProductFlow] Source image fingerprint mismatch for op $opId. Expected ${op.inputFingerprint}, got $currentFingerprint');
        await AiOperationStorage.updateResult(
          opId,
          status: AiOperationRecord.statusFailed,
          resultData: {
            'error': 'Source image bytes changed since operation was queued',
            'expected_fingerprint': op.inputFingerprint,
            'actual_fingerprint': currentFingerprint,
          },
        );
        if (mounted) {
          state = state.copyWith(
            isDegraded: true,
            degradedReason: 'Original image changed since enhancement was requested',
          );
          await _persistDraft();
        }
        return;
      }
    }

    try {
      final result = await enhancerService.enhanceImage(
        imagePath,
        draftId: op.draftId,
        idempotencyKey: op.idempotencyKey,
      );

      await AiOperationStorage.updateResult(
        opId,
        status: result.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
        resultData: {
          'mediaId': result.mediaId,
          'originalMediaId': result.originalMediaId,
          'sha256Checksum': result.sha256Checksum,
          'displayPath': result.displayPath,
          'isDegraded': result.isDegraded,
          'degradedReason': result.degradedReason,
        },
      );

      // 4. Validate late result preconditions before mutating active draft
      if (!mounted) return;
      final lateOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final lateBackend = ApiConfig.baseUrl;
      if (lateOwner != owner ||
          lateBackend != op.backend ||
          state.draftId != op.draftId ||
          (state.imageEnhanceOpId != null && state.imageEnhanceOpId != op.id) ||
          state.imageInputGeneration != opGeneration) {
        debugPrint('[AddProductFlow] Discarding stale image enhance result for op $opId.');
        return;
      }

      state = state.copyWith(
        mediaId: result.mediaId,
        originalMediaId: result.originalMediaId,
        sha256Checksum: result.sha256Checksum,
        enhancedImagePath: result.displayPath,
        isEnhanced: result.displayPath.isNotEmpty && result.displayPath != state.originalImagePath,
        isDegraded: result.isDegraded,
        degradedReason: result.degradedReason,
        boundMediaGeneration: opGeneration,
      );
      await _persistDraft();
    } catch (e) {
      debugPrint('[AddProductFlow] Error replaying image enhancement operation $opId: $e');
    }
  }

  Future<void> _replayPricingOperation(AiOperationRecord op) async {
    final pricingService = _ref.read(pricingServiceProvider);
    final req = op.requestSnapshot;
    final opId = op.id;
    final opGeneration = op.inputGeneration;
    final owner = op.owner;

    // Validate preconditions before dispatch
    final preOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
    final preBackend = ApiConfig.baseUrl;
    if (preOwner != op.owner ||
        preBackend != op.backend ||
        state.draftId != op.draftId ||
        (state.pricingOpId != null && state.pricingOpId != op.id) ||
        state.pricingInputGeneration != opGeneration) {
      debugPrint('[AddProductFlow] Pricing replay precondition mismatch for op $opId. Aborting replay.');
      return;
    }

    try {
      final suggestion = await pricingService.suggestPrice(
        description: req['description'] as String?,
        category: req['category'] as String? ?? 'Handicrafts',
        tags: _stringList(req['tags']),
        imageUrl: req['image_url'] as String? ?? req['imageUrl'] as String?,
        rawMaterialCost: (req['materials_cost'] as num?)?.toDouble() ??
            (req['raw_material_cost'] as num?)?.toDouble() ??
            (req['base_cost'] as num?)?.toDouble(),
        laborHours: (req['labor_hours'] as num?)?.toDouble(),
        hourlyWage: (req['hourly_wage'] as num?)?.toDouble() ??
            (req['hourly_rate'] as num?)?.toDouble(),
        idempotencyKey: op.idempotencyKey,
      );

      await AiOperationStorage.updateResult(
        opId,
        status: suggestion.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
        resultData: {
          'floor_price': suggestion.floorPrice,
          'suggested_price': suggestion.suggestedPrice,
          'min_price': suggestion.minPrice,
          'max_price': suggestion.maxPrice,
          'confidence_score': suggestion.confidenceScore,
          'market_position': suggestion.marketPosition,
          'comparable_products': suggestion.comparableProducts.map((c) => c.toJson()).toList(),
          'reasoning': suggestion.reasoning,
          'reasoning_hi': suggestion.reasoningHi,
          'is_degraded': suggestion.isDegraded,
          'degraded_reason': suggestion.degradedReason,
        },
      );

      if (!mounted) return;
      final cur = state;
      final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final curBackend = ApiConfig.baseUrl;
      if (curOwner == owner &&
          curBackend == op.backend &&
          cur.draftId == op.draftId &&
          cur.pricingInputGeneration == opGeneration &&
          cur.pricingOpId == opId) {
        final currentCostFloor = cur.rawMaterialCost + (cur.laborHours * cur.hourlyRate);
        final effectiveFloor = max(suggestion.floorPrice, currentCostFloor);
        final effectiveSuggested = max(suggestion.suggestedPrice, effectiveFloor);
        final effectiveMin = max(suggestion.minPrice, effectiveFloor);
        final effectiveMax = max(suggestion.maxPrice, effectiveFloor);

        if (!mounted) return;
        state = state.copyWith(
          floorPrice: effectiveFloor,
          suggestedPrice: effectiveSuggested,
          minPrice: effectiveMin,
          maxPrice: effectiveMax,
          finalPrice: effectiveSuggested,
          confidenceScore: suggestion.confidenceScore,
          marketPosition: suggestion.marketPosition,
          comparableProducts: suggestion.comparableProducts,
          pricingReasoning: suggestion.reasoning,
          pricingReasoningHi: suggestion.reasoningHi,
          isPricingProcessing: false,
          isPricingDegraded: suggestion.isDegraded,
          pricingDegradedReason: suggestion.degradedReason,
        );
        await _persistDraft();
      }
    } catch (e) {
      debugPrint('[AddProductFlow] Error during pricing replay: $e');
      await AiOperationStorage.updateResult(
        opId,
        status: AiOperationRecord.statusFailed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _replayListingOperation(AiOperationRecord op) async {
    final speechService = _ref.read(speechServiceProvider);
    final req = op.requestSnapshot;
    final opId = op.id;
    final opGeneration = op.inputGeneration;
    final owner = op.owner;

    // Validate preconditions before dispatch
    final preOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
    final preBackend = ApiConfig.baseUrl;
    if (preOwner != op.owner ||
        preBackend != op.backend ||
        state.draftId != op.draftId ||
        (state.voiceListingOpId != null && state.voiceListingOpId != op.id) ||
        state.listingInputGeneration != opGeneration) {
      debugPrint('[AddProductFlow] Listing replay precondition mismatch for op $opId. Aborting replay.');
      return;
    }

    try {
      final suggestion = await speechService.generateListingFromTranscript(
        transcript: req['transcript'] as String? ?? '',
        languageCode: req['language_code'] as String? ?? 'auto',
        categoryHint: req['category_hint'] as String?,
        idempotencyKey: op.idempotencyKey,
      );

      await AiOperationStorage.updateResult(
        opId,
        status: suggestion.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
        resultData: {
          'title_en': suggestion.titleEn,
          'title_hi': suggestion.titleHi,
          'description_en': suggestion.descriptionEn,
          'description_hi': suggestion.descriptionHi,
          'category': suggestion.category,
          'tags': suggestion.tags,
          'raw_material_cost': suggestion.rawMaterialCost,
          'labor_hours': suggestion.laborHours,
          'hourly_rate': suggestion.hourlyRate,
          'floor_price': suggestion.floorPrice,
          'is_degraded': suggestion.isDegraded,
          'degraded_reason': suggestion.degradedReason,
        },
      );

      if (!mounted) return;
      final cur = state;
      final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final curBackend = ApiConfig.baseUrl;
      if (curOwner == owner &&
          curBackend == op.backend &&
          cur.draftId == op.draftId &&
          cur.listingInputGeneration == opGeneration &&
          cur.voiceListingOpId == opId) {
        final mat = (suggestion.rawMaterialCost != null && suggestion.rawMaterialCost! > 0)
            ? suggestion.rawMaterialCost!
            : cur.rawMaterialCost;
        final hours = (suggestion.laborHours != null && suggestion.laborHours! > 0)
            ? suggestion.laborHours!
            : cur.laborHours;
        final rate = (suggestion.hourlyRate != null && suggestion.hourlyRate! > 0)
            ? suggestion.hourlyRate!
            : cur.hourlyRate;
        final calculatedFloor = mat + (hours * rate);
        final rawFloor = (suggestion.floorPrice != null && suggestion.floorPrice! > 0)
            ? suggestion.floorPrice!
            : cur.floorPrice;
        final effectiveFloor = max(rawFloor, calculatedFloor);

        if (!mounted) return;
        state = state.copyWith(
          titleEn: suggestion.titleEn,
          titleHi: suggestion.titleHi,
          descriptionEn: suggestion.descriptionEn,
          descriptionHi: suggestion.descriptionHi,
          category: suggestion.category.isNotEmpty ? suggestion.category : cur.category,
          tags: suggestion.tags.isNotEmpty ? suggestion.tags : cur.tags,
          rawMaterialCost: mat,
          laborHours: hours,
          hourlyRate: rate,
          floorPrice: effectiveFloor,
          minPrice: cur.minPrice < effectiveFloor ? effectiveFloor : cur.minPrice,
          finalPrice: cur.finalPrice < effectiveFloor ? effectiveFloor : cur.finalPrice,
          isListingDegraded: suggestion.isDegraded,
          listingDegradedReason: suggestion.degradedReason,
          isAiProcessing: false,
        );
        await _persistDraft();
      }
    } catch (e) {
      debugPrint('[AddProductFlow] Error during listing replay: $e');
      await AiOperationStorage.updateResult(
        opId,
        status: AiOperationRecord.statusFailed,
        errorMessage: e.toString(),
      );
    }
  }

  void discardPreviousDraft() {
    _pendingDraft = null;
    _pendingDraftSnapshot = null;
    state = AddProductDraft(
      draftId: 'draft_${DateTime.now().microsecondsSinceEpoch}',
      hasExistingDraft: false,
      resumePromptHandled: true,
      isAiProcessing: false,
    );
    if (Hive.isBoxOpen('draft_box')) {
      Hive.box('draft_box').clear();
    }
  }

  Future<void> _persistDraft() async {
    if (_isDisposed) return;
    if (!Hive.isBoxOpen('draft_box')) {
      throw StateError('draft_box is not open; cannot persist safety-critical draft');
    }
    final curState = state;
    final currentSeq = ++_draftSaveSeq;
    await _draftLock.synchronized(() async {
      if (currentSeq < _draftSaveSeq) return;
      final box = Hive.box('draft_box');
      final snapshotData = curState.toJson();
      snapshotData['__version'] = 1;
      snapshotData['__save_seq'] = currentSeq;
      final jsonStr = jsonEncode(snapshotData);
      await box.put(snapshotKey, jsonStr);
      await box.flush();
    });
  }

  /// Called from "Retake Photo" on the AI Listing Review step. Sends the
  /// user back to Step 1, but remembers to skip straight back to the
  /// review step (not through voice/description again) once they accept
  /// the new photo — the transcript/description they already gave is
  /// still valid.
  void startRetakePhoto() {
    state = state.copyWith(currentStep: 0, isRetakeFlow: true);
  }

  /// Called when the user accepts a photo on Step 1. Normally advances to
  /// Step 2; if we're mid-retake, jumps straight back to Step 3 instead.
  Future<void> confirmPhoto() async {
    if (state.isRetakeFlow) {
      state = state.copyWith(currentStep: 2, isRetakeFlow: false);
      await _persistDraft();
    } else {
      await nextStep();
    }
  }

  Future<void> setStep(int step) async {
    state = state.copyWith(currentStep: step);
    await _persistDraft();
  }

  Future<void> nextStep() async {
    if (state.currentStep < 4) {
      state = state.copyWith(currentStep: state.currentStep + 1);
      await _persistDraft();
    }
  }

  Future<void> previousStep() async {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
      await _persistDraft();
    }
  }

  Future<void> setImage(String path) async {
    _processingSubmissionInProgress = false;
    final newGen = state.imageInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'image_enhance',
      newGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );

    String snapshotPath = path;
    String? snapshotSha256;
    if (path.isNotEmpty && File(path).existsSync()) {
      snapshotPath = await _copyImageToDraftStorage(File(path));
      final bytes = await File(snapshotPath).readAsBytes();
      snapshotSha256 = sha256.convert(bytes).toString();
    }

    state = state.copyWith(
      originalImagePath: path,
      enhancedImagePath: path,
      immutablePhotoSnapshotPath: snapshotPath,
      immutablePhotoSnapshotSha256: snapshotSha256,
      isEnhanced: false,
      isAiProcessing: false,
      imageQueueItemId: null,
      imageQueueStatus: QueueStatus.pending,
      mediaId: null,
      originalMediaId: null,
      sha256Checksum: null,
      imageEnhanceOpId: null,
      isDegraded: false,
      degradedReason: null,
      imageInputGeneration: newGen,
      boundMediaGeneration: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await _persistDraft();
  }

  Future<String> queueImage(File imageFile) async {
    _processingSubmissionInProgress = false;
    final durablePath = await _copyImageToDraftStorage(imageFile);
    String? snapshotSha256;
    if (File(durablePath).existsSync()) {
      final bytes = await File(durablePath).readAsBytes();
      snapshotSha256 = sha256.convert(bytes).toString();
    }
    final newGen = state.imageInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'image_enhance',
      newGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    state = state.copyWith(
      originalImagePath: durablePath,
      enhancedImagePath: durablePath,
      immutablePhotoSnapshotPath: durablePath,
      immutablePhotoSnapshotSha256: snapshotSha256,
      isEnhanced: false,
      isAiProcessing: false,
      imageQueueItemId: null,
      imageQueueStatus: QueueStatus.pending,
      mediaId: null,
      originalMediaId: null,
      sha256Checksum: null,
      imageEnhanceOpId: null,
      isDegraded: false,
      degradedReason: null,
      imageInputGeneration: newGen,
      boundMediaGeneration: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await _persistDraft();
    return '';
  }

  Future<String> _copyImageToDraftStorage(File imageFile) async {
    if (!imageFile.existsSync()) return imageFile.path;
    Directory appDir;
    try {
      appDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      appDir = Directory.systemTemp;
    }
    final draftDir = Directory('${appDir.path}/draft_media');
    await draftDir.create(recursive: true);
    final extension = imageFile.path.contains('.')
        ? imageFile.path.split('.').last
        : 'jpg';
    final target = File(
      '${draftDir.path}/${state.draftId}-${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await imageFile.copy(target.path);
    return target.path;
  }

  Future<void> submitForAiProcessing(
    bool isOnline, {
    String languageCode = 'en',
  }) async {
    if (_processingSubmissionInProgress) return;
    _processingSubmissionInProgress = true;

    // New submission: invalidate any stale completions from a previous one
    // and start a hard watchdog so the spinner can never hang forever.
    final gen = ++_aiProcessingGen;

    try {
      final hasPendingAi = !state.isEnhanced || state.titleEn.isEmpty;
      state = state.copyWith(isAiProcessing: isOnline && hasPendingAi);
      if (state.isAiProcessing) _startAiProcessingWatchdog(gen);

      if (state.imageQueueItemId != null &&
          state.imageQueueItemId!.isNotEmpty) {
        _watchImageQueue(state.imageQueueItemId!);
      }

      // 1. Enqueue image if present and not yet queued in Drift
      if (!isOnline &&
          state.originalImagePath.isNotEmpty &&
          (state.imageQueueItemId == null || state.imageQueueItemId!.isEmpty)) {
        final imgFile = File(state.originalImagePath);
        if (imgFile.existsSync() && OfflineSyncService.instance.isInitialized) {
          try {
            final owner = _ref.read(authStateProvider).userId ?? 'anonymous';
            final backend = ApiConfig.baseUrl;
            final fingerprint = await AiOperationRecord.computeFingerprint(
              operationType: 'image_enhance',
              owner: owner,
              backend: backend,
              inputs: {'draft_id': state.draftId, 'generation': state.imageInputGeneration},
              files: [imgFile],
            );
            final opId = state.imageEnhanceOpId ??
                'enh_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${fingerprint.substring(0, 12)}';
            final record = AiOperationRecord(
              id: opId,
              idempotencyKey: opId,
              owner: owner,
              backend: backend,
              operationType: 'image_enhance',
              draftId: state.draftId,
              inputGeneration: state.imageInputGeneration,
              inputFingerprint: fingerprint,
              requestSnapshot: {'image_path': imgFile.path, 'draft_id': state.draftId},
              status: AiOperationRecord.statusInFlight,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            await AiOperationStorage.save(record);
            final localId = await OfflineSyncService.instance.enqueueImage(
              imageFile: imgFile,
              productDraftId: state.draftId,
              explicitLocalId: opId,
            );
            state = state.copyWith(
              imageEnhanceOpId: opId,
              imageQueueItemId: localId,
              imageQueueStatus: QueueStatus.pending,
            );
            _watchImageQueue(localId);
          } catch (e) {
            debugPrint('[AddProductFlow] Error enqueuing image: $e');
          }
        }
      }

      // 2. Enqueue voice note if present and not yet queued in Drift
      if (state.recordedAudioPath.isNotEmpty &&
          (state.voiceQueueItemId == null || state.voiceQueueItemId!.isEmpty)) {
        final voiceFile = File(state.recordedAudioPath);
        if (voiceFile.existsSync() &&
            OfflineSyncService.instance.isInitialized) {
          try {
            final localId = await OfflineSyncService.instance.enqueueVoiceNote(
              audioFile: voiceFile,
              productDraftId: state.draftId,
            );
            state = state.copyWith(
              voiceQueueItemId: localId,
              voiceQueueStatus: QueueStatus.pending,
            );
          } catch (e) {
            debugPrint('[AddProductFlow] Error enqueuing voice note: $e');
          }
        }
      }

      _persistDraft();

      // 3. Dispatch processing if online
      if (isOnline) {
        if (!state.isEnhanced &&
            state.originalImagePath.isNotEmpty &&
            _imageEnhancingCompleter == null) {
          final imageFile = File(state.originalImagePath);
          if (imageFile.existsSync()) {
            _trackBackgroundFuture(_enhanceProductImage(imageFile, gen: gen));
          }
        }

        if (OfflineSyncService.instance.isInitialized) {
          unawaited(OfflineSyncService.instance.triggerSyncNow());
        }

        // If manual description was provided instead of voice, generate listing
        if (state.titleEn.isEmpty &&
            state.manualDescription.isNotEmpty &&
            state.recordedAudioPath.isEmpty) {
          _trackBackgroundFuture(_generateListingFromManualDescription(languageCode, gen: gen));
        }
      } else {
        // Offline: keep items saved in draft and queue, wait for connectivity
        state = state.copyWith(isAiProcessing: false);
        _aiProcessingWatchdog?.cancel();
      }
    } finally {
      _processingSubmissionInProgress = false;
    }
  }

  Future<bool> enhanceProductImageAndWait() async {
    if (state.originalImagePath.isEmpty) return false;
    if (state.isEnhanced &&
        state.enhancedImagePath.isNotEmpty &&
        state.enhancedImagePath != state.originalImagePath) {
      return true;
    }
    final imageFile = File(state.originalImagePath);
    if (!imageFile.existsSync()) return false;

    if (_imageEnhancingCompleter != null) {
      return _imageEnhancingCompleter!.future;
    }

    final completer = Completer<bool>();
    _imageEnhancingCompleter = completer;

    try {
      await _enhanceProductImage(imageFile);
      completer.complete(state.isEnhanced);
    } catch (e) {
      completer.complete(false);
    } finally {
      if (_imageEnhancingCompleter == completer) {
        _imageEnhancingCompleter = null;
      }
    }

    return state.isEnhanced;
  }

  Future<void> _enhanceProductImage(File imageFile, {int? gen}) async {
    _imageEnhancementInFlight = true;
    _recomputeAiProcessing();
    if (kMockAiBackend) {
      await Future.delayed(const Duration(milliseconds: 700));
      _imageEnhancementInFlight = false;
      if (gen != null && gen != _aiProcessingGen) return;
      state = state.copyWith(
        enhancedImagePath: imageFile.path,
        isEnhanced: true,
        imageQueueStatus: QueueStatus.completed,
        boundMediaGeneration: state.imageInputGeneration,
      );
      _recomputeAiProcessing();
      _persistDraft();
      return;
    }

    final owner = _ref.read(authStateProvider).userId ?? 'anonymous';
    final backend = ApiConfig.baseUrl;
    final int opGeneration = state.imageInputGeneration;
    final targetDraftId = state.draftId;

    final fingerprint = await AiOperationRecord.computeFingerprint(
      operationType: 'image_enhance',
      owner: owner,
      backend: backend,
      inputs: {'draft_id': state.draftId, 'generation': opGeneration},
      files: [imageFile],
    );

    if (!mounted) return;

    final String opId;
    final existingOp = state.imageEnhanceOpId != null
        ? await AiOperationStorage.get(state.imageEnhanceOpId!)
        : null;
    if (existingOp != null &&
        existingOp.inputFingerprint == fingerprint &&
        existingOp.status != AiOperationRecord.statusSuperseded) {
      opId = state.imageEnhanceOpId!;
    } else {
      opId = 'enh_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${fingerprint.substring(0, 12)}';
      final record = AiOperationRecord(
        id: opId,
        idempotencyKey: opId,
        owner: owner,
        backend: backend,
        operationType: 'image_enhance',
        draftId: state.draftId,
        inputGeneration: opGeneration,
        inputFingerprint: fingerprint,
        requestSnapshot: {
          'image_path': imageFile.path,
          'draft_id': state.draftId,
        },
        status: AiOperationRecord.statusInFlight,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await AiOperationStorage.save(record);
      state = state.copyWith(imageEnhanceOpId: opId);
      await _persistDraft();
    }

    final enhancer = _ref.read(imageEnhancerServiceProvider);
    final networkFuture = enhancer.enhanceImage(
      imageFile.path,
      draftId: state.draftId,
      idempotencyKey: opId,
    );

    // Decouple background network future to persist late results
    final bgFuture = networkFuture.then((res) async {
      await AiOperationStorage.updateResult(
        opId,
        status: res.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
        resultData: res.toJson(),
      );
      if (_isDisposed) return;
      final cur = state;
      final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final curBackend = ApiConfig.baseUrl;
      if (curOwner == owner &&
          curBackend == backend &&
          cur.draftId == targetDraftId &&
          cur.imageInputGeneration == opGeneration &&
          (cur.imageEnhanceOpId == null || cur.imageEnhanceOpId == opId)) {
        final hasNewPath = res.displayPath.isNotEmpty && res.displayPath != imageFile.path;
        state = state.copyWith(
          enhancedImagePath: hasNewPath ? res.displayPath : cur.enhancedImagePath,
          isEnhanced: !res.isDegraded && hasNewPath,
          imageQueueStatus: QueueStatus.completed,
          mediaId: res.mediaId ?? cur.mediaId,
          originalMediaId: res.originalMediaId ?? cur.originalMediaId,
          sha256Checksum: res.sha256Checksum ?? cur.sha256Checksum,
          isDegraded: res.isDegraded,
          degradedReason: res.degradedReason,
          boundMediaGeneration: opGeneration,
        );
        _recomputeAiProcessing();
        await _persistDraft();
      }
    }).catchError((err) async {
      await AiOperationStorage.updateResult(
        opId,
        status: AiOperationRecord.statusFailed,
        errorMessage: err.toString(),
      );
    });
    _trackBackgroundFuture(bgFuture);

    try {
      final result = await networkFuture.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[AddProductFlow] Image enhancement timed out — proceeding offline.');
          return EnhancedImageResult(
            displayPath: imageFile.path,
            isDegraded: true,
            degradedReason: 'Image enhancement timed out after 30 seconds.',
            status: 'timeout_fallback',
          );
        },
      );
      _imageEnhancementInFlight = false;
      if (gen != null && gen != _aiProcessingGen) return;

      final cur = state;
      if (cur.imageInputGeneration != opGeneration) return;

      if (result.displayPath.isEmpty || result.displayPath == imageFile.path) {
        state = state.copyWith(
          mediaId: result.mediaId,
          originalMediaId: result.originalMediaId,
          sha256Checksum: result.sha256Checksum,
          isDegraded: result.isDegraded,
          degradedReason: result.degradedReason,
          boundMediaGeneration: opGeneration,
        );
        _recomputeAiProcessing();
        await _persistDraft();
        return;
      }

      state = state.copyWith(
        enhancedImagePath: result.displayPath,
        isEnhanced: !result.isDegraded,
        imageQueueStatus: QueueStatus.completed,
        mediaId: result.mediaId,
        originalMediaId: result.originalMediaId,
        sha256Checksum: result.sha256Checksum,
        isDegraded: result.isDegraded,
        degradedReason: result.degradedReason,
        boundMediaGeneration: opGeneration,
      );
      _recomputeAiProcessing();
      await _persistDraft();
    } catch (e, st) {
      debugPrint('[AddProductFlow] AI enhancement error: $e\n$st');
      _imageEnhancementInFlight = false;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') || errStr.contains('403') || errStr.contains('unauthorized')) {
        _ref.read(authStateProvider.notifier).expireSession();
      }
      state = state.copyWith(
        isDegraded: true,
        degradedReason: 'Image enhancement failed: $e',
      );
      if (gen != null && gen != _aiProcessingGen) return;
      _recomputeAiProcessing();
      await _persistDraft();
    }
  }

  void _watchImageQueue(String localId) {
    _imageQueueSubscription?.cancel();
    if (!OfflineSyncService.instance.isInitialized) return;

    _imageQueueSubscription = OfflineSyncService.instance.watchQueue().listen((
      items,
    ) {
      for (final item in items) {
        if (item.localId == localId || item.productDraftId == state.draftId) {
          _applyQueueItem(item);
        }
      }
    });
  }

  void _watchVoiceQueue(String localId) {
    _voiceQueueSubscription?.cancel();
    if (!OfflineSyncService.instance.isInitialized) return;

    _voiceQueueSubscription = OfflineSyncService.instance.watchQueue().listen((
      items,
    ) {
      for (final item in items) {
        if (item.localId == localId || item.productDraftId == state.draftId) {
          _applyQueueItem(item);
        }
      }
    });
  }

  Future<void> _hydrateQueueState() async {
    if (!OfflineSyncService.instance.isInitialized) return;
    final items = await OfflineSyncService.instance.getAllQueueItems();
    for (final item in items.where(
      (item) => item.productDraftId == state.draftId,
    )) {
      _applyQueueItem(item);
    }
    final imageId = state.imageQueueItemId;
    if (imageId != null && imageId.isNotEmpty) _watchImageQueue(imageId);
    final voiceId = state.voiceQueueItemId;
    if (voiceId != null && voiceId.isNotEmpty) _watchVoiceQueue(voiceId);
  }

  void _applyQueueItem(QueueItem item) {
    final result = item.resultJson == null
        ? null
        : jsonDecode(item.resultJson!) as Map<String, dynamic>;
    if (item.type == QueueItemType.imageEnhance) {
      if (state.imageQueueItemId != null &&
          state.imageQueueItemId!.isNotEmpty &&
          item.localId != state.imageQueueItemId) {
        debugPrint('[AddProductFlow] Ignoring stale queue item ${item.localId} (active: ${state.imageQueueItemId})');
        return;
      }
      final enhancedUrl =
          result?['enhancedImageUrl'] as String? ??
          result?['enhanced_url'] as String?;
      final serverMediaId =
          result?['mediaId'] as String? ??
          result?['media_id'] as String?;
      final serverOriginalMediaId =
          result?['originalMediaId'] as String? ??
          result?['original_media_id'] as String?;
      final sha256Checksum =
          result?['sha256Checksum'] as String? ??
          result?['sha256_checksum'] as String?;
      final isDegraded =
          result?['isDegraded'] as bool? ??
          result?['is_degraded'] as bool? ??
          false;
      final degradedReason =
          result?['degradedReason'] as String? ??
          result?['degraded_reason'] as String?;

      final hasNewEnhancedUrl = enhancedUrl != null &&
          enhancedUrl.isNotEmpty &&
          enhancedUrl != state.originalImagePath;
      state = state.copyWith(
        imageQueueItemId: item.localId,
        imageQueueStatus: item.status,
        enhancedImagePath:
            hasNewEnhancedUrl ? enhancedUrl : state.enhancedImagePath,
        isEnhanced: state.isEnhanced || hasNewEnhancedUrl,
        mediaId: serverMediaId ?? state.mediaId,
        originalMediaId: serverOriginalMediaId ?? state.originalMediaId,
        sha256Checksum: sha256Checksum ?? state.sha256Checksum,
        isDegraded: isDegraded || state.isDegraded,
        degradedReason: degradedReason ?? state.degradedReason,
        boundMediaGeneration: state.imageInputGeneration,
      );
      _persistDraft();
      _recomputeAiProcessing();
    } else {
      final pricing = result?['pricing'] as Map<String, dynamic>?;
      final suggestedPrice = (pricing?['suggested_price'] as num?)?.toDouble();
      final floorPrice = (pricing?['floor_price'] as num?)?.toDouble();
      final priceRange = pricing?['price_range'] as Map<String, dynamic>?;
      final minPrice = (priceRange?['min'] as num?)?.toDouble();
      final maxPrice = (priceRange?['max'] as num?)?.toDouble();
      final reasoning = pricing?['reasoning'] as String?;
      final reasoningHi = pricing?['reasoning_hi'] as String?;
      final isDegraded =
          result?['isDegraded'] as bool? ??
          result?['is_degraded'] as bool? ??
          false;
      final degradedReason =
          result?['degradedReason'] as String? ??
          result?['degraded_reason'] as String?;

      state = state.copyWith(
        voiceQueueItemId: item.localId,
        voiceQueueStatus: item.status,
        voiceTranscript: (result?['transcript'] is String &&
                !HttpSpeechService.isSilenceHallucination(result!['transcript'] as String))
            ? (result['transcript'] as String)
            : state.voiceTranscript,
        titleEn: result?['titleEn'] as String? ??
            result?['title_en'] as String? ??
            state.titleEn,
        titleHi: result?['titleHi'] as String? ??
            result?['title_hi'] as String? ??
            state.titleHi,
        descriptionEn: result?['descriptionEn'] as String? ??
            result?['description_en'] as String? ??
            state.descriptionEn,
        descriptionHi: result?['descriptionHi'] as String? ??
            result?['description_hi'] as String? ??
            state.descriptionHi,
        category: result?['category'] as String? ?? state.category,
        tags: _stringListOrNull(result?['tags']) ?? state.tags,
        suggestedPrice: suggestedPrice ?? state.suggestedPrice,
        floorPrice: floorPrice ?? state.floorPrice,
        minPrice: minPrice ?? state.minPrice,
        maxPrice: maxPrice ?? state.maxPrice,
        finalPrice: suggestedPrice ?? state.finalPrice,
        pricingReasoning: reasoning ?? state.pricingReasoning,
        pricingReasoningHi: reasoningHi ?? state.pricingReasoningHi,
        isVoiceDegraded: isDegraded || state.isVoiceDegraded,
        voiceDegradedReason: degradedReason ?? state.voiceDegradedReason,
        isListingDegraded: isDegraded || state.isListingDegraded,
        listingDegradedReason: degradedReason ?? state.listingDegradedReason,
        isPricingDegraded: isDegraded || state.isPricingDegraded,
        pricingDegradedReason: degradedReason ?? state.pricingDegradedReason,
      );
      _recomputeAiProcessing();
    }
    _persistDraft();
  }

  Future<void> _generateListingFromManualDescription(
    String languageCode, {
    int? gen,
  }) async {
    _listingGenerationInFlight = true;
    _recomputeAiProcessing();
    if (kMockAiBackend) {
      await Future.delayed(const Duration(milliseconds: 700));
      _listingGenerationInFlight = false;
      if (gen != null && gen != _aiProcessingGen) return;
      state = state.copyWith(
        titleEn: state.manualDescription,
        titleHi: state.titleHi.isNotEmpty ? state.titleHi : state.manualDescription,
        descriptionEn: state.manualDescription,
        descriptionHi:
            state.descriptionHi.isNotEmpty ? state.descriptionHi : state.manualDescription,
      );
      _recomputeAiProcessing();
      _persistDraft();
      return;
    }
    final opId = state.voiceListingOpId ??
        'list_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${state.manualDescription.hashCode.abs()}';
    if (state.voiceListingOpId != opId) {
      state = state.copyWith(voiceListingOpId: opId);
      _persistDraft();
    }

    try {
      final speechService = _ref.read(speechServiceProvider);
      // Cap at 25 s so isAiProcessing always resolves, even if the backend
      // is unreachable — without this, a hung request left the full-screen
      // loader stuck forever.
      final suggestion = await speechService
          .generateListingFromTranscript(
            transcript: state.manualDescription,
            languageCode: languageCode,
            categoryHint: (state.category.isNotEmpty && state.category != 'Handicrafts') ? state.category : null,
            idempotencyKey: opId,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              debugPrint(
                '[AddProductFlow] Manual-description listing generation timed out.',
              );
              return AiListingSuggestion(
                titleEn: state.manualDescription,
                titleHi: state.titleHi,
                descriptionEn: state.manualDescription,
                descriptionHi: state.descriptionHi,
                category: state.category,
                tags: state.tags,
                isDegraded: true,
                degradedReason: 'Manual description listing generation timed out after 25 seconds.',
              );
            },
          );
      _listingGenerationInFlight = false;
      if (gen != null && gen != _aiProcessingGen) return;
      state = state.copyWith(
        titleEn: suggestion.titleEn,
        titleHi: suggestion.titleHi,
        descriptionEn: suggestion.descriptionEn,
        descriptionHi: suggestion.descriptionHi,
        category: suggestion.category,
        tags: suggestion.tags,
        rawMaterialCost: (suggestion.rawMaterialCost != null && suggestion.rawMaterialCost! > 0)
            ? suggestion.rawMaterialCost!
            : state.rawMaterialCost,
        laborHours: (suggestion.laborHours != null && suggestion.laborHours! > 0)
            ? suggestion.laborHours!
            : state.laborHours,
        hourlyRate: (suggestion.hourlyRate != null && suggestion.hourlyRate! > 0)
            ? suggestion.hourlyRate!
            : state.hourlyRate,
        floorPrice: (suggestion.floorPrice != null && suggestion.floorPrice! > 0)
            ? suggestion.floorPrice!
            : state.floorPrice,
        isListingDegraded: suggestion.isDegraded,
        listingDegradedReason: suggestion.degradedReason,
      );
      _recomputeAiProcessing();
      _persistDraft();
    } catch (e) {
      _listingGenerationInFlight = false;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') || errStr.contains('403') || errStr.contains('unauthorized')) {
        _ref.read(authStateProvider.notifier).expireSession();
      }
      if (gen != null && gen != _aiProcessingGen) return;
      state = state.copyWith(
        titleEn: state.manualDescription,
        descriptionEn: state.manualDescription,
        isListingDegraded: true,
        listingDegradedReason: 'Listing generation failed: $e',
      );
      _recomputeAiProcessing();
      _persistDraft();
    }
  }

  Future<void> addAdditionalImage(String path) async {
    if (state.additionalImagePaths.length >= 2) return;
    state = state.copyWith(
      additionalImagePaths: [...state.additionalImagePaths, path],
    );
    await _persistDraft();
  }

  Future<void> removeAdditionalImage(String path) async {
    state = state.copyWith(
      additionalImagePaths: state.additionalImagePaths
          .where((p) => p != path)
          .toList(),
    );
    await _persistDraft();
  }

  Future<void> addTag(String tag) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || state.tags.contains(trimmed)) return;
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      tags: [...state.tags, trimmed],
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  Future<void> removeTag(String tag) async {
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      tags: state.tags.where((t) => t != tag).toList(),
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  Future<void> setManualDescription(String desc) async {
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      manualDescription: desc,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  Future<void> retakeDescription() async {
    final newVoiceGen = state.voiceInputGeneration + 1;
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      recordedAudioPath: '',
      voiceTranscript: '',
      manualDescription: '',
      voiceQueueItemId: null,
      voiceInputGeneration: newVoiceGen,
      voiceFingerprint: null,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'voice_transcribe',
      newVoiceGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    setStep(1);
    await _persistDraft();
  }

  Future<void> processVoiceRecording({
    required String audioPath,
    required String languageCode,
  }) async {
    final newVoiceGen = state.voiceInputGeneration + 1;
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      recordedAudioPath: audioPath,
      voiceQueueItemId: null,
      voiceInputGeneration: newVoiceGen,
      voiceFingerprint: null,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'voice_transcribe',
      newVoiceGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  Future<String> queueVoiceRecording(File audioFile) async {
    final newVoiceGen = state.voiceInputGeneration + 1;
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    state = state.copyWith(
      recordedAudioPath: audioFile.path,
      voiceQueueStatus: QueueStatus.pending,
      voiceInputGeneration: newVoiceGen,
      voiceFingerprint: null,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'voice_transcribe',
      newVoiceGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();

    if (kMockAiBackend) {
      // Skip the real offline-sync queue entirely — there's no backend to
      // sync to in mock mode, so mark it done immediately instead of
      // leaving voiceQueueStatus stuck at "pending" (which would otherwise
      // keep the AI-processing loader open until the watchdog times out).
      state = state.copyWith(voiceQueueStatus: QueueStatus.completed);
      await _persistDraft();
      return '';
    }

    if (OfflineSyncService.instance.isInitialized) {
      try {
        final localId = await OfflineSyncService.instance.enqueueVoiceNote(
          audioFile: audioFile,
          productDraftId: state.draftId,
        );
        state = state.copyWith(voiceQueueItemId: localId);
        _watchVoiceQueue(localId);
        unawaited(OfflineSyncService.instance.triggerSyncNow());
        return localId;
      } catch (e) {
        debugPrint('[AddProductFlow] Error enqueuing voice note: $e');
      }
    }
    return '';
  }

  Future<void> transcribeVoiceDirectly(File audioFile, {String languageCode = 'auto'}) async {
    if (kMockAiBackend) {
      await Future.delayed(const Duration(milliseconds: 700));
      const fakeTranscript = 'Mock transcription (backend bypassed for testing)';
      _listingGenerationInFlight = true;
      state = state.copyWith(voiceTranscript: fakeTranscript, transcriptionConfidence: 1.0);
      _recomputeAiProcessing();
      _persistDraft();
      await Future.delayed(const Duration(milliseconds: 700));
      _listingGenerationInFlight = false;
      state = state.copyWith(
        titleEn: fakeTranscript,
        descriptionEn: fakeTranscript,
      );
      _recomputeAiProcessing();
      _persistDraft();
      return;
    }
    final opId = state.voiceListingOpId ??
        'voice_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${audioFile.path.hashCode.abs()}';
    if (state.voiceListingOpId != opId) {
      state = state.copyWith(voiceListingOpId: opId);
      _persistDraft();
    }

    try {
      final speechService = _ref.read(speechServiceProvider);

      // Step 1: Transcribe audio via Whisper. Cap at 20 s — backend may be
      // unreachable, and this must always resolve so the loader can't hang.
      final result = await speechService
          .transcribeAudio(
            audioPath: audioFile.path,
            languageCode: languageCode,
            idempotencyKey: opId,
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              debugPrint('[AddProductFlow] Direct transcription timed out.');
              return const TranscriptionResult(
                transcript: '',
                confidence: 0,
                isDegraded: true,
                degradedReason: 'Direct transcription timed out after 20 seconds.',
              );
            },
          );
      final transcript = result.transcript;

      if (transcript.isEmpty ||
          HttpSpeechService.isSilenceHallucination(transcript)) {
        debugPrint('[AddProductFlow] Transcription empty or hallucination — skipping listing generation.');
        state = state.copyWith(
          isVoiceDegraded: true,
          voiceDegradedReason: result.degradedReason ?? 'Transcription returned no audible speech.',
        );
        _recomputeAiProcessing();
        _persistDraft();
        return;
      }

      _listingGenerationInFlight = true;
      state = state.copyWith(
        voiceTranscript: transcript,
        transcriptionConfidence: result.confidence,
        isVoiceDegraded: result.isDegraded,
        voiceDegradedReason: result.degradedReason,
      );
      _recomputeAiProcessing();
      _persistDraft();

      // Step 2: Generate bilingual SEO listing from transcript via Gemini.
      // Cap at 25 s for the same reason as above.
      debugPrint('[AddProductFlow] Transcript ready — calling generate-listing...');
      final suggestion = await speechService
          .generateListingFromTranscript(
            transcript: transcript,
            languageCode: languageCode,
            categoryHint: (state.category.isNotEmpty && state.category != 'Handicrafts') ? state.category : null,
            idempotencyKey: opId,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              debugPrint('[AddProductFlow] Direct listing generation timed out.');
              return AiListingSuggestion(
                titleEn: transcript,
                titleHi: state.titleHi,
                descriptionEn: transcript,
                descriptionHi: state.descriptionHi,
                category: state.category,
                tags: state.tags,
                isDegraded: true,
                degradedReason: 'Listing generation timed out after 25 seconds.',
              );
            },
          );

      _listingGenerationInFlight = false;
      state = state.copyWith(
        titleEn: suggestion.titleEn,
        titleHi: suggestion.titleHi,
        descriptionEn: suggestion.descriptionEn,
        descriptionHi: suggestion.descriptionHi,
        category: suggestion.category,
        tags: suggestion.tags,
        rawMaterialCost: (suggestion.rawMaterialCost != null && suggestion.rawMaterialCost! > 0)
            ? suggestion.rawMaterialCost!
            : state.rawMaterialCost,
        laborHours: (suggestion.laborHours != null && suggestion.laborHours! > 0)
            ? suggestion.laborHours!
            : state.laborHours,
        hourlyRate: (suggestion.hourlyRate != null && suggestion.hourlyRate! > 0)
            ? suggestion.hourlyRate!
            : state.hourlyRate,
        floorPrice: (suggestion.floorPrice != null && suggestion.floorPrice! > 0)
            ? suggestion.floorPrice!
            : state.floorPrice,
        isListingDegraded: suggestion.isDegraded,
        listingDegradedReason: suggestion.degradedReason,
      );
      _recomputeAiProcessing();
      _persistDraft();
      debugPrint('[AddProductFlow] Listing generation complete: "${suggestion.titleEn}"');
    } catch (e) {
      debugPrint('[AddProductFlow] Error during voice transcription/listing: $e');
      _listingGenerationInFlight = false;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') || errStr.contains('403') || errStr.contains('unauthorized')) {
        _ref.read(authStateProvider.notifier).expireSession();
      }
      state = state.copyWith(
        isVoiceDegraded: true,
        voiceDegradedReason: 'Voice transcription failed: $e',
      );
      _recomputeAiProcessing();
      _persistDraft();
    }
  }

  Future<void> retakePhoto(File newPhoto) async {
    final durablePath = await _copyImageToDraftStorage(newPhoto);
    String? snapshotSha256;
    if (File(durablePath).existsSync()) {
      final bytes = await File(durablePath).readAsBytes();
      snapshotSha256 = sha256.convert(bytes).toString();
    }
    final newGen = state.imageInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'image_enhance',
      newGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    state = state.copyWith(
      originalImagePath: durablePath,
      enhancedImagePath: durablePath,
      immutablePhotoSnapshotPath: durablePath,
      immutablePhotoSnapshotSha256: snapshotSha256,
      isEnhanced: false,
      imageQueueItemId: null,
      imageQueueStatus: QueueStatus.pending,
      mediaId: null,
      originalMediaId: null,
      sha256Checksum: null,
      imageEnhanceOpId: null,
      isDegraded: false,
      degradedReason: null,
      imageInputGeneration: newGen,
      boundMediaGeneration: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );
    await _persistDraft();
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    if (isOnline) {
      _trackBackgroundFuture(_enhanceProductImage(File(durablePath)));
    }
  }

  Future<void> retakeVoice(File newAudio) async {
    final newVoiceGen = state.voiceInputGeneration + 1;
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;

    state = state.copyWith(
      recordedAudioPath: newAudio.path,
      voiceTranscript: '',
      voiceQueueItemId: null,
      voiceQueueStatus: QueueStatus.pending,
      voiceInputGeneration: newVoiceGen,
      voiceFingerprint: null,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );

    await AiOperationStorage.markSuperseded(
      state.draftId,
      'voice_transcribe',
      newVoiceGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );

    await _persistDraft();
    if (OfflineSyncService.instance.isInitialized) {
      try {
        final localId = await OfflineSyncService.instance.enqueueVoiceNote(
          audioFile: newAudio,
          productDraftId: state.draftId,
        );
        state = state.copyWith(voiceQueueItemId: localId);
        _watchVoiceQueue(localId);
        unawaited(OfflineSyncService.instance.triggerSyncNow());
      } catch (e) {
        debugPrint('[AddProductFlow] Error re-enqueuing voice: $e');
      }
    }
  }

  Future<void> clearVoiceRecording() async {
    final newVoiceGen = state.voiceInputGeneration + 1;
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;

    state = state.copyWith(
      recordedAudioPath: '',
      voiceTranscript: '',
      voiceQueueItemId: null,
      voiceQueueStatus: QueueStatus.completed,
      voiceInputGeneration: newVoiceGen,
      voiceFingerprint: null,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );

    await AiOperationStorage.markSuperseded(
      state.draftId,
      'voice_transcribe',
      newVoiceGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );

    await _persistDraft();
  }

  Future<void> generateAiListing(String languageCode) async {
    state = state.copyWith(isAiProcessing: true);
    try {
      final speechService = _ref.read(speechServiceProvider);

      String transcript = state.voiceTranscript.trim();
      if (transcript.isEmpty) {
        transcript = state.manualDescription.trim();
      }
      if (transcript.isEmpty) {
        transcript = state.descriptionEn.trim();
      }
      if (transcript.isEmpty) {
        transcript = state.descriptionHi.trim();
      }
      if (transcript.isEmpty) {
        transcript = state.titleEn.trim();
      }

      if (transcript.isEmpty && state.recordedAudioPath.isNotEmpty) {
        final audioFile = File(state.recordedAudioPath);
        if (audioFile.existsSync()) {
          try {
            // Cap transcription at 20 s — backend may be unreachable.
            final transResult = await speechService
                .transcribeAudio(
                  audioPath: audioFile.path,
                  languageCode: languageCode,
                )
                .timeout(
                  const Duration(seconds: 20),
                  onTimeout: () {
                    debugPrint('[AddProductFlow] Transcription timed out.');
                    return const TranscriptionResult(transcript: '', confidence: 0);
                  },
                );
            if (transResult.transcript.isNotEmpty &&
                !HttpSpeechService.isSilenceHallucination(transResult.transcript)) {
              transcript = transResult.transcript;
              state = state.copyWith(voiceTranscript: transcript);
            }
          } catch (e) {
            debugPrint('[AddProductFlow] Error transcribing in generateAiListing: $e');
          }
        }
      }

      if (transcript.isEmpty) {
        transcript = (state.category.isNotEmpty && state.category != 'Handicrafts')
            ? 'Handcrafted ${state.category} artisan product made with traditional techniques'
            : 'Handcrafted traditional artisan product';
      }

      final owner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final backend = ApiConfig.baseUrl;
      final categoryHint = (state.category.isNotEmpty && state.category != 'Handicrafts') ? state.category : null;
      final targetDraftId = state.draftId;
      final targetOwner = owner;
      final targetBackend = backend;

      final listingInputs = <String, dynamic>{
        'transcript': transcript,
        'language_code': languageCode,
        'category_hint': categoryHint,
      };

      final frozenListingInputs = Map<String, dynamic>.from(listingInputs);

      final fingerprint = await AiOperationRecord.computeFingerprint(
        operationType: 'listing_generate',
        owner: owner,
        backend: backend,
        inputs: frozenListingInputs,
      );

      final String opId;
      final int opGeneration;
      if (state.listingFingerprint == fingerprint && state.voiceListingOpId != null) {
        opId = state.voiceListingOpId!;
        opGeneration = state.listingInputGeneration;
      } else {
        opGeneration = state.listingInputGeneration + 1;
        opId = 'voice_gen_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${fingerprint.substring(0, 12)}';
        final record = AiOperationRecord(
          id: opId,
          idempotencyKey: opId,
          owner: owner,
          backend: backend,
          operationType: 'listing_generate',
          draftId: state.draftId,
          inputGeneration: opGeneration,
          inputFingerprint: fingerprint,
          requestSnapshot: frozenListingInputs,
          status: AiOperationRecord.statusInFlight,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await AiOperationStorage.save(record);
        state = state.copyWith(
          voiceListingOpId: opId,
          listingFingerprint: fingerprint,
          listingInputGeneration: opGeneration,
        );
        await _persistDraft();
      }

      final networkFuture = speechService.generateListingFromTranscript(
        transcript: transcript,
        languageCode: languageCode,
        categoryHint: categoryHint,
        idempotencyKey: opId,
      );

      // Decouple background network future to persist late results
      final bgFuture = networkFuture.then((res) async {
        await AiOperationStorage.updateResult(
          opId,
          status: res.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
          resultData: {
            'title_en': res.titleEn,
            'title_hi': res.titleHi,
            'description_en': res.descriptionEn,
            'description_hi': res.descriptionHi,
            'category': res.category,
            'tags': res.tags,
            'raw_material_cost': res.rawMaterialCost,
            'labor_hours': res.laborHours,
            'hourly_rate': res.hourlyRate,
            'floor_price': res.floorPrice,
            'is_degraded': res.isDegraded,
            'degraded_reason': res.degradedReason,
          },
        );
        if (_isDisposed) return;
        final cur = state;
        final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
        final curBackend = ApiConfig.baseUrl;
        if (curOwner == targetOwner &&
            curBackend == targetBackend &&
            cur.draftId == targetDraftId &&
            cur.listingInputGeneration == opGeneration &&
            cur.voiceListingOpId == opId) {
          final mat = (res.rawMaterialCost != null && res.rawMaterialCost! > 0)
              ? res.rawMaterialCost!
              : cur.rawMaterialCost;
          final hours = (res.laborHours != null && res.laborHours! > 0)
              ? res.laborHours!
              : cur.laborHours;
          final rate = (res.hourlyRate != null && res.hourlyRate! > 0)
              ? res.hourlyRate!
              : cur.hourlyRate;
          final calculatedFloor = mat + (hours * rate);
          final rawFloor = (res.floorPrice != null && res.floorPrice! > 0)
              ? res.floorPrice!
              : cur.floorPrice;
          final effectiveFloor = max(rawFloor, calculatedFloor);

          state = state.copyWith(
            titleEn: res.titleEn,
            titleHi: res.titleHi,
            descriptionEn: res.descriptionEn,
            descriptionHi: res.descriptionHi,
            category: res.category.isNotEmpty ? res.category : cur.category,
            tags: res.tags.isNotEmpty ? res.tags : cur.tags,
            rawMaterialCost: mat,
            laborHours: hours,
            hourlyRate: rate,
            floorPrice: effectiveFloor,
            minPrice: cur.minPrice < effectiveFloor ? effectiveFloor : cur.minPrice,
            finalPrice: cur.finalPrice < effectiveFloor ? effectiveFloor : cur.finalPrice,
            isListingDegraded: res.isDegraded,
            listingDegradedReason: res.degradedReason,
            isAiProcessing: false,
          );
          await _persistDraft();
        }
      }).catchError((err) async {
        await AiOperationStorage.updateResult(
          opId,
          status: AiOperationRecord.statusFailed,
          errorMessage: err.toString(),
        );
      });
      _trackBackgroundFuture(bgFuture);

      // Cap listing generation at 25 s for foreground UI responsiveness
      final suggestion = await networkFuture.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('[AddProductFlow] Listing generation timed out — using placeholder.');
          return AiListingSuggestion(
            titleEn: state.titleEn.isNotEmpty ? state.titleEn : transcript,
            titleHi: state.titleHi,
            descriptionEn: state.descriptionEn.isNotEmpty ? state.descriptionEn : transcript,
            descriptionHi: state.descriptionHi,
            category: state.category,
            tags: state.tags,
            isDegraded: true,
            degradedReason: 'Listing generation timed out after 25 seconds.',
          );
        },
      );

      final cur = state;
      final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final curBackend = ApiConfig.baseUrl;
      if (curOwner == targetOwner &&
          curBackend == targetBackend &&
          cur.draftId == targetDraftId &&
          cur.listingInputGeneration == opGeneration &&
          cur.voiceListingOpId == opId) {
        final mat = (suggestion.rawMaterialCost != null && suggestion.rawMaterialCost! > 0)
            ? suggestion.rawMaterialCost!
            : cur.rawMaterialCost;
        final hours = (suggestion.laborHours != null && suggestion.laborHours! > 0)
            ? suggestion.laborHours!
            : cur.laborHours;
        final rate = (suggestion.hourlyRate != null && suggestion.hourlyRate! > 0)
            ? suggestion.hourlyRate!
            : cur.hourlyRate;
        final calculatedFloor = mat + (hours * rate);
        final rawFloor = (suggestion.floorPrice != null && suggestion.floorPrice! > 0)
            ? suggestion.floorPrice!
            : cur.floorPrice;
        final effectiveFloor = max(rawFloor, calculatedFloor);

        state = state.copyWith(
          titleEn: suggestion.titleEn,
          titleHi: suggestion.titleHi,
          descriptionEn: suggestion.descriptionEn,
          descriptionHi: suggestion.descriptionHi,
          category: suggestion.category.isNotEmpty ? suggestion.category : state.category,
          tags: suggestion.tags.isNotEmpty ? suggestion.tags : state.tags,
          rawMaterialCost: mat,
          laborHours: hours,
          hourlyRate: rate,
          floorPrice: effectiveFloor,
          minPrice: cur.minPrice < effectiveFloor ? effectiveFloor : cur.minPrice,
          finalPrice: cur.finalPrice < effectiveFloor ? effectiveFloor : cur.finalPrice,
          isListingDegraded: suggestion.isDegraded,
          listingDegradedReason: suggestion.degradedReason,
          isAiProcessing: false,
        );
        await _persistDraft();
      }
    } catch (e) {
      debugPrint('[AddProductFlow] Error in generateAiListing: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') || errStr.contains('403') || errStr.contains('unauthorized')) {
        _ref.read(authStateProvider.notifier).expireSession();
      }
      state = state.copyWith(
        isAiProcessing: false,
        isListingDegraded: true,
        listingDegradedReason: 'Listing generation failed: $e',
      );
      await _persistDraft();
    }
  }

  Future<void> regenerateAll({String languageCode = 'en'}) async {
    state = state.copyWith(
      isEnhanced: false,
      enhancedImagePath: state.originalImagePath,
      isAiProcessing: true,
      isRegenerating: true, // overlay card, not full-screen
      imageQueueStatus: QueueStatus.pending,
    );
    await _persistDraft();

    final isOnline = _ref.read(connectivityProvider).value ?? true;

    Future<void>? enhanceFuture;
    if (isOnline && state.originalImagePath.isNotEmpty) {
      final imgFile = File(state.originalImagePath);
      if (imgFile.existsSync()) {
        enhanceFuture = _enhanceProductImage(imgFile);
      }
    }

    final listingFuture = generateAiListing(languageCode);

    try {
      await Future.wait([
        ?enhanceFuture,
        listingFuture,
      ]);
    } catch (e) {
      debugPrint('[AddProductFlow] Error during regenerateAll: $e');
    } finally {
      state = state.copyWith(isAiProcessing: false, isRegenerating: false);
      await _persistDraft();
    }
  }

  /// Manual escape hatch for the full-screen AI loader (Step 2 → 3), used
  /// only if a request hangs well beyond its own timeout.
  ///
  /// This must actually navigate the user back to Step 2 — just clearing
  /// isAiProcessing left currentStep on Step 3, so "Go back" silently
  /// dropped the user onto the offline-waiting screen (or a half-populated
  /// Step 3) instead of returning them to where they tapped Next.
  Future<void> cancelAiProcessing() async {
    _aiProcessingWatchdog?.cancel();
    // Invalidate any in-flight enhancement/listing requests from this
    // submission so a late response can't flip isAiProcessing back on
    // after the user has already left this screen.
    _aiProcessingGen++;
    state = state.copyWith(isAiProcessing: false, isRegenerating: false);
    if (state.currentStep == 2) {
      state = state.copyWith(currentStep: 1);
    }
    await _persistDraft();
  }

  /// Manual escape hatch for the full-screen pricing loader (Step 3 → 4).
  Future<void> cancelPricingProcessing() async {
    state = state.copyWith(isPricingProcessing: false);
    await _persistDraft();
  }

  Future<void> calculatePriceSuggestion() async {
    final pricingService = _ref.read(pricingServiceProvider);

    final desc = state.descriptionEn.isNotEmpty
        ? state.descriptionEn
        : (state.titleEn.isNotEmpty
            ? state.titleEn
            : (state.manualDescription.isNotEmpty
                ? state.manualDescription
                : state.voiceTranscript));

    final imagePath = state.enhancedImagePath.isNotEmpty
        ? state.enhancedImagePath
        : state.originalImagePath;

    final owner = _ref.read(authStateProvider).userId ?? 'anonymous';
    final backend = ApiConfig.baseUrl;

    final pricingInputs = <String, dynamic>{
      'description': desc.isNotEmpty ? desc : '${state.category} handcrafted product',
      'category': state.category,
      'tags': state.tags,
      'image_url': imagePath,
      'raw_material_cost': state.rawMaterialCost > 0 ? state.rawMaterialCost : null,
      'labor_hours': state.laborHours > 0 ? state.laborHours : null,
      'hourly_rate': (state.laborHours > 0 && state.hourlyRate > 0) ? state.hourlyRate : null,
    };

    final frozenPricingInputs = Map<String, dynamic>.from(pricingInputs);

    final fingerprint = await AiOperationRecord.computeFingerprint(
      operationType: 'pricing_suggest',
      owner: owner,
      backend: backend,
      inputs: frozenPricingInputs,
    );

    final String opId;
    final int opGeneration;
    if (state.pricingFingerprint == fingerprint && state.pricingOpId != null) {
      opId = state.pricingOpId!;
      opGeneration = state.pricingInputGeneration;
    } else {
      opGeneration = state.pricingInputGeneration + 1;
      opId = 'price_${state.draftId.isNotEmpty ? state.draftId : "temp"}_${fingerprint.substring(0, 12)}';
      final record = AiOperationRecord(
        id: opId,
        idempotencyKey: opId,
        owner: owner,
        backend: backend,
        operationType: 'pricing_suggest',
        draftId: state.draftId,
        inputGeneration: opGeneration,
        inputFingerprint: fingerprint,
        requestSnapshot: frozenPricingInputs,
        status: AiOperationRecord.statusInFlight,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await AiOperationStorage.save(record);
      state = state.copyWith(
        pricingOpId: opId,
        pricingFingerprint: fingerprint,
        pricingInputGeneration: opGeneration,
      );
      await _persistDraft();
    }

    final targetDraftId = state.draftId;
    final targetOwner = owner;
    final targetBackend = backend;

    final String reqDescription = (frozenPricingInputs['description'] as String?) ??
        (desc.isNotEmpty ? desc : '${state.category} handcrafted product');
    final String reqCategory = (frozenPricingInputs['category'] as String?) ?? state.category;
    final List<String> reqTags = (frozenPricingInputs['tags'] is List)
        ? (frozenPricingInputs['tags'] as List).map((e) => e.toString()).toList()
        : state.tags;
    final String? reqImageUrl = frozenPricingInputs['image_url'] as String?;
    final double? reqRawMaterialCost = (frozenPricingInputs['raw_material_cost'] as num?)?.toDouble();
    final double? reqLaborHours = (frozenPricingInputs['labor_hours'] as num?)?.toDouble();
    final double? reqHourlyWage = (frozenPricingInputs['hourly_rate'] as num?)?.toDouble();

    try {
      final networkFuture = pricingService.suggestPrice(
        description: reqDescription,
        category: reqCategory,
        tags: reqTags,
        imageUrl: reqImageUrl,
        rawMaterialCost: reqRawMaterialCost,
        laborHours: reqLaborHours,
        hourlyWage: reqHourlyWage,
        idempotencyKey: opId,
      );

      // Decouple background network future so late response is persisted to AiOperationStorage
      // without reviving superseded operations or being lost on UI timeout
      final bgFuture = networkFuture.then((suggestion) async {
        await AiOperationStorage.updateResult(
          opId,
          status: suggestion.isDegraded ? AiOperationRecord.statusFailed : AiOperationRecord.statusCompleted,
          resultData: {
            'floor_price': suggestion.floorPrice,
            'suggested_price': suggestion.suggestedPrice,
            'min_price': suggestion.minPrice,
            'max_price': suggestion.maxPrice,
            'confidence_score': suggestion.confidenceScore,
            'market_position': suggestion.marketPosition,
            'comparable_products': suggestion.comparableProducts
                .map((c) => c.toJson())
                .toList(),
            'reasoning': suggestion.reasoning,
            'reasoning_hi': suggestion.reasoningHi,
            'is_degraded': suggestion.isDegraded,
            'degraded_reason': suggestion.degradedReason,
          },
        );

        if (_isDisposed) return;
        final cur = state;
        final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
        final curBackend = ApiConfig.baseUrl;
        if (curOwner == targetOwner &&
            curBackend == targetBackend &&
            cur.draftId == targetDraftId &&
            cur.pricingInputGeneration == opGeneration &&
            cur.pricingOpId == opId) {
          final currentCostFloor = cur.rawMaterialCost + (cur.laborHours * cur.hourlyRate);
          final effectiveFloor = max(suggestion.floorPrice, currentCostFloor);
          final effectiveSuggested = max(suggestion.suggestedPrice, effectiveFloor);
          final effectiveMin = max(suggestion.minPrice, effectiveFloor);
          final effectiveMax = max(suggestion.maxPrice, effectiveFloor);

          state = state.copyWith(
            floorPrice: effectiveFloor,
            suggestedPrice: effectiveSuggested,
            minPrice: effectiveMin,
            maxPrice: effectiveMax,
            finalPrice: effectiveSuggested,
            confidenceScore: suggestion.confidenceScore,
            marketPosition: suggestion.marketPosition,
            comparableProducts: suggestion.comparableProducts,
            pricingReasoning: suggestion.reasoning,
            pricingReasoningHi: suggestion.reasoningHi,
            isPricingDegraded: suggestion.isDegraded,
            pricingDegradedReason: suggestion.degradedReason,
          );
          await _persistDraft();
        }
      }).catchError((e) async {
        await AiOperationStorage.updateResult(
          opId,
          status: AiOperationRecord.statusFailed,
          errorMessage: e.toString(),
        );
      });
      _trackBackgroundFuture(bgFuture);

      final suggestion = await networkFuture.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint('[AddProductFlow] Pricing calculation timed out — using cost floor.');
          final curCostFloor = state.rawMaterialCost + (state.laborHours * state.hourlyRate);
          return PriceSuggestion(
            floorPrice: curCostFloor,
            suggestedPrice: curCostFloor > 0 ? curCostFloor * 1.5 : 100.0,
            minPrice: curCostFloor,
            maxPrice: curCostFloor > 0 ? curCostFloor * 2.5 : 250.0,
            confidenceScore: 0.0,
            marketPosition: 'fair',
            comparableProducts: const [],
            reasoning: 'Pricing calculation timed out. Defaulted to calculated cost floor.',
            reasoningHi: 'मूल्य गणना समय समाप्त हो गई। गणना किए गए लागत आधार पर निर्धारित।',
            isDegraded: true,
            degradedReason: 'Pricing calculation timed out after 25 seconds.',
          );
        },
      );

      final cur = state;
      final curOwner = _ref.read(authStateProvider).userId ?? 'anonymous';
      final curBackend = ApiConfig.baseUrl;
      if (curOwner == targetOwner &&
          curBackend == targetBackend &&
          cur.draftId == targetDraftId &&
          cur.pricingInputGeneration == opGeneration &&
          cur.pricingOpId == opId) {
        final currentCostFloor = cur.rawMaterialCost + (cur.laborHours * cur.hourlyRate);
        final effectiveFloor = max(suggestion.floorPrice, currentCostFloor);
        final effectiveSuggested = max(suggestion.suggestedPrice, effectiveFloor);
        final effectiveMin = max(suggestion.minPrice, effectiveFloor);
        final effectiveMax = max(suggestion.maxPrice, effectiveFloor);

        state = state.copyWith(
          floorPrice: effectiveFloor,
          suggestedPrice: effectiveSuggested,
          minPrice: effectiveMin,
          maxPrice: effectiveMax,
          finalPrice: effectiveSuggested,
          confidenceScore: suggestion.confidenceScore,
          marketPosition: suggestion.marketPosition,
          comparableProducts: suggestion.comparableProducts,
          pricingReasoning: suggestion.reasoning,
          pricingReasoningHi: suggestion.reasoningHi,
          isPricingDegraded: suggestion.isDegraded,
          pricingDegradedReason: suggestion.degradedReason,
        );
        await _persistDraft();
      }
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('401') || errStr.contains('403') || errStr.contains('unauthorized')) {
        _ref.read(authStateProvider.notifier).expireSession();
      }
      final cur = state;
      if (cur.pricingInputGeneration == opGeneration && cur.pricingOpId == opId) {
        state = state.copyWith(
          isPricingDegraded: true,
          pricingDegradedReason: 'Pricing calculation failed: $e',
        );
        await _persistDraft();
      }
      rethrow;
    }
  }

  /// Called when the user taps "Looks Good!" on Step 3.
  /// Shows a pricing loading screen, calculates the AI price suggestion,
  /// then advances to Step 4 (pricing) and dismisses the loader.
  Future<void> submitForPricingAndAdvance() async {
    state = state.copyWith(isPricingProcessing: true);
    try {
      await calculatePriceSuggestion();
    } catch (e) {
      debugPrint('[AddProductFlow] Error calculating price: $e');
    } finally {
      state = state.copyWith(
        isPricingProcessing: false,
        currentStep: 3,
      );
      await _persistDraft();
    }
  }

  Future<void> updateCostParameters({
    double? materialCost,
    double? laborHours,
    double? hourlyRate,
  }) async {
    final mat = materialCost ?? state.rawMaterialCost;
    final hours = laborHours ?? state.laborHours;
    final rate = hourlyRate ?? state.hourlyRate;
    final floor = mat + (hours * rate);

    final newMin = state.minPrice < floor ? floor : state.minPrice;
    final newPrice = state.finalPrice < floor ? floor : state.finalPrice;
    final newPricingGen = state.pricingInputGeneration + 1;

    state = state.copyWith(
      rawMaterialCost: mat,
      laborHours: hours,
      hourlyRate: rate,
      floorPrice: floor,
      minPrice: newMin,
      finalPrice: newPrice,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );

    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  Future<void> setFinalPrice(double price) async {
    state = state.copyWith(finalPrice: price);
    await _persistDraft();
  }

  Future<void> updateListingDetails({
    String? titleEn,
    String? titleHi,
    String? descriptionEn,
    String? descriptionHi,
    String? category,
    List<String>? tags,
  }) async {
    final newListingGen = state.listingInputGeneration + 1;
    final newPricingGen = state.pricingInputGeneration + 1;

    state = state.copyWith(
      titleEn: titleEn ?? state.titleEn,
      titleHi: titleHi ?? state.titleHi,
      descriptionEn: descriptionEn ?? state.descriptionEn,
      descriptionHi: descriptionHi ?? state.descriptionHi,
      category: category ?? state.category,
      tags: tags ?? state.tags,
      listingInputGeneration: newListingGen,
      voiceListingOpId: null,
      listingFingerprint: null,
      pricingInputGeneration: newPricingGen,
      pricingOpId: null,
      pricingFingerprint: null,
    );

    await AiOperationStorage.markSuperseded(
      state.draftId,
      'listing_generate',
      newListingGen,
    );
    await AiOperationStorage.markSuperseded(
      state.draftId,
      'pricing_suggest',
      newPricingGen,
    );
    await _persistDraft();
  }

  void reset() {
    state = AddProductDraft(
      draftId: 'draft_${DateTime.now().microsecondsSinceEpoch}',
      hasExistingDraft: false,
      resumePromptHandled: true,
    );
    if (Hive.isBoxOpen('draft_box')) {
      Hive.box('draft_box').clear();
    }
  }
}

final addProductFlowProvider =
    StateNotifierProvider<AddProductFlowNotifier, AddProductDraft>((ref) {
      return AddProductFlowNotifier(ref);
    });

// --- Notifications Provider ---
enum NotificationType { listingLive, pendingSync, buyerView, priceSuggestion, newOrder }

class NotificationItem {
  final String id;
  final NotificationType type;
  final String messageKey;
  final DateTime timestamp;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.messageKey,
    required this.timestamp,
    this.isRead = false,
  });

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
        id: id,
        type: type,
        messageKey: messageKey,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );
}

class NotificationsNotifier extends StateNotifier<List<NotificationItem>> {
  NotificationsNotifier() : super(_initialNotifications());

  static List<NotificationItem> _initialNotifications() {
    final now = DateTime.now();
    return [
      NotificationItem(
        id: 'n1',
        type: NotificationType.newOrder,
        messageKey: 'notif_new_order',
        timestamp: now.subtract(const Duration(minutes: 15)),
      ),
      NotificationItem(
        id: 'n2',
        type: NotificationType.listingLive,
        messageKey: 'notif_listing_live',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      NotificationItem(
        id: 'n3',
        type: NotificationType.buyerView,
        messageKey: 'notif_buyer_viewed',
        timestamp: now.subtract(const Duration(hours: 5)),
      ),
      NotificationItem(
        id: 'n4',
        type: NotificationType.pendingSync,
        messageKey: 'notif_pending_sync',
        timestamp: now.subtract(const Duration(days: 1)),
      ),
      NotificationItem(
        id: 'n5',
        type: NotificationType.priceSuggestion,
        messageKey: 'notif_price_suggestion',
        timestamp: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  void markRead(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(isRead: true) else item,
    ];
  }

  void markAllRead() {
    state = [for (final item in state) item.copyWith(isRead: true)];
  }

  void addNotification(NotificationItem item) {
    state = [item, ...state];
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationItem>>((ref) {
  return NotificationsNotifier();
});

/// Derived provider — number of unread notifications (drives the bell badge).
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((n) => !n.isRead).length;
});

