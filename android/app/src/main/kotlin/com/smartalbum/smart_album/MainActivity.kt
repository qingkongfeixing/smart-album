package com.smartalbum.smart_album

import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.smartalbum/mediastore"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "queryImages") {
                    try {
                        val since = call.argument<Long>("since") ?: 0L
                        val folder = call.argument<String>("folder")
                        val images = queryImages(since, folder)
                        result.success(images)
                    } catch (e: Exception) {
                        result.error("QUERY_ERROR", e.message, null)
                    }
                } else if (call.method == "queryFolders") {
                    try {
                        val folders = queryFolders()
                        result.success(folders)
                    } catch (e: Exception) {
                        result.error("QUERY_ERROR", e.message, null)
                    }
                } else if (call.method == "openFolder") {
                    try {
                        val folderPath = call.argument<String>("path") ?: ""
                        openFolder(folderPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                } else if (call.method == "scanFile") {
                    try {
                        val path = call.argument<String>("path") ?: ""
                        val uri = scanFile(path)
                        result.success(uri)
                    } catch (e: Exception) {
                        result.error("SCAN_ERROR", e.message, null)
                    }
                } else if (call.method == "removeFromMediaStore") {
                    try {
                        val path = call.argument<String>("path") ?: ""
                        removeFromMediaStore(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REMOVE_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    data class ImageInfo(
        val path: String,
        val timestamp: Long,
        val width: Int,
        val height: Int,
        val size: Long,
        val folder: String,
        val contentUri: String
    )

    private fun queryImages(since: Long, folder: String?): String {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME
        )

        val conditions = mutableListOf<String>()
        val args = mutableListOf<String>()

        if (since > 0) {
            conditions.add("${MediaStore.Images.Media.DATE_MODIFIED} > ?")
            args.add((since / 1000).toString())
        }
        if (!folder.isNullOrEmpty()) {
            conditions.add("${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} = ?")
            args.add(folder)
        }

        val selection = if (conditions.isNotEmpty()) conditions.joinToString(" AND ") else null
        val selectionArgs = if (args.isNotEmpty()) args.toTypedArray() else null

        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val sortOrder = "${MediaStore.Images.Media.DATE_MODIFIED} DESC"

        val json = JSONArray()
        contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val dataCol = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val widthCol = cursor.getColumnIndex(MediaStore.Images.Media.WIDTH)
            val heightCol = cursor.getColumnIndex(MediaStore.Images.Media.HEIGHT)
            val sizeCol = cursor.getColumnIndex(MediaStore.Images.Media.SIZE)
            val bucketCol = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val path = cursor.getString(dataCol)
                val dateMod = cursor.getLong(dateCol) * 1000L // to millis
                val width = if (widthCol >= 0) cursor.getInt(widthCol) else 0
                val height = if (heightCol >= 0) cursor.getInt(heightCol) else 0
                val size = if (sizeCol >= 0) cursor.getLong(sizeCol) else 0L
                val bucket = if (bucketCol >= 0) cursor.getString(bucketCol) ?: "其他" else "其他"

                val obj = JSONObject()
                val contentUri = ContentUris.withAppendedId(uri, id).toString()
                // 优先用 DATA 路径，空则用 content URI
                obj.put("path", path ?: contentUri)
                obj.put("id", contentUri)
                obj.put("timestamp", dateMod)
                obj.put("width", width)
                obj.put("height", height)
                obj.put("size", size)
                obj.put("folder", bucket)
                json.put(obj)
            }
        }
        return json.toString()
    }

    private fun openFolder(folderPath: String) {
        val file = File(folderPath)
        if (!file.exists() || !file.isDirectory) return
        try {
            val storageDir = Environment.getExternalStorageDirectory().absolutePath
            if (!folderPath.startsWith(storageDir)) return
            val relativePath = folderPath.removePrefix(storageDir).trimStart('/')
            val docId = "primary:$relativePath"
            val uri = DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents", docId)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun queryFolders(): String {
        val projection = arrayOf(
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            "count(*)"
        )
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val json = JSONArray()
        contentResolver.query(
            uri, projection,
            null, null,
            "${MediaStore.Images.Media.BUCKET_DISPLAY_NAME}"
        )?.use { cursor ->
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val countCol = cursor.getColumnIndexOrThrow("count(*)")
            while (cursor.moveToNext()) {
                val obj = JSONObject()
                obj.put("name", cursor.getString(nameCol) ?: "其他")
                obj.put("count", cursor.getInt(countCol))
                json.put(obj)
            }
        }
        return json.toString()
    }

    private fun scanFile(filePath: String): String? {
        val file = File(filePath)
        if (!file.exists()) return null

        val values = android.content.ContentValues().apply {
            put(MediaStore.Images.Media.DATA, filePath)
            put(MediaStore.Images.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Images.Media.DATE_MODIFIED, file.lastModified() / 1000)
            put(MediaStore.Images.Media.SIZE, file.length())
        }

        val uri = contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        return uri?.toString()
    }

    private fun removeFromMediaStore(filePath: String) {
        val selection = "${MediaStore.Images.Media.DATA} = ?"
        val args = arrayOf(filePath)
        contentResolver.delete(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI, selection, args)
    }
}
