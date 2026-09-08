import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// The one and only [FlutterTts] instance in the app, plus whichever
/// [AppTtsService] handle is currently using it.
///
/// This exists because of a sharp edge in flutter_tts: its method channel is
/// `static const`, and *every* `FlutterTts()` constructor calls
/// `setMethodCallHandler` on it. Handlers are not additive — the newest
/// instance silently takes ownership of the callbacks for all of them. With a
/// read-aloud button on a dozen screens, each building its own instance, only
/// the most recently built one ever received `onComplete`; the rest set
/// `isSpeaking = true` when they started and never heard that speech had
/// finished. Their buttons stayed frozen on "Stop", and the next tap called
/// `stop()` on already-silent audio instead of reading the page again — the
/// button simply stopped working, with nothing in the logs to say so.
///
/// So the engine is created once here, its handlers are registered once, and
/// they dispatch to [owner] — the handle that actually started the current
/// utterance.
class _TtsEngine {
  static final _TtsEngine instance = _TtsEngine._();

  final FlutterTts tts = FlutterTts();

  /// The handle whose [AppTtsService.speak] started what is playing now.
  AppTtsService? owner;

  bool _configured = false;

  _TtsEngine._() {
    tts.setStartHandler(() => owner?._engineReportedSpeaking(true));
    tts.setCompletionHandler(() => owner?._engineReportedSpeaking(false));
    tts.setCancelHandler(() => owner?._engineReportedSpeaking(false));
    tts.setErrorHandler((msg) {
      debugPrint('[AppTts] error: $msg');
      owner?._engineReportedSpeaking(false);
    });
  }

  /// Applies the shared voice settings, once, and awaited before the first
  /// utterance — previously these were fired off un-awaited from a
  /// constructor, so a button tapped immediately after a screen opened could
  /// speak at the OS default rate before `setSpeechRate` had landed.
  Future<void> ensureConfigured() async {
    if (_configured) return;
    try {
      // Slower than the OS default — clearer for comprehension, matches the
      // rate already validated in the tutorial narration.
      await tts.setSpeechRate(0.48);
      await tts.setPitch(1.0);
      // 1.0 is the maximum flutter_tts accepts; there is no further headroom
      // in the API. Anything louder is the device's own media volume.
      await tts.setVolume(1.0);
      _configured = true;
    } catch (e) {
      debugPrint('[AppTts] configure failed: $e');
    }
  }
}

/// Shared text-to-speech engine for the whole app.
///
/// This is the voice pipeline's read-back engine, generalized so every
/// "tap to hear" affordance in the app — Photo Tips, packaging steps,
/// social captions, order summaries, notifications — speaks through the
/// same, fully-checked path instead of a dozen copies of ad hoc FlutterTts
/// calls.
///
/// Each widget constructs its own [AppTtsService]; they are cheap handles
/// onto the single shared [_TtsEngine], and only one of them can be speaking
/// at a time. Starting speech from one screen stops another's, which is the
/// behaviour you want — two voices talking over each other helps nobody.
///
/// Two things this does that a plain `FlutterTts().speak()` call does not:
///
/// 1. Checks [FlutterTts.isLanguageAvailable] before speaking. Without this, a
///    missing voice pack makes `speak()` return normally with no sound
///    produced — the user taps Listen, hears nothing, and has no idea why.
///    Callers get a [TtsResult.voiceUnavailable] instead of silence.
///
/// 2. On Android, offers a one-tap route to the OS voice-download screen
///    via [openVoiceDownloadScreen] instead of the user having to find
///    Settings > System > Languages > Text-to-speech > Install voice data.
class AppTtsService {
  /// Bridge to MainActivity.kt. Android only — iOS manages voices itself.
  static const MethodChannel _voiceDataChannel =
      MethodChannel('kalasetu/tts_voice_data');

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  /// Called whenever [isSpeaking] changes, so widgets can rebuild a
  /// speaker/stop icon without polling.
  VoidCallback? onStateChanged;

  /// Locale for each language TTS read-back supports right now: English and
  /// Hindi only. Any other app language falls back to English rather than
  /// failing — see [localeFor].
  static const Map<String, String> _locales = {
    'en': 'en-IN',
    'hi': 'hi-IN',
  };

  /// Locale FlutterTts will be asked to use for [languageCode].
  /// Falls back to English for anything not in the map.
  static String localeFor(String languageCode) =>
      _locales[languageCode] ?? _locales['en']!;

  void _engineReportedSpeaking(bool speaking) {
    _isSpeaking = speaking;
    if (!speaking && identical(_TtsEngine.instance.owner, this)) {
      _TtsEngine.instance.owner = null;
    }
    onStateChanged?.call();
  }

  /// Speaks [text] in [languageCode].
  ///
  /// Returns [TtsResult.spoke] on success, [TtsResult.voiceUnavailable] if
  /// the device has no voice data for that language (checked, not guessed),
  /// or [TtsResult.empty] if there was nothing to say.
  Future<TtsResult> speak(String text, {required String languageCode}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return TtsResult.empty;

    final engine = _TtsEngine.instance;
    await engine.ensureConfigured();

    // Silence whatever is playing first — this handle's own utterance, or
    // another screen's.
    final current = engine.owner;
    if (current != null) {
      await current.stop();
    }

    final locale = localeFor(languageCode);

    try {
      final available = await engine.tts.isLanguageAvailable(locale);
      if (available != true) {
        debugPrint('[AppTts] no voice data for $locale');
        return TtsResult.voiceUnavailable;
      }

      await engine.tts.setLanguage(locale);
      engine.owner = this;
      _isSpeaking = true;
      onStateChanged?.call();
      await engine.tts.speak(trimmed);
      return TtsResult.spoke;
    } catch (e) {
      debugPrint('[AppTts] speak error: $e');
      if (identical(engine.owner, this)) engine.owner = null;
      _isSpeaking = false;
      onStateChanged?.call();
      return TtsResult.error;
    }
  }

  Future<void> stop() async {
    final engine = _TtsEngine.instance;
    // Only silence the engine if this handle is the one using it; otherwise a
    // screen being disposed in the background would cut off the screen the
    // artisan is actually listening to.
    if (identical(engine.owner, this)) {
      try {
        await engine.tts.stop();
      } catch (e) {
        debugPrint('[AppTts] stop error: $e');
      } finally {
        engine.owner = null;
      }
    }
    _isSpeaking = false;
    onStateChanged?.call();
  }

  /// Opens Android's voice-data download screen. Returns false on iOS, and
  /// false (rather than throwing) if the device has no handler for the
  /// intent — callers should show a message rather than assume this works.
  Future<bool> openVoiceDownloadScreen() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _voiceDataChannel.invokeMethod<bool>(
            'openVoiceDataInstaller',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[AppTts] voice installer unavailable: ${e.message}');
      return false;
    }
  }

  void dispose() {
    // Clear the listener *before* stopping. stop() notifies, and widgets wire
    // that notification to setState — but State.mounted is still true while
    // dispose() is running, so their `if (mounted)` guard does not catch this
    // and Flutter asserts on markNeedsBuild for a defunct element.
    onStateChanged = null;
    stop();
  }
}

enum TtsResult { spoke, voiceUnavailable, empty, error }
