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

// --- Services Providers ---
final apiServiceProvider = Provider<ApiService>((ref) {
  return MockApiService();
});

final imageEnhancerServiceProvider = Provider<ImageEnhancerService>((ref) {
  return MockImageEnhancerService();
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

  ProductListNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
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
    final syncService = _ref.read(syncServiceProvider);
    final count = await syncService.triggerSync();
    await loadProducts();
    return count;
  }
}

final productListProvider =
    StateNotifierProvider<ProductListNotifier, AsyncValue<List<Product>>>((ref) {
  final repository = ref.watch(productRepositoryProvider);
  return ProductListNotifier(repository, ref);
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
  final int currentStep; // 0 to 4
  final String originalImagePath;
  final String enhancedImagePath;
  final bool isEnhanced;
  final String recordedAudioPath;
  final String voiceTranscript;
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

  const AddProductDraft({
    this.currentStep = 0,
    this.originalImagePath = '',
    this.enhancedImagePath = '',
    this.isEnhanced = false,
    this.recordedAudioPath = '',
    this.voiceTranscript = '',
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
  });

  AddProductDraft copyWith({
    int? currentStep,
    String? originalImagePath,
    String? enhancedImagePath,
    bool? isEnhanced,
    String? recordedAudioPath,
    String? voiceTranscript,
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
  }) {
    return AddProductDraft(
      currentStep: currentStep ?? this.currentStep,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      enhancedImagePath: enhancedImagePath ?? this.enhancedImagePath,
      isEnhanced: isEnhanced ?? this.isEnhanced,
      recordedAudioPath: recordedAudioPath ?? this.recordedAudioPath,
      voiceTranscript: voiceTranscript ?? this.voiceTranscript,
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
    );
  }
}

class AddProductFlowNotifier extends StateNotifier<AddProductDraft> {
  final Ref _ref;

  AddProductFlowNotifier(this._ref) : super(const AddProductDraft()) {
    _loadDraft();
  }

  void _loadDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      final image = box.get('draft_image') as String?;
      final transcript = box.get('draft_transcript') as String?;
      if (image != null || transcript != null) {
        state = state.copyWith(
          originalImagePath: image ?? '',
          enhancedImagePath: image ?? '',
          voiceTranscript: transcript ?? '',
        );
      }
    }
  }

  void _persistDraft() {
    if (Hive.isBoxOpen('draft_box')) {
      final box = Hive.box('draft_box');
      box.put('draft_image', state.enhancedImagePath.isNotEmpty ? state.enhancedImagePath : state.originalImagePath);
      box.put('draft_transcript', state.voiceTranscript);
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
      isAiProcessing: true,
    );

    final enhancer = _ref.read(imageEnhancerServiceProvider);
    final enhanced = await enhancer.enhanceImage(path);

    state = state.copyWith(
      enhancedImagePath: enhanced,
      isEnhanced: true,
      isAiProcessing: false,
    );
    _persistDraft();
  }

  void setManualDescription(String desc) {
    state = state.copyWith(manualDescription: desc);
    _persistDraft();
  }

  Future<void> processVoiceRecording({
    required String audioPath,
    required String languageCode,
  }) async {
    state = state.copyWith(
      recordedAudioPath: audioPath,
      isAiProcessing: true,
    );

    final speechService = _ref.read(speechServiceProvider);
    final transcript = await speechService.transcribeAudio(
      audioPath: audioPath,
      languageCode: languageCode,
    );

    state = state.copyWith(
      voiceTranscript: transcript,
      isAiProcessing: false,
    );
    _persistDraft();
  }

  Future<void> generateAiListing(String languageCode) async {
    state = state.copyWith(isAiProcessing: true);

    final speechService = _ref.read(speechServiceProvider);
    final content = state.voiceTranscript.isNotEmpty
        ? state.voiceTranscript
        : state.manualDescription;

    final suggestion = await speechService.generateListingFromTranscript(
      transcript: content,
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
      isAiProcessing: false,
    );

    // Also trigger price suggestion
    await calculatePriceSuggestion();
    _persistDraft();
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
    // Ensure final price cannot go below ethical floor
    final safePrice = price < state.floorPrice ? state.floorPrice : price;
    state = state.copyWith(finalPrice: safePrice);
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
    state = const AddProductDraft();
    if (Hive.isBoxOpen('draft_box')) {
      Hive.box('draft_box').clear();
    }
  }
}

final addProductFlowProvider =
    StateNotifierProvider<AddProductFlowNotifier, AddProductDraft>((ref) {
  return AddProductFlowNotifier(ref);
});
