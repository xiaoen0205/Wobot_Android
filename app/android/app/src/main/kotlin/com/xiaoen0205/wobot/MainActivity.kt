package com.xiaoen0205.wobot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.SpeechRecognizer
import android.speech.RecognizerIntent
import android.speech.ModelDownloadListener
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    private var modelDownloader: SpeechRecognizer? = null
    private var downloadResult: MethodChannel.Result? = null
    private var downloadGeneration = 0
    private val downloadHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wobot/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isOnDeviceRecognitionAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                    )
                    "hasMicrophonePermission" -> result.success(
                        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                            PackageManager.PERMISSION_GRANTED
                    )
                    "downloadSpeechModel" -> downloadSpeechModel(call.argument<String>("localeId"), result)
                    "openAppSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("settings_unavailable", "Could not open app settings", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun finishDownload(status: String, generation: Int = downloadGeneration) {
        if (generation != downloadGeneration) return
        downloadGeneration++
        val result = downloadResult
        downloadResult = null
        downloadHandler.removeCallbacksAndMessages(null)
        modelDownloader?.destroy()
        modelDownloader = null
        result?.success(status)
    }

    private fun downloadSpeechModel(locale: String?, result: MethodChannel.Result) {
        if (downloadResult != null) {
            result.success("busy")
            return
        }
        if (locale !in listOf("zh-TW", "en-US") ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
            result.success("unavailable")
            return
        }
        downloadResult = result
        val generation = ++downloadGeneration
        try {
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            modelDownloader = recognizer
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            // A service may schedule the download rather than completing it now.
            downloadHandler.postDelayed({ finishDownload("requested", generation) }, 45000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                recognizer.triggerModelDownload(intent, mainExecutor, object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {}
                    override fun onSuccess() = finishDownload("downloaded", generation)
                    override fun onScheduled() = finishDownload("scheduled", generation)
                    override fun onError(error: Int) = finishDownload(
                        if (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED) "unsupported" else "failed",
                        generation
                    )
                })
            } else {
                recognizer.triggerModelDownload(intent)
            }
        } catch (e: Exception) {
            finishDownload("failed", generation)
        }
    }

    override fun onDestroy() {
        finishDownload("requested")
        super.onDestroy()
    }
}
