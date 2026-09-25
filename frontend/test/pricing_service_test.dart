import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:kalasetu/core/network/session_expired_exception.dart';
import 'package:kalasetu/data/services/pricing_service.dart';

void main() {
  group('PriceSuggestion & ComparableProduct Models', () {
    test('deserializes complete backend PriceSuggestResponse JSON', () {
      final json = {
        'suggested_price': 850.0,
        'min_price': 700.0,
        'max_price': 1100.0,
        'floor_price': 520.0,
        'confidence_score': 0.88,
        'market_position': 'premium',
        'reasoning': 'Based on handloom weaving complexity and market rates.',
        'reasoning_hi': 'हथकरघा बुनाई की जटिलता और बाज़ार दरों पर आधारित।',
        'comparable_products': [
          {
            'id': 'comp_1',
            'title': 'Khurja Blue Pottery Floral Vase',
            'selling_price': 799.0,
            'category': 'pottery',
            'source_platform': 'Amazon Karigar',
            'similarity_score': 0.89,
            'product_url': 'https://amazon.in/dp/test',
          },
          {
            'id': 'comp_2',
            'title': 'Terracotta Warli Table Lamp',
            'selling_price': 890.0,
            'category': 'pottery',
            'source_platform': 'CraftsVilla',
            'similarity_score': 0.83,
          }
        ]
      };

      final suggestion = PriceSuggestion.fromJson(json);

      expect(suggestion.suggestedPrice, equals(850.0));
      expect(suggestion.minPrice, equals(700.0));
      expect(suggestion.maxPrice, equals(1100.0));
      expect(suggestion.floorPrice, equals(520.0));
      expect(suggestion.confidenceScore, equals(0.88));
      expect(suggestion.marketPosition, equals('premium'));
      expect(suggestion.reasoning, contains('handloom weaving'));
      expect(suggestion.reasoningHi, contains('हथकरघा'));
      expect(suggestion.comparableProducts.length, equals(2));

      final comp1 = suggestion.comparableProducts.first;
      expect(comp1.id, equals('comp_1'));
      expect(comp1.title, equals('Khurja Blue Pottery Floral Vase'));
      expect(comp1.sellingPrice, equals(799.0));
      expect(comp1.sourcePlatform, equals('Amazon Karigar'));
      expect(comp1.similarityScore, equals(0.89));
      expect(comp1.productUrl, equals('https://amazon.in/dp/test'));
    });

    test('gracefully handles missing optional fields in JSON', () {
      final json = {
        'suggested_price': 600,
        'min_price': 500,
        'max_price': 800,
        'floor_price': 400,
        'reasoning': 'Basic pricing',
        'reasoning_hi': 'सामान्य मूल्य',
      };

      final suggestion = PriceSuggestion.fromJson(json);

      expect(suggestion.suggestedPrice, equals(600.0));
      expect(suggestion.confidenceScore, equals(0.85)); // default
      expect(suggestion.marketPosition, equals('mid-range')); // default
      expect(suggestion.comparableProducts, isEmpty);
    });
  });

  group('HttpPricingService', () {
    test('falls back to MockPricingService on Dio network error', () async {
      // Create a Dio instance configured to hit an unreachable endpoint immediately
      final failingDio = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 100),
          receiveTimeout: const Duration(milliseconds: 100),
        ),
      );

      final service = HttpPricingService(
        baseUrl: 'http://127.0.0.1:59999', // Port unlikely to be open
        dio: failingDio,
      );

      final suggestion = await service.suggestPrice(
        description: 'Handmade pottery clay bowl',
        category: 'pottery',
        tags: ['clay', 'pottery'],
        rawMaterialCost: 150.0,
        laborHours: 3.0,
        hourlyWage: 100.0,
      );

      // Verify that the fallback kicked in and calculated an ethical floor price
      expect(suggestion.floorPrice, equals(450.0)); // 150 + 3*100
      expect(suggestion.suggestedPrice, greaterThanOrEqualTo(suggestion.floorPrice));
      expect(suggestion.reasoning, isNotEmpty);
      expect(suggestion.reasoningHi, isNotEmpty);
    });

    test('sends stable Idempotency-Key header on pricing request', () async {
      String? capturedKey;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedKey = options.headers['Idempotency-Key'] as String?;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'suggested_price': 500.0,
                  'min_price': 400.0,
                  'max_price': 600.0,
                  'floor_price': 300.0,
                  'confidence_score': 0.9,
                  'market_position': 'mid-range',
                  'reasoning': 'test',
                  'reasoning_hi': 'परीक्षण',
                },
              ),
            );
          },
        ),
      );

      final service = HttpPricingService(
        baseUrl: 'http://127.0.0.1:8000',
        dio: dio,
      );

      final suggestion = await service.suggestPrice(
        category: 'textiles',
        tags: ['cotton'],
        rawMaterialCost: 100,
        laborHours: 2,
        hourlyWage: 100,
      );

      expect(suggestion.suggestedPrice, equals(500.0));
      expect(capturedKey, isNotNull);
      expect(capturedKey, startsWith('idem_price_'));
    });

    test('HTTP 401/403 maps to SessionExpiredException and NEVER falls back to mock', () async {
      for (final statusCode in [401, 403]) {
        final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: statusCode,
                    data: {'detail': 'Invalid token'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final service = HttpPricingService(
          baseUrl: 'http://127.0.0.1:8000',
          dio: dio,
        );

        expect(
          () => service.suggestPrice(
            category: 'pottery',
            tags: ['clay'],
            rawMaterialCost: 100,
            laborHours: 2,
            hourlyWage: 100,
          ),
          throwsA(isA<SessionExpiredException>()),
          reason: 'HTTP $statusCode must throw SessionExpiredException without falling back to mock',
        );
      }
    });
  });
}
