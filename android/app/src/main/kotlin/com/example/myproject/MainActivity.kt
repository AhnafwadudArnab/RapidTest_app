package com.example.myproject

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "rapid_test/downloads"
    private val storagePermissionRequestCode = 4242

    private data class PendingExport(
        val fileName: String,
        val mimeType: String,
        val bytes: ByteArray,
    )

    private var pendingExport: PendingExport? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFileToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                val bytes = call.argument<ByteArray>("bytes")

                if (fileName.isNullOrBlank() || bytes == null) {
                    result.error("invalid_arguments", "Missing export file data.", null)
                    return@setMethodCallHandler
                }

                if (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    pendingExport = PendingExport(fileName, mimeType, bytes)
                    pendingResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        storagePermissionRequestCode,
                    )
                    return@setMethodCallHandler
                }

                try {
                    result.success(saveFileToDownloads(fileName, mimeType, bytes))
                } catch (error: Exception) {
                    result.error("download_failed", error.message, null)
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != storagePermissionRequestCode) return

        val result = pendingResult ?: return
        val export = pendingExport

        pendingResult = null
        pendingExport = null

        if (export == null) {
            result.error("permission_error", "Missing pending export request.", null)
            return
        }

        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            try {
                result.success(saveFileToDownloads(export.fileName, export.mimeType, export.bytes))
            } catch (error: Exception) {
                result.error("download_failed", error.message, null)
            }
        } else {
            result.error(
                "permission_denied",
                "Storage permission is required to save exports to Downloads on this device.",
                null,
            )
        }
    }

    private fun saveFileToDownloads(fileName: String, mimeType: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create Downloads file.")

            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open Downloads file.")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri.toString()
        } else {
            val directory = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            )
            if (!directory.exists()) directory.mkdirs()

            val file = File(directory, fileName)
            FileOutputStream(file).use { it.write(bytes) }
            file.absolutePath
        }
    }
}
