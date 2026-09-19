package com.togetherly.love

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Фоновая запись медиа воспоминаний в галерею (19.09.2026).
 *
 * Служба переднего плана типа dataSync: уведомление «Сохраняю в галерею ·
 * Лето на Днестре · 37/94» с кнопкой «Остановить». Работает отдельно от
 * экрана: сохранение не встаёт, когда приложение свернули или смахнули из
 * недавних, — служба живёт без Dart и без Activity. Очередь и итоги держит
 * [MediaSaveEngine], Dart только отдаёт файлы и забирает готовое.
 *
 * Три потока: больше не даёт скорости на одном канале телефона, а сервер
 * отдаёт файлы через кэш раздачи. По окончании вместо хода — «В галерее: 94».
 */
class MediaSaveService : Service() {

    companion object {
        private const val TAG = "MediaSaveService"
        private const val CHANNEL_ID = "media_save"
        private const val PROGRESS_ID = 77301
        private const val DONE_ID = 77302
        private const val ACTION_STOP = "com.togetherly.love.MEDIA_SAVE_STOP"
        private const val WORKERS = 3

        @Volatile
        var isRunning = false
            private set

        /**
         * Поднять службу, если её нет. Запуск из фона Android 12+ запрещает —
         * тогда файлы ждут в очереди до следующего опроса с экрана.
         */
        fun ensureRunning(ctx: Context) {
            if (isRunning) {
                instance?.wakeWorkers()
                return
            }
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, MediaSaveService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "start refused", e)
            }
        }

        @Volatile
        private var instance: MediaSaveService? = null
    }

    private val lock = Object()
    private var activeWorkers = 0

    /** Служба уходит (кончились сутки dataSync): новых файлов не брать. */
    @Volatile
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        createChannel()
        try {
            ServiceCompat.startForeground(
                this,
                PROGRESS_ID,
                progressNotification(),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
            )
        } catch (e: Exception) {
            // Не дали подняться на передний план — работать в фоне нельзя.
            Log.w(TAG, "startForeground refused", e)
            isRunning = false
            instance = null
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            MediaSaveEngine.stopAll(this)
        } else if (stopping) {
            // Новый файл пришёл, пока служба уходила: Android отдал его тому же
            // экземпляру — возвращаемся на передний план и работаем дальше.
            stopping = false
            instance = this
            isRunning = true
            try {
                ServiceCompat.startForeground(
                    this, PROGRESS_ID, progressNotification(),
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
                )
            } catch (e: Exception) {
                Log.w(TAG, "startForeground refused", e)
            }
        }
        wakeWorkers()
        return START_NOT_STICKY
    }

    /** Android 15: сутки dataSync исчерпаны — сохраняем очередь и уходим.
     *  Недоделанное Dart поставит снова при следующем открытии приложения. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "dataSync timeout")
        shutdown(showResult = false)
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        super.onDestroy()
    }

    fun wakeWorkers() {
        synchronized(lock) {
            while (activeWorkers < WORKERS) {
                activeWorkers++
                Thread({ workLoop() }, "media-save-$activeWorkers").start()
            }
        }
    }

    private fun workLoop() {
        try {
            while (!stopping) {
                val item = MediaSaveEngine.take(this) ?: break
                val result = process(item)
                MediaSaveEngine.finish(this, item, result)
                updateProgress()
            }
        } finally {
            val last = synchronized(lock) {
                activeWorkers--
                activeWorkers == 0
            }
            if (last && MediaSaveEngine.isIdle()) shutdown(showResult = true)
        }
    }

    private fun process(item: MediaSaveEngine.Item): MediaSaveEngine.Result {
        var temp: File? = null
        try {
            val file: File = when {
                item.path != null -> File(item.path)
                item.url != null -> download(item).also { temp = it }
                else -> throw IOException("нет ни пути, ни ссылки")
            }
            if (MediaSaveEngine.isDropped(item.key)) {
                return MediaSaveEngine.Result(item.key, MediaSaveEngine.CANCELLED, null, null)
            }
            val uri = GallerySaver(applicationContext).writeFile(
                GallerySaver.Params(
                    path = file.path,
                    kind = item.kind,
                    takenAt = item.takenAt,
                    offsetMinutes = item.offsetMinutes,
                    latitude = item.latitude,
                    longitude = item.longitude,
                    name = item.name,
                    album = item.album,
                )
            )
            return MediaSaveEngine.Result(item.key, MediaSaveEngine.OK, uri, null)
        } catch (e: SecurityException) {
            return MediaSaveEngine.Result(item.key, MediaSaveEngine.ACCESS_DENIED, null, e.message)
        } catch (e: Exception) {
            Log.w(TAG, "не сохранился ${item.key}", e)
            return MediaSaveEngine.Result(item.key, MediaSaveEngine.FAILED, null, e.toString())
        } finally {
            temp?.delete()
            if (item.deleteAfter && item.path != null) File(item.path).delete()
        }
    }

    /** Загрузка с тремя попытками: мобильная сеть рвётся, и это не повод
     *  отдавать кадр Dart как несохранённый. */
    private fun download(item: MediaSaveEngine.Item): File {
        val ext = item.name.substringAfterLast('.', "bin")
        val out = File(cacheDir, "media_save_${item.key.hashCode()}.$ext")
        var last: Exception? = null
        for (attempt in 0 until 3) {
            if (MediaSaveEngine.isDropped(item.key)) throw IOException("снят")
            try {
                val conn = URL(item.url).openConnection() as HttpURLConnection
                conn.connectTimeout = 30_000
                conn.readTimeout = 60_000
                try {
                    val code = conn.responseCode
                    if (code != 200) throw IOException("HTTP $code")
                    conn.inputStream.use { input ->
                        out.outputStream().use { output ->
                            val buf = ByteArray(64 * 1024)
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                if (MediaSaveEngine.isDropped(item.key)) throw IOException("снят")
                                output.write(buf, 0, n)
                            }
                        }
                    }
                } finally {
                    conn.disconnect()
                }
                if (out.length() == 0L) throw IOException("пустой ответ")
                return out
            } catch (e: Exception) {
                last = e
                out.delete()
                // 404 и 403 повтором не лечатся.
                if (e.message?.startsWith("HTTP 4") == true) break
                Thread.sleep(longArrayOf(2_000, 5_000, 10_000)[attempt])
            }
        }
        throw last ?: IOException("не скачался")
    }

    private fun label(key: String, fallback: String) =
        MediaSaveEngine.labels[key]?.takeIf { it.isNotEmpty() } ?: fallback

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        // Тихий канал: ход сохранения не должен звенеть на каждом кадре.
        val ch = NotificationChannel(
            CHANNEL_ID,
            label("saving", "Сохранение в галерею"),
            NotificationManager.IMPORTANCE_LOW
        )
        ch.setShowBadge(false)
        nm.createNotificationChannel(ch)
    }

    private fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun progressNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_stat_photo)
        .setContentTitle(label("saving", "Сохраняю в галерею"))
        .setContentText(progressText())
        .setProgress(
            MediaSaveEngine.batchTotal.coerceAtLeast(1),
            MediaSaveEngine.batchDone + MediaSaveEngine.batchFailed,
            MediaSaveEngine.batchTotal == 0
        )
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setSilent(true)
        .setContentIntent(openAppIntent())
        .addAction(
            0,
            label("stop", "Остановить"),
            PendingIntent.getService(
                this, 1,
                Intent(this, MediaSaveService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )
        .build()

    private fun progressText(): String {
        val done = MediaSaveEngine.batchDone + MediaSaveEngine.batchFailed
        val total = MediaSaveEngine.batchTotal
        val title = MediaSaveEngine.lastTitle
        val count = "$done/$total"
        return if (title.isEmpty()) count else "$title · $count"
    }

    private fun updateProgress() {
        if (stopping) return
        try {
            NotificationManagerCompat.from(this).notify(PROGRESS_ID, progressNotification())
        } catch (e: SecurityException) {
            // Уведомления запрещены — служба работает и без них.
        }
    }

    private fun shutdown(showResult: Boolean) {
        if (stopping) return
        stopping = true
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        if (showResult) {
            val (done, failed, title) = MediaSaveEngine.closeBatch()
            if (done + failed > 0) showDone(done, failed, title)
        }
        isRunning = false
        instance = null
        stopSelf()
    }

    private fun showDone(done: Int, failed: Int, title: String) {
        val text = if (failed > 0)
            label("failed", "Не сохранилось: {n}").replace("{n}", "$failed")
        else
            label("done", "В галерее: {n}").replace("{n}", "$done")
        val n = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_photo)
            .setContentTitle(text)
            .setContentText(title)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        try {
            NotificationManagerCompat.from(this).notify(DONE_ID, n)
        } catch (e: SecurityException) {
        }
    }
}
