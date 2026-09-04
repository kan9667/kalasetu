import 'dart:io';
import 'dart:async';
import 'dart:convert';

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

// --- Services Providers ---
final apiServiceProvider = Provider<ApiService>((ref) {
  return MockApiService();
});

final imageEnhancerServiceProvider = Provider<ImageEnhancerService>((ref) {
  return HttpImageEnhancerService();
});

final speechServiceProvider = Provider<SpeechService>((ref) {
  return HttpSpeechService();
});

final pricingServiceProvider = Provider<PricingService>((ref) {
  return MockPricingService();
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
    final created = await _repository.addProduct(product, isOnline: isOnline);
    await loadProducts();
    return created;
  }

  Future<Product> updateProduct(Product product) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    final updated = await _repository.updateProduct(
      product,
      isOnline: isOnline,
    );
    await loadProducts();
    return updated;
  }

  Future<void> deleteProduct(String id) async {
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    await _repository.deleteProduct(id, isOnline: isOnline);
    await loadProducts();
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
  final bool isAiProcessing;
  final List<String> additionalImagePaths;
  final bool isRetakeFlow;
  final bool hasExistingDraft;
  final bool resumePromptHandled;
  final String? imageQueueItemId;
  final String? voiceQueueItemId;
  final QueueStatus imageQueueStatus;
  final QueueStatus voiceQueueStatus;

  const AddProductDraft({
    this.draftId = '',
    this.currentStep = 0,
    this.originalImagePath = '',
    this.enhancedImagePath = '',
    this.isEnhanced = false,
    this.recordedAudioPath = '',
    this.voiceTranscript = '',
    this.transcriptionConfidence = 1.0,
    this.manualDescription = '',
    this.titleEn = '',
    this.titleHi = '',
    this.descriptionEn = '',
    this.descriptionHi = '',
    this.category = 'Pottery',
    this.tags = const ['terracotta', 'handcrafted', 'sustainable'],
    this.rawMaterialCost = 150.0,
    this.laborHours = 3.0,
    this.hourlyRate = 120.0,
    this.floorPrice = 510.0,
    this.suggestedPrice = 750.0,
    this.minPrice = 510.0,
    this.maxPrice = 1100.0,
    this.finalPrice = 750.0,
    this.pricingReasoning =
        'Evaluated based on pure river clay sourcing, wheel sculpting time, and fair wage floor.',
    this.pricingReasoningHi =
        'प्राकृतिक नदी की मिट्टी, चाक पर गढ़ने का समय और उचित पारिश्रमिक के आधार पर विश्लेषित।',
    this.isAiProcessing = false,
    this.additionalImagePaths = const [],
    this.isRetakeFlow = false,
    this.hasExistingDraft = false,
    this.resumePromptHandled = false,
    this.imageQueueItemId,
    this.voiceQueueItemId,
    this.imageQueueStatus = QueueStatus.completed,
    this.voiceQueueStatus = QueueStatus.completed,
  });

  AddProductDraft copyWith({
    String? draftId,
    int? currentStep,
    String? originalImagePath,
    String? enhancedImagePath,
    bool? isEnhanced,
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
    bool? isAiProcessing,
    List<String>? additionalImagePaths,
    bool? isRetakeFlow,
    bool? hasExistingDraft,
    bool? resumePromptHandled,
    Object? imageQueueItemId = _unset,
    Object? voiceQueueItemId = _unset,
    QueueStatus? imageQueueStatus,
    QueueStatus? voiceQueueStatus,
  }) {
    return AddProductDraft(
      draftId: draftId ?? this.draftId,
      currentStep: currentStep ?? this.currentStep,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      enhancedImagePath: enhancedImagePath ?? this.enhancedImagePath,
      isEnhanced: isEnhanced ?? this.isEnhanced,
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
      isAiProcessing: isAiProcessing ?? this.isAiProcessing,
      additionalImagePaths: additionalImagePaths ?? this.additionalImagePaths,
      isRetakeFlow: isRetakeFlow ?? this.isRetakeFlow,
      hasExistingDraft: hasExistingDraft ?? this.hasExistingDraft,
      resumePromptHandled: resumePromptHandled ?? this.resumePromptHandled,
      imageQueueItemId: identical(imageQueueItemId, _unset)
          ? this.imageQueueItemId
          : imageQueueItemId as String?,
      voiceQueueItemId: identical(voiceQueueItemId, _unset)
          ? this.voiceQueueItemId
          : voiceQueueItemId as String?,
      imageQueueStatus: imageQueueStatus ?? this.imageQueueStatus,
      voiceQueueStatus: voiceQueueStatus ?? this.voiceQueueStatus,
    );
  }
}

