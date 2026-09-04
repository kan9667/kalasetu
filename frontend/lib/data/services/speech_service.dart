import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/api_config.dart';

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

/// Real HTTP speech service connecting directly to FastAPI `/api/v1/voice/transcribe`
/// which runs the ML Whisper STT pipeline with domain craft glossary biasing.
class HttpSpeechService implements SpeechService {
  HttpSpeechService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'Accept': 'application/json'},
              ),
            );

  final Dio _dio;

  /// Check if the returned transcript matches known Whisper silence artifacts / hallucinations
  static bool isSilenceHallucination(String text) {
    if (text.trim().isEmpty) return true;
    final clean = text
        .replaceAll(RegExp(r"""[\s\.,!?:;\-_"'()\[\]{}।…~*]+"""), ' ')
        .trim()
        .toLowerCase();

    const silenceArtifacts = {
      'thanks',
      'thank you',
      'thanks for watching',
      'thank you for watching',
      'thanks for listening',
      'thank you for listening',
      'thank you very much',
      'thank you so much',
      'please subscribe',
      'subscribe',
      'subtitles',
      'subtitles by',
      'bye',
      'bye bye',
      'you',
      'goodbye',
      'peace',
      'watching',
      'so',
      'the end',
      'see you next time',
      'thanks guys',
      'thank you all',
      'धन्यवाद',
      'बहुत धन्यवाद',
      'शुक्रिया',
      'बहुत शुक्रिया',
      'प्रस्तुत',
      'प्रश्नित',
      'प्रश्नित प्रश्नित',
      'झाल',
      'सब्सक्राइब करें',
      'लाइक करें',
      'शेयर करें',
      'चैनल को सब्सक्राइब करें',
    };

    if (silenceArtifacts.contains(clean)) return true;

    final words = clean.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length <= 6) {
      if ((clean.contains('thank') || clean.contains('thanks')) && clean.contains('watching')) {
        return true;
      }
      for (final prefix in [
        'thanks',
        'thank you',
        'bye',
        'goodbye',
        'subtitles',
        'subscribe',
        'धन्यवाद',
        'शुक्रिया',
      ]) {
        if (clean.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  @override
  Future<TranscriptionResult> transcribeAudio({
    required String audioPath,
    required String languageCode,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      debugPrint('[HttpSpeechService] Audio file does not exist: $audioPath');
      return const TranscriptionResult(transcript: '', confidence: 0.0);
    }

    try {
      final activeUrl = ApiConfig.baseUrl;
      _dio.options.baseUrl = activeUrl;

      final fileName = audioPath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioPath,
          filename: fileName.isNotEmpty ? fileName : 'recording.m4a',
        ),
        'language_code': languageCode.isNotEmpty ? languageCode : 'hi',
      });

      debugPrint('[HttpSpeechService] POST $activeUrl/api/v1/voice/transcribe (lang: $languageCode)');
      final response = await _dio.post(
        '/api/v1/voice/transcribe',
        data: formData,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final transcript = (data['transcript'] as String? ?? '').trim();
        debugPrint('[HttpSpeechService] Whisper transcription received: "$transcript"');

        if (isSilenceHallucination(transcript)) {
          debugPrint('[HttpSpeechService] Filtered silence hallucination: "$transcript"');
          return const TranscriptionResult(transcript: '', confidence: 0.0);
        }

        return TranscriptionResult(
          transcript: transcript,
          confidence: transcript.isNotEmpty ? 0.95 : 0.0,
        );
      }
    } catch (e) {
      debugPrint('[HttpSpeechService] Error during voice transcription: $e');
    }

    return const TranscriptionResult(transcript: '', confidence: 0.0);
  }

  @override
  Future<AiListingSuggestion> generateListingFromTranscript({
    required String transcript,
    required String languageCode,
    String? categoryHint,
  }) async {
    final cleanTranscript = transcript.trim();
    return AiListingSuggestion(
      titleEn: cleanTranscript.isNotEmpty ? cleanTranscript : 'Handcrafted Artisan Product',
      titleHi: cleanTranscript.isNotEmpty ? cleanTranscript : 'हस्तनिर्मित उत्पाद',
      descriptionEn: cleanTranscript,
      descriptionHi: cleanTranscript,
      category: categoryHint ?? 'Handicrafts',
      tags: ['handcrafted', 'artisan', 'kalasetu'],
    );
  }
}