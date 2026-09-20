import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kalasetu/core/providers/app_providers.dart';
import 'package:kalasetu/data/models/product.dart';
import 'package:kalasetu/data/models/user_profile.dart';
import 'package:kalasetu/data/services/pricing_service.dart';

class PricingProbe extends MockPricingService {
  final keys = <String?>[];
  final costs = <double?>[];
  @override
  Future<PriceSuggestion> suggestPrice({String? description, required String category, required List<String> tags, String? imageUrl, double? rawMaterialCost, double? laborHours, double? hourlyWage, String? idempotencyKey}) async {
    keys.add(idempotencyKey);
    costs.add(rawMaterialCost);
    return const PriceSuggestion(minPrice: 100, maxPrice: 500, suggestedPrice: 300, floorPrice: 100, reasoning: 'probe', reasoningHi: 'probe');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;
  late PricingProbe pricing;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kalasetu_identity_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ProductStatusAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(UserProfileAdapter());
    final authBox = await Hive.openBox('auth_box');
    await authBox.put('user_id', 'artisan_probe');
    await authBox.put('phone_number', '+919876543210');
    await authBox.put('is_authenticated', true);
    await Hive.openBox('draft_box');
    await Hive.openBox<String>('ai_operations_box');
    await Hive.openBox<UserProfile>('user_profile_box');
    pricing = PricingProbe();
    container = ProviderContainer(overrides: [pricingServiceProvider.overrideWithValue(pricing)]);
  });
  tearDown(() async {
    final flow = container.read(addProductFlowProvider.notifier);
    await flow.awaitActiveBackgroundFutures();
    container.dispose();
    await Hive.close();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('retaking a photo invalidates old approved-media candidate', () async {
    final flow = container.read(addProductFlowProvider.notifier);
    await flow.loadSavedDraftState(draftId: 'draft_probe', originalImagePath: '/old.jpg', enhancedImagePath: '/old_enhanced.jpg', transcript: 'pot', mediaId: 'med_old', originalMediaId: 'med_raw_old', sha256Checksum: 'a' * 64, imageEnhanceOpId: 'op_old');
    await flow.setImage('/new.jpg');
    final draft = container.read(addProductFlowProvider);
    expect(draft.mediaId, isNull, reason: 'New photo must never publish the old media asset');
    expect(draft.imageEnhanceOpId, isNull);
  });

  test('changed pricing inputs receive a new operation key', () async {
    final flow = container.read(addProductFlowProvider.notifier);
    await flow.loadSavedDraftState(draftId: 'draft_probe', originalImagePath: '', enhancedImagePath: '', transcript: 'pot', descriptionEn: 'Terracotta pot', category: 'Pottery', rawMaterialCost: 100);
    await flow.calculatePriceSuggestion();
    flow.updateCostParameters(materialCost: 200);
    await flow.calculatePriceSuggestion();
    expect(pricing.costs, [100.0, 200.0]);
    expect(pricing.keys[1], isNot(pricing.keys[0]), reason: 'Changed payload with old key returns HTTP 409');
  });
}