class AddProductFlowNotifier extends StateNotifier<AddProductDraft> {
  final Ref _ref;
  StreamSubscription<List<QueueItem>>? _imageQueueSubscription;
  StreamSubscription<List<QueueItem>>? _voiceQueueSubscription;
  bool _processingSubmissionInProgress = false;
  Completer<bool>? _imageEnhancingCompleter;
  Map<String, dynamic>? _pendingDraft;

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
    _imageQueueSubscription?.cancel();
    _voiceQueueSubscription?.cancel();
    super.dispose();
  }

  void _loadDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      final values = <String, dynamic>{
        for (final key in box.keys) key.toString(): box.get(key),
      };
      if (values.isNotEmpty &&
          (values['draft_id'] != null ||
              values['draft_original_image'] != null ||
              values['draft_image'] != null)) {
        _pendingDraft = values;
        state = state.copyWith(
          hasExistingDraft: true,
          resumePromptHandled: false,
        );
      }
    }
  }

  void loadSavedDraftState({
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
    String? imageQueueItemId,
    String? voiceQueueItemId,
    QueueStatus? imageQueueStatus,
    QueueStatus? voiceQueueStatus,
  }) {
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

    state = state.copyWith(
      draftId: draftId,
      originalImagePath: originalImagePath,
      enhancedImagePath: enhancedImagePath,
      isEnhanced:
          enhancedImagePath.isNotEmpty &&
          enhancedImagePath != originalImagePath,
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
      currentStep: resolvedStep,
      additionalImagePaths: additionalImagePaths,
      imageQueueItemId: imageQueueItemId,
      voiceQueueItemId: voiceQueueItemId,
      imageQueueStatus: imageQueueStatus ?? QueueStatus.completed,
      voiceQueueStatus: voiceQueueStatus ?? QueueStatus.completed,
      hasExistingDraft: true,
      resumePromptHandled: false,
      isAiProcessing: false,
    );
  }

  void markResumePromptVisible() {
    state = state.copyWith(resumePromptHandled: true);
  }

  void resumeExistingDraft() {
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
        imageQueueItemId: pending['draft_image_queue_id'] as String?,
        voiceQueueItemId: pending['draft_voice_queue_id'] as String?,
        imageQueueStatus: _queueStatus(pending['draft_image_queue_status']),
        voiceQueueStatus: _queueStatus(pending['draft_voice_queue_status']),
      );
      _hydrateQueueState();
    }
    _pendingDraft = null;
    state = state.copyWith(
      hasExistingDraft: false,
      resumePromptHandled: true,
      isAiProcessing: false,
    );
  }

  void discardPreviousDraft() {
    _pendingDraft = null;
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

  void _persistDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      box.put('draft_id', state.draftId);
      box.put('draft_step', state.currentStep);
      box.put('draft_image', state.originalImagePath);
      box.put('draft_original_image', state.originalImagePath);
      box.put('draft_enhanced_image', state.enhancedImagePath);
      box.put('draft_audio', state.recordedAudioPath);
      box.put('draft_transcript', state.voiceTranscript);
      box.put('draft_manual_description', state.manualDescription);
      box.put('draft_title_en', state.titleEn);
      box.put('draft_title_hi', state.titleHi);
      box.put('draft_description_en', state.descriptionEn);
      box.put('draft_description_hi', state.descriptionHi);
      box.put('draft_category', state.category);
      box.put('draft_tags', state.tags);
      box.put('draft_raw_material_cost', state.rawMaterialCost);
      box.put('draft_labor_hours', state.laborHours);
      box.put('draft_hourly_rate', state.hourlyRate);
      box.put('draft_floor_price', state.floorPrice);
      box.put('draft_suggested_price', state.suggestedPrice);
      box.put('draft_min_price', state.minPrice);
      box.put('draft_max_price', state.maxPrice);
      box.put('draft_final_price', state.finalPrice);
      box.put('draft_pricing_reasoning', state.pricingReasoning);
      box.put('draft_pricing_reasoning_hi', state.pricingReasoningHi);
      box.put('draft_additional_images', state.additionalImagePaths);
      box.put('draft_image_queue_id', state.imageQueueItemId);
      box.put('draft_voice_queue_id', state.voiceQueueItemId);
      box.put('draft_image_queue_status', state.imageQueueStatus.index);
      box.put('draft_voice_queue_status', state.voiceQueueStatus.index);
    }
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
  void confirmPhoto() {
    if (state.isRetakeFlow) {
      state = state.copyWith(currentStep: 2, isRetakeFlow: false);
    } else {
      nextStep();
    }
  }

  void setStep(int step) {
    state = state.copyWith(currentStep: step);
    _persistDraft();
  }

  void nextStep() {
    if (state.currentStep < 4) {
      state = state.copyWith(currentStep: state.currentStep + 1);
      _persistDraft();
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
      _persistDraft();
    }
  }

  Future<void> setImage(String path) async {
    _processingSubmissionInProgress = false;
    state = state.copyWith(
      originalImagePath: path,
      enhancedImagePath: path,
      isEnhanced: false,
      isAiProcessing: false,
      imageQueueItemId: null,
    );
    _persistDraft();
  }

  Future<String> queueImage(File imageFile) async {
    _processingSubmissionInProgress = false;
    final durablePath = await _copyImageToDraftStorage(imageFile);
    state = state.copyWith(
      originalImagePath: durablePath,
      enhancedImagePath: durablePath,
      isEnhanced: false,
      isAiProcessing: false,
      imageQueueItemId: null,
    );
    _persistDraft();
    return '';
  }

  Future<String> _copyImageToDraftStorage(File imageFile) async {
    if (!imageFile.existsSync()) return imageFile.path;
    final appDir = await getApplicationDocumentsDirectory();
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

    try {
      final hasPendingAi = !state.isEnhanced || state.titleEn.isEmpty;
      state = state.copyWith(isAiProcessing: isOnline && hasPendingAi);

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
            final localId = await OfflineSyncService.instance.enqueueImage(
              imageFile: imgFile,
              productDraftId: state.draftId,
            );
            state = state.copyWith(
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
            unawaited(_enhanceProductImage(imageFile));
          }
        }

        if (OfflineSyncService.instance.isInitialized) {
          unawaited(OfflineSyncService.instance.triggerSyncNow());
        }

        // If manual description was provided instead of voice, generate listing
        if (state.titleEn.isEmpty &&
            state.manualDescription.isNotEmpty &&
            state.recordedAudioPath.isEmpty) {
          unawaited(_generateListingFromManualDescription(languageCode));
        }
      } else {
        // Offline: keep items saved in draft and queue, wait for connectivity
        state = state.copyWith(isAiProcessing: false);
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
    state = state.copyWith(isAiProcessing: true);

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

  Future<void> _enhanceProductImage(File imageFile) async {
    try {
      final enhancer = _ref.read(imageEnhancerServiceProvider);
      final enhancedUrl = await enhancer.enhanceImage(
        imageFile.path,
        draftId: state.draftId,
      );
      if (enhancedUrl.isEmpty || enhancedUrl == imageFile.path) {
        state = state.copyWith(isAiProcessing: false);
        return;
      }

      state = state.copyWith(
        enhancedImagePath: enhancedUrl,
        isEnhanced: true,
        isAiProcessing: false,
        imageQueueStatus: QueueStatus.completed,
      );
      _persistDraft();
    } catch (e, st) {
      debugPrint('[AddProductFlow] AI enhancement error: $e\n$st');
      state = state.copyWith(isAiProcessing: false);
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
      final enhancedUrl =
          result?['enhancedImageUrl'] as String? ??
          result?['enhanced_url'] as String?;
      final hasNewEnhancedUrl = enhancedUrl != null &&
          enhancedUrl.isNotEmpty &&
          enhancedUrl != state.originalImagePath;
      state = state.copyWith(
        imageQueueItemId: item.localId,
        imageQueueStatus: item.status,
        enhancedImagePath:
            hasNewEnhancedUrl ? enhancedUrl : state.enhancedImagePath,
        isEnhanced: state.isEnhanced || hasNewEnhancedUrl,
        isAiProcessing: state.voiceQueueItemId != null &&
            state.voiceQueueStatus != QueueStatus.completed,
      );
    } else {
      final pricing = result?['pricing'] as Map<String, dynamic>?;
      final suggestedPrice = (pricing?['suggested_price'] as num?)?.toDouble();
      final floorPrice = (pricing?['floor_price'] as num?)?.toDouble();
      final priceRange = pricing?['price_range'] as Map<String, dynamic>?;
      final minPrice = (priceRange?['min'] as num?)?.toDouble();
      final maxPrice = (priceRange?['max'] as num?)?.toDouble();
      final reasoning = pricing?['reasoning'] as String?;
      final reasoningHi = pricing?['reasoning_hi'] as String?;

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
        isAiProcessing: item.status != QueueStatus.completed &&
            item.status != QueueStatus.failed,
      );
    }
    _persistDraft();
  }

  Future<void> _generateListingFromManualDescription(
    String languageCode,
  ) async {
    try {
      state = state.copyWith(isAiProcessing: true);
      final speechService = _ref.read(speechServiceProvider);
      final suggestion = await speechService.generateListingFromTranscript(
        transcript: state.manualDescription,
        languageCode: languageCode,
        categoryHint: state.category,
      );
      state = state.copyWith(
        titleEn: suggestion.titleEn,
        titleHi: suggestion.titleHi,
        descriptionEn: suggestion.descriptionEn,
        descriptionHi: suggestion.descriptionHi,
        category: suggestion.category,
        tags: suggestion.tags,
        isAiProcessing: !state.isEnhanced && state.originalImagePath.isNotEmpty,
      );
      _persistDraft();
    } catch (_) {
      state = state.copyWith(
        titleEn: state.manualDescription,
        descriptionEn: state.manualDescription,
        isAiProcessing: !state.isEnhanced && state.originalImagePath.isNotEmpty,
      );
      _persistDraft();
    }
  }

  Future<void> addAdditionalImage(String path) async {
    if (state.additionalImagePaths.length >= 2) return;
    state = state.copyWith(
      additionalImagePaths: [...state.additionalImagePaths, path],
    );
    _persistDraft();
  }

  void removeAdditionalImage(String path) {
    state = state.copyWith(
      additionalImagePaths: state.additionalImagePaths
          .where((p) => p != path)
          .toList(),
    );
    _persistDraft();
  }

  void addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty || state.tags.contains(trimmed)) return;
    state = state.copyWith(tags: [...state.tags, trimmed]);
    _persistDraft();
  }

  void removeTag(String tag) {
    state = state.copyWith(tags: state.tags.where((t) => t != tag).toList());
    _persistDraft();
  }

  void setManualDescription(String desc) {
    state = state.copyWith(manualDescription: desc);
    _persistDraft();
  }

  void retakeDescription() {
    state = state.copyWith(
      recordedAudioPath: '',
      voiceTranscript: '',
      manualDescription: '',
      voiceQueueItemId: null,
    );
    setStep(1);
  }

  Future<void> processVoiceRecording({
    required String audioPath,
    required String languageCode,
  }) async {
    state = state.copyWith(
      recordedAudioPath: audioPath,
      voiceQueueItemId: null,
    );
    _persistDraft();
  }

  Future<String> queueVoiceRecording(File audioFile) async {
    state = state.copyWith(
      recordedAudioPath: audioFile.path,
      voiceQueueStatus: QueueStatus.pending,
    );
    _persistDraft();

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

  Future<void> transcribeVoiceDirectly(File audioFile, {String languageCode = 'hi'}) async {
    try {
      final speechService = _ref.read(speechServiceProvider);
      final result = await speechService.transcribeAudio(
        audioPath: audioFile.path,
        languageCode: languageCode,
      );
      if (result.transcript.isNotEmpty &&
          !HttpSpeechService.isSilenceHallucination(result.transcript)) {
        state = state.copyWith(
          voiceTranscript: result.transcript,
          transcriptionConfidence: result.confidence,
        );
        _persistDraft();
      }
    } catch (e) {
      debugPrint('[AddProductFlow] Error during direct voice transcription: $e');
    }
  }

  Future<void> retakePhoto(File newPhoto) async {
    final durablePath = await _copyImageToDraftStorage(newPhoto);
    state = state.copyWith(
      originalImagePath: durablePath,
      enhancedImagePath: durablePath,
      isEnhanced: false,
      imageQueueItemId: null,
      imageQueueStatus: QueueStatus.pending,
    );
    _persistDraft();
    final isOnline = _ref.read(connectivityProvider).value ?? true;
    if (isOnline) {
      unawaited(_enhanceProductImage(File(durablePath)));
    }
  }

  Future<void> retakeVoice(File newAudio) async {
    state = state.copyWith(
      recordedAudioPath: newAudio.path,
      voiceTranscript: '',
      voiceQueueItemId: null,
      voiceQueueStatus: QueueStatus.pending,
    );
    _persistDraft();
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

  void clearVoiceRecording() {
    state = state.copyWith(
      recordedAudioPath: '',
      voiceTranscript: '',
      voiceQueueItemId: null,
      voiceQueueStatus: QueueStatus.completed,
    );
    _persistDraft();
  }

  Future<void> generateAiListing(String languageCode) async {
    state = state.copyWith(isAiProcessing: true);
    if (state.recordedAudioPath.isNotEmpty &&
        OfflineSyncService.instance.isInitialized) {
      final audioFile = File(state.recordedAudioPath);
      if (audioFile.existsSync()) {
        try {
          final localId = await OfflineSyncService.instance.enqueueVoiceNote(
            audioFile: audioFile,
            productDraftId: state.draftId,
          );
          state = state.copyWith(voiceQueueItemId: localId);
          _watchVoiceQueue(localId);
          await OfflineSyncService.instance.triggerSyncNow();
        } catch (_) {}
      }
    } else if (state.manualDescription.isNotEmpty) {
      await _generateListingFromManualDescription(languageCode);
    } else {
      state = state.copyWith(isAiProcessing: false);
    }
  }

  Future<void> calculatePriceSuggestion() async {
    final pricingService = _ref.read(pricingServiceProvider);
    final suggestion = await pricingService.suggestPrice(
      category: state.category,
      tags: state.tags,
      rawMaterialCost: state.rawMaterialCost,
      laborHours: state.laborHours,
      hourlyWage: state.hourlyRate,
    );

    state = state.copyWith(
      floorPrice: suggestion.floorPrice,
      suggestedPrice: suggestion.suggestedPrice,
      minPrice: suggestion.minPrice,
      maxPrice: suggestion.maxPrice,
      finalPrice: suggestion.suggestedPrice,
      pricingReasoning: suggestion.reasoning,
      pricingReasoningHi: suggestion.reasoningHi,
    );
  }

  void updateCostParameters({
    double? materialCost,
    double? laborHours,
    double? hourlyRate,
  }) {
    final mat = materialCost ?? state.rawMaterialCost;
    final hours = laborHours ?? state.laborHours;
    final rate = hourlyRate ?? state.hourlyRate;
    final floor = mat + (hours * rate);

    final newMin = state.minPrice < floor ? floor : state.minPrice;
    final newPrice = state.finalPrice < floor ? floor : state.finalPrice;

    state = state.copyWith(
      rawMaterialCost: mat,
      laborHours: hours,
      hourlyRate: rate,
      floorPrice: floor,
      minPrice: newMin,
      finalPrice: newPrice,
    );
  }

  void setFinalPrice(double price) {
    state = state.copyWith(finalPrice: price);
  }

  void updateListingDetails({
    String? titleEn,
    String? titleHi,
    String? descriptionEn,
    String? descriptionHi,
    String? category,
    List<String>? tags,
  }) {
    state = state.copyWith(
      titleEn: titleEn ?? state.titleEn,
      titleHi: titleHi ?? state.titleHi,
      descriptionEn: descriptionEn ?? state.descriptionEn,
      descriptionHi: descriptionHi ?? state.descriptionHi,
      category: category ?? state.category,
      tags: tags ?? state.tags,
    );
    _persistDraft();
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
enum NotificationType { listingLive, pendingSync, buyerView, priceSuggestion }

class NotificationItem {
  final String id;
  final NotificationType type;
  final String messageKey;
  final DateTime timestamp;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.messageKey,
    required this.timestamp,
  });
}

final notificationsProvider = Provider<List<NotificationItem>>((ref) {
  final now = DateTime.now();
  return [
    NotificationItem(
      id: 'n1',
      type: NotificationType.listingLive,
      messageKey: 'notif_listing_live',
      timestamp: now.subtract(const Duration(hours: 2)),
    ),
    NotificationItem(
      id: 'n2',
      type: NotificationType.buyerView,
      messageKey: 'notif_buyer_viewed',
      timestamp: now.subtract(const Duration(hours: 5)),
    ),
    NotificationItem(
      id: 'n3',
      type: NotificationType.pendingSync,
      messageKey: 'notif_pending_sync',
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    NotificationItem(
      id: 'n4',
      type: NotificationType.priceSuggestion,
      messageKey: 'notif_price_suggestion',
      timestamp: now.subtract(const Duration(days: 2)),
    ),
  ];
});
