package com.barricade.app

import android.content.ContentValues
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.content.Intent
import android.os.Bundle

// just_audio_background requires the host Activity to extend AudioServiceActivity
// (it provides the cached FlutterEngine that audio_service needs).
class MainActivity : AudioServiceActivity() {
    private val downloadsChannel = "barricade/downloads"
    private val callChannel = "barricade/call"
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name") ?: "file"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    if (path == null) {
                        result.error("ARG", "path is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        saveToDownloads(path, name, mime)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message ?: e.toString(), null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCallService" -> {
                        CallForegroundService.startCall(this)
                        result.success(true)
                    }
                    "stopCallService" -> {
                        CallForegroundService.stop(this)
                        result.success(true)
                    }
                    "showIncomingCall" -> {
                        val name = call.argument<String>("callerName") ?: ""
                        val id = call.argument<String>("callerId") ?: ""
                        val chId = call.argument<String>("channelId") ?: ""
                        CallForegroundService.showIncomingCallNotification(this, name, id, chId)
                        result.success(true)
                    }
                    "cancelIncomingNotification" -> {
                        CallForegroundService.cancelIncomingNotification(this)
                        result.success(true)
                    }
                    "getLaunchData" -> {
                        val intent = intent
                        val showCall = intent.getBooleanExtra("show_incoming_call", false)
                        result.success(mapOf(
                            "show_incoming_call" to showCall,
                            "caller_name" to (intent.getStringExtra("caller_name") ?: ""),
                            "caller_id" to (intent.getStringExtra("caller_id") ?: ""),
                            "channel_id" to (intent.getStringExtra("channel_id") ?: ""),
                        ))
                    }
                    "playRingtone" -> {
                        try {
                            ringtone?.stop()
                            val uri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            ringtone = RingtoneManager.getRingtone(this, uri)
                            ringtone?.play()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("RINGTONE", e.message ?: e.toString(), null)
                        }
                    }
                    "stopRingtone" -> {
                        ringtone?.stop()
                        ringtone = null
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // If launched from notification with incoming call data,
        // it's already handled by Flutter state via the OverlayEntry
    }

    // Saves a file into the public Downloads/Barricade folder via MediaStore
    // (scoped-storage safe on Android 10+; direct write on older versions).
    private fun saveToDownloads(srcPath: String, displayName: String, mime: String) {
        val src = File(srcPath)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Barricade")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore insert returned null")
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IllegalStateException("openOutputStream null")
                src.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Barricade")
            if (!dir.exists()) dir.mkdirs()
            src.copyTo(File(dir, displayName), overwrite = true)
        }
    }
}
