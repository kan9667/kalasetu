package com.kalasetu.kalasetu

import android.content.Intent
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val ttsVoiceDataChannel = "kalasetu/tts_voice_data"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Bridges AppTtsService.openVoiceDownloadScreen() to Android's native
        // voice-data download screen. Flutter cannot reach this on its own —
        // without it, a missing voice pack means the user has to find
        // Settings > System > Languages > Text-to-speech > Install voice data
        // themselves, in whatever language the OS happens to be in.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ttsVoiceDataChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openVoiceDataInstaller" -> openVoiceDataInstaller(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openVoiceDataInstaller(result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                action = TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            if (intent.resolveActivity(packageManager) == null) {
                result.success(false)
                return
            }

            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
