import 'dart:async';

class PriceSuggestion {
  final double minPrice;
  final double maxPrice;
  final double suggestedPrice;
  final double floorPrice;
  final String reasoning;
  final String reasoningHi;

  const PriceSuggestion({
    required this.minPrice,
    required this.maxPrice,
    required this.suggestedPrice,
    required this.floorPrice,
    required this.reasoning,
    required this.reasoningHi,
  });
}

abstract class PricingService {
  Future<PriceSuggestion> suggestPrice({
    required String category,
    required List<String> tags,
    double? rawMaterialCost,
    double? laborHours,
    double? hourlyWage,
  });
}

class MockPricingService implements PricingService {
  @override
  Future<PriceSuggestion> suggestPrice({
    required String category,
    required List<String> tags,
    double? rawMaterialCost,
    double? laborHours,
    double? hourlyWage,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final matCost = rawMaterialCost ?? 180.0;
    final hours = laborHours ?? 3.5;
    final rate = hourlyWage ?? 120.0;

    // Strict ethical floor: Artisan raw material + fair labor cost guarantee
    final calculatedFloor = matCost + (hours * rate);

    double baseSuggested;
    double baseMin;
    double baseMax;
    String reasonEn;
    String reasonHi;

    switch (category.toLowerCase()) {
      case 'textiles':
        baseMin = 1400.0;
        baseMax = 2400.0;
        baseSuggested = 1850.0;
        reasonEn = 'Based on handloom weaving complexity (3.5 hrs), silk-cotton blend fabric market rates, and current festive demand.';
        reasonHi = 'हथकरघा बुनाई की जटिलता, सिल्क-कॉटन फैब्रिक की बाज़ार दर और वर्तमान मांग के आधार पर विश्लेषित।';
        break;
      case 'woodwork':
        baseMin = 950.0;
        baseMax = 1600.0;
        baseSuggested = 1250.0;
        reasonEn = 'Based on seasoned Sheesham hardwood material, detailed brass inlay craftsmanship, and e-commerce decor benchmarks.';
        reasonHi = 'शीशम की लकड़ी की लागत, पीतल की नक्काशी और हस्तकला ई-कॉमर्स बाज़ार के आंकड़ों के अनुसार।';
        break;
      case 'jewelry':
        baseMin = 650.0;
        baseMax = 1200.0;
        baseSuggested = 890.0;
        reasonEn = 'Calculated from brass/terracotta casting, intricate hand-finishing, and artisan jewelry trends.';
        reasonHi = 'धातु/मिट्टी की ढलाई, बारीक पॉलिश और पारंपरिक आभूषण बाज़ार की दरों के अनुसार।';
        break;
      case 'paintings':
        baseMin = 1200.0;
        baseMax = 2800.0;
        baseSuggested = 1950.0;
        reasonEn = 'Evaluated using organic pigment quality, canvas size, and traditional folk art auction benchmarks.';
        reasonHi = 'प्राकृतिक रंगों की गुणवत्ता, कैनवास का आकार और पारंपरिक लोक चित्रकला के बाज़ार मूल्य पर आधारित।';
        break;
      case 'pottery':
      default:
        baseMin = 550.0;
        baseMax = 950.0;
        baseSuggested = 750.0;
        reasonEn = 'Evaluated based on pure river clay sourcing, wheel sculpting time, wood-kiln firing fuel costs, and sustainable home decor trends.';
        reasonHi = 'प्राकृतिक नदी की मिट्टी, चाक पर गढ़ने का समय, भट्टी ईंधन लागत और पर्यावरण-अनुकूल घरेलू सजावट की बाज़ार मांग के अनुसार।';
        break;
    }

    // Floor price safeguard: minimum price and suggested price can never drop below calculatedFloor
    final finalFloor = calculatedFloor > 0 ? calculatedFloor : 300.0;
    final minPrice = baseMin < finalFloor ? finalFloor : baseMin;
    final maxPrice = baseMax < (finalFloor * 1.3) ? (finalFloor * 1.6) : baseMax;
    final suggested = baseSuggested < minPrice ? minPrice : (baseSuggested > maxPrice ? maxPrice : baseSuggested);

    return PriceSuggestion(
      minPrice: double.parse(minPrice.toStringAsFixed(0)),
      maxPrice: double.parse(maxPrice.toStringAsFixed(0)),
      suggestedPrice: double.parse(suggested.toStringAsFixed(0)),
      floorPrice: double.parse(finalFloor.toStringAsFixed(0)),
      reasoning: reasonEn,
      reasoningHi: reasonHi,
    );
  }
}
