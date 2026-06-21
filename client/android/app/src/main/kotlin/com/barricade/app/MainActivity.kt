package com.barricade.app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// just_audio_background requires the host Activity to extend AudioServiceActivity
// (it provides the cached FlutterEngine that audio_service needs).
class MainActivity : AudioServiceActivity() {
    private val channelName = "barricade/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
