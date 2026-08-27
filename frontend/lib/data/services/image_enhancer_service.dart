import 'dart:async';

abstract class ImageEnhancerService {
  Future<String> enhanceImage(String inputPathOrUrl);
  List<String> getSampleCraftImages();
}

class MockImageEnhancerService implements ImageEnhancerService {
  static const List<String> _sampleCrafts = [
    'https://images.unsplash.com/photo-1578749556568-bc2c40e68b61?auto=format&fit=crop&w=800&q=80', // Clay pottery
    'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80', // Handloom textile
    'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=800&q=80', // Wooden craft
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=800&q=80', // Brass / jewelry
    'https://images.unsplash.com/photo-1565193566173-7a0ee3dbe261?auto=format&fit=crop&w=800&q=80', // Blue pottery vase
  ];

  @override
  Future<String> enhanceImage(String inputPathOrUrl) async {
    // Simulate AI background removal + lighting correction pipeline latency
    await Future.delayed(const Duration(milliseconds: 1400));
    
    // If input is empty or invalid, return a default sample
    if (inputPathOrUrl.isEmpty) {
      return _sampleCrafts[0];
    }
    
    // In mock mode, return the input path/url with an enhanced studio indicator
    return inputPathOrUrl;
  }

  @override
  List<String> getSampleCraftImages() {
    return List.unmodifiable(_sampleCrafts);
  }
}
