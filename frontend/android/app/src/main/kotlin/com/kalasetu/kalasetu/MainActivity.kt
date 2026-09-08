package com.kalasetu.kalasetu
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.tts.TextToSpeech
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.kalasetu.kalasetu/whatsapp_share"
    private val ttsVoiceDataChannel = "kalasetu/tts_voice_data"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 1. WhatsApp Share Channel (From your PR)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "shareToWhatsApp") {
                val imagePath = call.argument<String>("imagePath")
                val text = call.argument<String>("text") ?: ""

                try {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/*"
                        putExtra(Intent.EXTRA_TEXT, text)
                        setPackage("com.whatsapp")
                        if (!imagePath.isNullOrEmpty()) {
                            val file = File(imagePath)
                            if (file.exists()) {
                                val contentUri = FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.fileprovider",
                                    file
                                )
                                putExtra(Intent.EXTRA_STREAM, contentUri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                        }
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                } catch (e: Exception) {
                    result.error("SHARE_ERROR", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // 2. TTS Voice Data Installer Channel (From main)
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