package com.togetherly.love

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Запись в галерею с датой и местом воспоминания — канал `love_app/gallery`.
 *
 * Togetherly при загрузке срезает у снимков дату съёмки, и файл, сохранённый
 * пакетом gal, встаёт в галерее на день сохранения: 94 летних кадра оказались
 * бы «сегодня». Здесь дата ставится дважды — строкой `datetaken` в MediaStore
 * (по ней сортирует галерея этого телефона) и тегами EXIF в самом снимке
 * (они переезжают вместе с файлом на новый телефон и в облако).
 *
 * Всё ложится в одну папку: фото и видео — `Pictures/Togetherly`, одна плитка
 * в галерее (просьба заказчика 19.09.2026). Звук галерея не показывает — он
 * уходит в `Download/Togetherly`.
 */
class GallerySaver(private val context: Context) : MethodChannel.MethodCallHandler {

    private val io = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save" -> io.execute {
                try {
                    val uri = save(call)
                    main.post { result.success(uri) }
                } catch (e: SecurityException) {
                    main.post { result.error(ACCESS_DENIED, e.message, null) }
                } catch (e: Exception) {
                    Log.w(TAG, "save failed", e)
                    val code = if (e.toString().contains("No space left")) "NO_SPACE" else "SAVE_FAILED"
                    main.post { result.error(code, e.toString(), null) }
                }
            }
            "open" -> {
                open(call.argument<String>("uri"))
                result.success(null)
            }
            // С Android 10 свои файлы кладутся в MediaStore без разрешений.
            // Спрашивать через gal там нельзя: он просит WRITE_EXTERNAL_STORAGE,
            // а в манифесте оно объявлено только до Android 9 — система
            // отказала бы сразу, и сохранение не работало бы вовсе.
            // Фоновая запись (MediaSaveService): Dart отдаёт файлы и забирает
            // готовое, служба работает и без него.
            "engineSubmit" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("BAD_ARGS", "нет аргументов", null)
                } else {
                    MediaSaveEngine.submit(context, args)
                    result.success(null)
                }
            }
            "engineStatus" -> result.success(MediaSaveEngine.status(context))
            "engineAck" -> {
                MediaSaveEngine.ack(context, call.argument<List<String>>("keys") ?: emptyList())
                result.success(null)
            }
            "engineCancel" -> {
                MediaSaveEngine.cancel(context, call.argument<List<String>>("keys") ?: emptyList())
                result.success(null)
            }
            "hasAccess" -> result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                    ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ) == PackageManager.PERMISSION_GRANTED
            )
            else -> result.notImplemented()
        }
    }

    /** Что нужно галерее о файле: откуда взять и на какой день положить. */
    data class Params(
        val path: String,
        val kind: String,
        val takenAt: Long,
        val offsetMinutes: Int,
        val latitude: Double?,
        val longitude: Double?,
        val name: String,
        val album: String,
    )

    private fun save(call: MethodCall): String {
        val path = call.argument<String>("path") ?: throw IllegalArgumentException("path")
        return writeFile(
            Params(
                path = path,
                kind = call.argument<String>("kind") ?: KIND_PHOTO,
                takenAt = (call.argument<Number>("takenAt") ?: System.currentTimeMillis()).toLong(),
                offsetMinutes = (call.argument<Number>("offsetMinutes") ?: 0).toInt(),
                latitude = call.argument<Number>("latitude")?.toDouble(),
                longitude = call.argument<Number>("longitude")?.toDouble(),
                name = call.argument<String>("name") ?: File(path).name,
                album = call.argument<String>("album") ?: DEFAULT_ALBUM,
            )
        )
    }

    /**
     * Положить файл в галерею. Зовут и канал (сохранение на глазах), и
     * фоновая служба [MediaSaveService] — она работает без Dart.
     */
    fun writeFile(p: Params): String {
        val src = File(p.path)
        if (!src.exists()) throw FileNotFoundException(p.path)
        val kind = p.kind
        val name = p.name
        val album = p.album
        val takenAt = p.takenAt
        val offsetMinutes = p.offsetMinutes
        val latitude = p.latitude
        val longitude = p.longitude

        // EXIF пишется в копию: исходник бывает файлом кэша картинок ленты, и
        // трогать его нельзя.
        var body = src
        var temp: File? = null
        if (kind == KIND_PHOTO && exifWritable(name)) {
            temp = File(context.cacheDir, "gallery_${System.nanoTime()}_$name")
            src.copyTo(temp, overwrite = true)
            try {
                writeExif(temp, takenAt, offsetMinutes, latitude, longitude)
            } catch (e: Exception) {
                // Без EXIF снимок всё равно встанет на нужный день по datetaken.
                Log.w(TAG, "exif failed for $name", e)
            }
            body = temp
        }
        try {
            return insert(body, kind, name, album, takenAt)
        } finally {
            temp?.delete()
        }
    }

    /** EXIF умеет писать в JPEG, PNG и WebP. HEIC — только читать. */
    private fun exifWritable(name: String): Boolean =
        name.substringAfterLast('.', "").lowercase(Locale.ROOT) in setOf("jpg", "jpeg", "png", "webp")

    private fun writeExif(file: File, takenAt: Long, offsetMinutes: Int, lat: Double?, lng: Double?) {
        val exif = ExifInterface(file.absolutePath)
        // В EXIF дата — местное время съёмки, пояс лежит рядом отдельным тегом.
        val fmt = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val stamp = fmt.format(Date(takenAt + offsetMinutes * 60_000L))
        val offset = offsetString(offsetMinutes)
        exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, stamp)
        exif.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, stamp)
        exif.setAttribute(ExifInterface.TAG_DATETIME, stamp)
        exif.setAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL, offset)
        exif.setAttribute(ExifInterface.TAG_OFFSET_TIME_DIGITIZED, offset)
        exif.setAttribute(ExifInterface.TAG_OFFSET_TIME, offset)
        if (lat != null && lng != null && !(lat == 0.0 && lng == 0.0)) {
            exif.setLatLong(lat, lng)
        }
        exif.saveAttributes()
    }

    private fun offsetString(minutes: Int): String {
        val sign = if (minutes < 0) "-" else "+"
        val abs = Math.abs(minutes)
        return String.format(Locale.US, "%s%02d:%02d", sign, abs / 60, abs % 60)
    }

    private fun insert(file: File, kind: String, name: String, album: String, takenAt: Long): String {
        val resolver = context.contentResolver
        val mime = mimeOf(name, kind)
        val isAudio = kind == KIND_AUDIO
        val dir = if (isAudio) Environment.DIRECTORY_DOWNLOADS else Environment.DIRECTORY_PICTURES
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (!isAudio) put(COLUMN_DATE_TAKEN, takenAt)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = when (kind) {
                KIND_VIDEO -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                KIND_AUDIO -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
                else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, "$dir/$album")
            // Пока файл пишется, галерея его не видит и не сканирует обрывок.
            values.put(MediaStore.MediaColumns.IS_PENDING, 1)
            val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore insert вернул null")
            try {
                val out = resolver.openOutputStream(uri) ?: throw IOException("нет потока записи")
                out.use { o -> file.inputStream().use { it.copyTo(o) } }
                val done = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                    // Повторно: у ролика в файле своей даты нет, и сканер,
                    // снимая IS_PENDING, не должен оставить поле пустым.
                    if (!isAudio) put(COLUMN_DATE_TAKEN, takenAt)
                }
                resolver.update(uri, done, null, null)
            } catch (e: Exception) {
                try {
                    resolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
            return uri.toString()
        }

        // Android 9 и ниже: файл кладётся в общую папку руками, строка в
        // MediaStore ставится с путём. Разрешение на запись спросил gal.
        @Suppress("DEPRECATION")
        val folder = File(Environment.getExternalStoragePublicDirectory(dir), album)
        if (!folder.exists() && !folder.mkdirs()) throw IOException("не создать ${folder.path}")
        val base = name.substringBeforeLast('.')
        val ext = name.substringAfterLast('.', "")
        var target = File(folder, name)
        var n = 1
        while (target.exists()) {
            target = File(folder, "${base}_$n.$ext")
            n++
        }
        file.copyTo(target)
        target.setLastModified(takenAt)
        if (isAudio) {
            MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(mime), null)
            return Uri.fromFile(target).toString()
        }
        @Suppress("DEPRECATION")
        values.put(MediaStore.MediaColumns.DATA, target.absolutePath)
        val collection = if (kind == KIND_VIDEO) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = resolver.insert(collection, values)
        if (uri == null) {
            MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(mime), null)
            return Uri.fromFile(target).toString()
        }
        return uri.toString()
    }

    private fun mimeOf(name: String, kind: String): String =
        when (name.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "gif" -> "image/gif"
            "mp4", "m4v" -> "video/mp4"
            "mov" -> "video/quicktime"
            "webm" -> "video/webm"
            "3gp" -> "video/3gpp"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "aac" -> "audio/aac"
            "ogg", "oga" -> "audio/ogg"
            "wav" -> "audio/wav"
            else -> when (kind) {
                KIND_VIDEO -> "video/mp4"
                KIND_AUDIO -> "audio/mpeg"
                else -> "image/jpeg"
            }
        }

    /** «Открыть» после сохранения: галерея на последнем файле. */
    private fun open(uri: String?) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            if (uri != null && uri.startsWith("content://")) {
                val u = Uri.parse(uri)
                setDataAndType(u, context.contentResolver.getType(u) ?: "image/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                data = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            try {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        const val CHANNEL = "love_app/gallery"
        const val ACCESS_DENIED = "ACCESS_DENIED"
        const val DEFAULT_ALBUM = "Togetherly"
        const val KIND_PHOTO = "photo"
        const val KIND_VIDEO = "video"
        const val KIND_AUDIO = "audio"

        /** `MediaStore.MediaColumns.DATE_TAKEN` появился константой лишь в
         * API 29, а колонка у снимков и роликов была всегда. */
        private const val COLUMN_DATE_TAKEN = "datetaken"
        private const val TAG = "GallerySaver"
    }
}
