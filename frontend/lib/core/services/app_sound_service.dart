import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

/// Centralized service managing tactile click audio and haptic feedback.
///
/// Preloads a single [AudioPlayer] instance on startup for zero-latency
/// tactile responses when buttons or navigation items are tapped.
class AppSoundService {
  AppSoundService._();
  static final AppSoundService instance = AppSoundService._();

  static const String assetPath = 'assets/sounds/tap_click.wav';
  static const String _settingsBox = 'app_settings_box';
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyHapticsEnabled = 'haptics_enabled';
  static const String _keyVolume = 'sound_volume';

  AudioPlayer? _player;
  bool _isSoundEnabled = true;
  bool _isHapticsEnabled = true;
  double _volume = 0.35;
  bool _isInitialized = false;

  bool get isSoundEnabled => _isSoundEnabled;
  bool get isHapticsEnabled => _isHapticsEnabled;
  double get volume => _volume;
  bool get isInitialized => _isInitialized;

  /// Preloads audio player instance and restores user settings.
  Future<void> init({AudioPlayer? customPlayer}) async {
    try {
      if (Hive.isBoxOpen(_settingsBox)) {
        final box = Hive.box(_settingsBox);
        _isSoundEnabled = box.get(_keySoundEnabled, defaultValue: true) as bool;
        _isHapticsEnabled = box.get(_keyHapticsEnabled, defaultValue: true) as bool;
        _volume = (box.get(_keyVolume, defaultValue: 0.35) as num).toDouble();
      }

      _player = customPlayer ?? AudioPlayer();
      await _player!.setAsset(assetPath);
      await _player!.setVolume(_volume);
      _isInitialized = true;
    } catch (e) {
      debugPrint('[AppSoundService] Audio init note: $e');
      // Set initialized true so app continues smoothly even if audio device is unavailable
      _isInitialized = true;
    }
  }

  /// Plays a subtle tactile click sound and triggers light haptic impact.
  ///
  /// Executed asynchronously without blocking button tap callbacks.
  void playTapSound({bool forceSound = false}) {
    // 1. Immediate zero-latency haptic response
    if (_isHapticsEnabled) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }

    // 2. Low-volume click sound
    if ((_isSoundEnabled || forceSound) && _player != null) {
      _triggerAudioAsync();
    }
  }

  void _triggerAudioAsync() {
    unawaited(() async {
      try {
        final player = _player;
        if (player == null) return;
        if (player.playing) {
          await player.stop();
        }
        await player.seek(Duration.zero);
        await player.play();
      } catch (e) {
        // Silently capture any playback glitch so button action is never impacted
      }
    }());
  }

  /// Globally toggle sound feedback on or off.
  Future<void> setSoundEnabled(bool enabled) async {
    _isSoundEnabled = enabled;
    if (Hive.isBoxOpen(_settingsBox)) {
      await Hive.box(_settingsBox).put(_keySoundEnabled, enabled);
    }
  }

  /// Globally toggle haptic feedback on or off.
  Future<void> setHapticsEnabled(bool enabled) async {
    _isHapticsEnabled = enabled;
    if (Hive.isBoxOpen(_settingsBox)) {
      await Hive.box(_settingsBox).put(_keyHapticsEnabled, enabled);
    }
  }

  /// Adjust tactile click volume (default: 0.35, recommended 0.2–0.5).
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_player != null) {
      await _player!.setVolume(_volume);
    }
    if (Hive.isBoxOpen(_settingsBox)) {
      await Hive.box(_settingsBox).put(_keyVolume, _volume);
    }
  }

  /// Dispose player resources.
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _isInitialized = false;
  }
}

/// Riverpod provider for [AppSoundService].
final appSoundServiceProvider = Provider<AppSoundService>((ref) {
  return AppSoundService.instance;
});

/// Convenience helper to wrap any existing tap callback with tactile feedback.
class AppSoundFeedback {
  /// Wraps [onPressed] to play a tactile sound and light haptic tap before calling the action.
  static VoidCallback? wrap(VoidCallback? onPressed) {
    if (onPressed == null) return null;
    return () {
      AppSoundService.instance.playTapSound();
      onPressed();
    };
  }

  /// Wraps a single-parameter callback (e.g. `onChanged`, `onTabTap`) with tactile feedback.
  static ValueChanged<T>? wrapValueChanged<T>(ValueChanged<T>? callback) {
    if (callback == null) return null;
    return (value) {
      AppSoundService.instance.playTapSound();
      callback(value);
    };
  }
}
