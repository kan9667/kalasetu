import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  return MockSpeechService();
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
    final updated = await _repository.updateProduct(product, isOnline: isOnline);
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
    StateNotifierProvider<ProductListNotifier, AsyncValue<List<Product>>>((ref) {
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
    this.pricingReasoning = 'Evaluated based on pure river clay sourcing, wheel sculpting time, and fair wage floor.',
    this.pricingReasoningHi = 'प्राकृतिक नदी की मिट्टी, चाक पर गढ़ने का समय और उचित पारिश्रमिक के आधार पर विश्लेषित।',
    this.isAiProcessing = false,
    this.additionalImagePaths = const [],
    this.isRetakeFlow = false,
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
    String? imageQueueItemId,
    String? voiceQueueItemId,
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
      transcriptionConfidence: transcriptionConfidence ?? this.transcriptionConfidence,
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
      imageQueueItemId: imageQueueItemId ?? this.imageQueueItemId,
      voiceQueueItemId: voiceQueueItemId ?? this.voiceQueueItemId,
      imageQueueStatus: imageQueueStatus ?? this.imageQueueStatus,
      voiceQueueStatus: voiceQueueStatus ?? this.voiceQueueStatus,
    );
  }
}

class AddProductFlowNotifier extends StateNotifier<AddProductDraft> {
  final Ref _ref;
  StreamSubscription<List<QueueItem>>? _queueSubscription;

  AddProductFlowNotifier(this._ref)
      : super(AddProductDraft(draftId: 'draft_${DateTime.now().microsecondsSinceEpoch}')) {
    _loadDraft();
    if (OfflineSyncService.instance.isInitialized) {
      _queueSubscription = OfflineSyncService.instance.watchQueue().listen(_handleQueueItems);
    }
  }

  void _handleQueueItems(List<QueueItem> items) {
    for (final item in items.where((item) => item.productDraftId == state.draftId)) {
      if (item.type == QueueItemType.imageEnhance) {
        state = state.copyWith(imageQueueStatus: item.status);
      } else {
        state = state.copyWith(voiceQueueStatus: item.status);
      }

      if (item.status != QueueStatus.completed || item.resultJson == null) continue;

      final result = jsonDecode(item.resultJson!) as Map<String, dynamic>;
      if (item.type == QueueItemType.imageEnhance) {
        final enhancedUrl = result['enhancedImageUrl'] as String?;
        if (enhancedUrl != null && enhancedUrl.isNotEmpty) {
          state = state.copyWith(
            enhancedImagePath: enhancedUrl,
            isEnhanced: true,
          );
        }
      } else {
        state = state.copyWith(
          voiceTranscript: result['transcript'] as String? ?? state.voiceTranscript,
          titleEn: result['titleEn'] as String? ?? state.titleEn,
          titleHi: result['titleHi'] as String? ?? state.titleHi,
          descriptionEn: result['descriptionEn'] as String? ?? state.descriptionEn,
          descriptionHi: result['descriptionHi'] as String? ?? state.descriptionHi,
          category: result['category'] as String? ?? state.category,
          tags: (result['tags'] as List<dynamic>?)?.map((tag) => tag.toString()).toList() ?? state.tags,
        );
      }
      _persistDraft();
    }
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    super.dispose();
  }

  void _loadDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      final draftId = box.get('draft_id') as String?;
      final image = box.get('draft_image') as String?;
      final transcript = box.get('draft_transcript') as String?;
      final additional = (box.get('draft_additional_images') as List?)
          ?.map((e) => e.toString())
          .toList();
      if (draftId != null || image != null || transcript != null || additional != null) {
        state = state.copyWith(
          draftId: draftId,
          originalImagePath: image ?? '',
          enhancedImagePath: image ?? '',
          voiceTranscript: transcript ?? '',
          additionalImagePaths: additional ?? [],
        );
      }
    }
  }

  void _persistDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      box.put('draft_id', state.draftId);
      box.put('draft_image', state.enhancedImagePath.isNotEmpty ? state.enhancedImagePath : state.originalImagePath);
      box.put('draft_transcript', state.voiceTranscript);
      box.put('draft_additional_images', state.additionalImagePaths);
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
  }

  void nextStep() {
    if (state.currentStep < 4) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  Future<void> setImage(String path) async {
    state = state.copyWith(
      originalImagePath: path,
      enhancedImagePath: path,
      isEnhanced: true,
    );
    _persistDraft();
  }

  Future<String> queueImage(File imageFile) async {
    state = state.copyWith(
      originalImagePath: imageFile.path,
      enhancedImagePath: imageFile.path,
      isEnhanced: false,
      isAiProcessing: true,
      imageQueueStatus: QueueStatus.pending,
    );

    String localId = '';
    if (OfflineSyncService.instance.isInitialized) {
      try {
        localId = await OfflineSyncService.instance.enqueueImage(
          imageFile: imageFile,
          productDraftId: state.draftId,
        );
      } catch (_) {}
    }
    state = state.copyWith(imageQueueItemId: localId);
    _persistDraft();

    // Trigger HTTP AI Image Enhancement
    unawaited(_enhanceProductImage(imageFile));

    return localId;
  }

  Future<void> _enhanceProductImage(File imageFile) async {
    try {
      debugPrint('[AddProductFlow] Triggering AI Enhancer for: ${imageFile.path}');
      final enhancer = _ref.read(imageEnhancerServiceProvider);
      final enhancedUrl = await enhancer.enhanceImage(
        imageFile.path,
        draftId: state.draftId,
      );
      debugPrint('[AddProductFlow] Received enhancedUrl: $enhancedUrl (original: ${imageFile.path})');
      if (enhancedUrl.isNotEmpty && enhancedUrl != imageFile.path) {
        state = state.copyWith(
          enhancedImagePath: enhancedUrl,
          isEnhanced: true,
          isAiProcessing: false,
          imageQueueStatus: QueueStatus.completed,
        );
        _persistDraft();
        debugPrint('[AddProductFlow] State updated: isEnhanced=true, enhancedImagePath=$enhancedUrl');
      } else {
        state = state.copyWith(isAiProcessing: false);
      }
    } catch (e, st) {
      debugPrint('[AddProductFlow] AI enhancement error: $e\n$st');
      state = state.copyWith(isAiProcessing: false);
    }
  }

  Future<void> addAdditionalImage(String path) async {
    if (state.additionalImagePaths.length >= 2) return;
    state = state.copyWith(additionalImagePaths: [...state.additionalImagePaths, path]);
    _persistDraft();
  }

  void removeAdditionalImage(String path) {
    state = state.copyWith(
      additionalImagePaths: state.additionalImagePaths.where((p) => p != path).toList(),
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
    );
    setStep(1);
  }

  Future<void> processVoiceRecording({
    required String audioPath,
    required String languageCode,
  }) async {
    await queueVoiceRecording(File(audioPath));
  }

  Future<String> queueVoiceRecording(File audioFile) async {
    state = state.copyWith(
      recordedAudioPath: audioFile.path,
      voiceQueueStatus: QueueStatus.pending,
    );

    final localId = await OfflineSyncService.instance.enqueueVoiceNote(
      audioFile: audioFile,
      productDraftId: state.draftId,
    );
    state = state.copyWith(voiceQueueItemId: localId);
    _persistDraft();
    return localId;
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
    // The queued voice job owns listing generation. A result coordinator will
    // populate this draft when the backend completes the job.
    state = state.copyWith(isAiProcessing: false);
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
    state = AddProductDraft(draftId: 'draft_${DateTime.now().microsecondsSinceEpoch}');
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