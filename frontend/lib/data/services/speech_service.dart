import 'dart:async';
import 'dart:math';

class TranscriptionResult {
  final String transcript;
  final double confidence; // 0.0–1.0

  const TranscriptionResult({required this.transcript, required this.confidence});
}

class AiListingSuggestion {
  final String titleEn;
  final String titleHi;
  final String descriptionEn;
  final String descriptionHi;
  final String category;
  final List<String> tags;

  const AiListingSuggestion({
    required this.titleEn,
    required this.titleHi,
    required this.descriptionEn,
    required this.descriptionHi,
    required this.category,
    required this.tags,
  });
}

abstract class SpeechService {
  Future<TranscriptionResult> transcribeAudio({
    required String audioPath,
    required String languageCode,
  });

  Future<AiListingSuggestion> generateListingFromTranscript({
    required String transcript,
    required String languageCode,
    String? categoryHint,
  });
}

class MockSpeechService implements SpeechService {
  final Random _random = Random();

  @override
  Future<TranscriptionResult> transcribeAudio({
    required String audioPath,
    required String languageCode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1200));

    final transcript = switch (languageCode) {
      'hi' => 'यह मिट्टी का हस्तनिर्मित सुराहीदार फूलदान है, जिसे प्राकृतिक लाल मिट्टी से चाक पर बनाया गया है। इस पर पारंपरिक मधुबनी शैली के पुष्प डिजाइन उकेरे गए हैं।',
      'ta' => 'இது பாரம்பரிய கைவினை மண் பானை, இயற்கை களிமண்ணால் சக்கரத்தில் செய்யப்பட்டது. பாரம்பரிய கைவினை வடிவமைப்புடன் அழகாக மெருகூட்டப்பட்டது.',
      'bn' => 'এটি ঐতিহ্যবাহী হাতে তৈরি মাটির ফুলদানি, প্রাকৃতিক পোড়ামাটির ওপর সুন্দর নকশা খোদাই করা হয়েছে।',
      _ => 'This is a handcrafted terracotta floral vase sculpted on a traditional potter\'s wheel using natural river clay, with etched folk motifs and organic earthen polish.',
    };

    // Simulate real-world STT confidence variance — occasionally low, so the
    // "try re-recording in a quiet place" hint actually gets exercised.
    // Replace with the real API's confidence field later.
    final confidence = 0.6 + _random.nextDouble() * 0.4; // 0.60–1.00

    return TranscriptionResult(transcript: transcript, confidence: confidence);
  }

  @override
  Future<AiListingSuggestion> generateListingFromTranscript({
    required String transcript,
    required String languageCode,
    String? categoryHint,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1300));

    final lower = transcript.toLowerCase();

    if (lower.contains('silk') || lower.contains('textile') || lower.contains('सिल्क') || lower.contains('दुपट्टा') || categoryHint == 'Textiles') {
      return const AiListingSuggestion(
        titleEn: 'Handwoven Pure Silk Cotton Dupatta with Traditional Zari Border',
        titleHi: 'पारंपरिक ज़री बॉर्डर के साथ हाथ से बुना शुद्ध सिल्क कॉटन दुपट्टा',
        descriptionEn: 'Exquisitely hand-spun and handwoven by master weavers. Made from premium breathable silk-cotton yarn with intricate golden zari patterns and natural organic vegetable dyes.',
        descriptionHi: 'कुशल बुनकरों द्वारा हाथ से काता और बुना गया उत्कृष्ट दुपट्टा। प्राकृतिक वनस्पति रंगों और सुनहरे ज़री के काम से सुसज्जित।',
        category: 'Textiles',
        tags: ['handloom', 'chanderi', 'silk', 'sustainable', 'traditional'],
      );
    } else if (lower.contains('wood') || lower.contains('लकड़ी') || categoryHint == 'Woodwork') {
      return const AiListingSuggestion(
        titleEn: 'Carved Sheesham Wood Elephant Figurine with Brass Inlay',
        titleHi: 'पीतल की नक्काशी के साथ शीशम की लकड़ी की हस्तनिर्मित हाथी की मूर्ति',
        descriptionEn: 'Intricately hand-carved decorative elephant crafted from seasoned Indian rosewood (Sheesham), detailed with fine hand-embedded floral brass inlays.',
        descriptionHi: 'अनुभवी शीशम की लकड़ी से तराशी गई सुंदर हाथी की सजावटी मूर्ति, जिसमें बारीक पीतल की नक्काशी का काम किया गया है।',
        category: 'Woodwork',
        tags: ['woodwork', 'sheesham', 'brass-inlay', 'handcarved', 'home-decor'],
      );
    } else {
      return const AiListingSuggestion(
        titleEn: 'Handcrafted Terracotta Ceramic Floral Vase with Folk Etchings',
        titleHi: 'लोक नक्काशीदार हस्तनिर्मित मिट्टी का सजावटी फूलदान',
        descriptionEn: 'Authentic handcrafted terracotta vase molded on a traditional potter wheel from pure riverbed clay. Features hand-etched folk patterns and wood-kiln fired for durability.',
        descriptionHi: 'पारंपरिक चाक पर शुद्ध नदी की मिट्टी से बना असली हस्तनिर्मित मिट्टी का फूलदान। लोक कला की नक्काशी और भट्टी में पकाया गया मजबूत ढांचा।',
        category: 'Pottery',
        tags: ['terracotta', 'pottery', 'folk-art', 'handcrafted', 'eco-friendly'],
      );
    }
  }
}