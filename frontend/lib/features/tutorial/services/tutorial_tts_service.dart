import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TutorialTtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;
  VoidCallback? onStateChanged;

  bool get isPlaying => _isPlaying;

  TutorialTtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setSpeechRate(0.48); // Slightly slower for clear comprehension
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      _tts.setStartHandler(() {
        _isPlaying = true;
        onStateChanged?.call();
      });

      _tts.setCompletionHandler(() {
        _isPlaying = false;
        onStateChanged?.call();
      });

      _tts.setCancelHandler(() {
        _isPlaying = false;
        onStateChanged?.call();
      });

      _tts.setErrorHandler((msg) {
        debugPrint('[TutorialTTS] Error: $msg');
        _isPlaying = false;
        onStateChanged?.call();
      });
    } catch (e) {
      debugPrint('[TutorialTTS] Initialization failed: $e');
    }
  }

  Future<void> speak(String text, {String languageCode = 'en'}) async {
    try {
      if (_isPlaying) {
        await stop();
      }

      String ttsLang = 'en-IN';
      switch (languageCode) {
        case 'hi':
          ttsLang = 'hi-IN';
          break;
        case 'bn':
          ttsLang = 'bn-IN';
          break;
        case 'ta':
          ttsLang = 'ta-IN';
          break;
        default:
          ttsLang = 'en-IN';
      }

      await _tts.setLanguage(ttsLang);
      _isPlaying = true;
      onStateChanged?.call();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TutorialTTS] Speak error: $e');
      _isPlaying = false;
      onStateChanged?.call();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('[TutorialTTS] Stop error: $e');
    } finally {
      _isPlaying = false;
      onStateChanged?.call();
    }
  }

  void dispose() {
    stop();
    onStateChanged = null;
  }
}
