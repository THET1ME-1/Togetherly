package com.togetherly.love

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Очередь фоновой записи в галерею — живёт без Dart.
 *
 * Dart отдаёт файлы (`engineSubmit`) и забирает готовое (`engineStatus` →
 * `engineAck`). Всё держится по ключу файла: повторная постановка того же
 * ключа ничего не удваивает — после перезапуска Dart ставит недоделанное
 * заново, и уже идущее просто продолжается. Состояние лежит в файле, поэтому
 * переживает и смерть процесса: служба при следующем старте берёт очередь
 * оттуда.
 *
 * Качает и пишет [MediaSaveService]: три потока, уведомление с ходом и
 * кнопкой «Остановить».
 */
object MediaSaveEngine {
    private const val TAG = "MediaSaveEngine"
    private const val FILE = "media_save_engine.json"

    data class Item(
        val key: String,
        val url: String?,
        val path: String?,
        val deleteAfter: Boolean,
        val kind: String,
        val takenAt: Long,
        val offsetMinutes: Int,
        val latitude: Double?,
        val longitude: Double?,
        val name: String,
        val album: String,
        val title: String,
    ) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("key", key)
            put("url", url ?: JSONObject.NULL)
            put("path", path ?: JSONObject.NULL)
            put("deleteAfter", deleteAfter)
            put("kind", kind)
            put("takenAt", takenAt)
            put("offsetMinutes", offsetMinutes)
            put("latitude", latitude ?: JSONObject.NULL)
            put("longitude", longitude ?: JSONObject.NULL)
            put("name", name)
            put("album", album)
            put("title", title)
        }

        companion object {
            fun fromJson(o: JSONObject) = Item(
                key = o.getString("key"),
                url = o.optStringOrNull("url"),
                path = o.optStringOrNull("path"),
                deleteAfter = o.optBoolean("deleteAfter"),
                kind = o.optString("kind", GallerySaver.KIND_PHOTO),
                takenAt = o.optLong("takenAt"),
                offsetMinutes = o.optInt("offsetMinutes"),
                latitude = if (o.isNull("latitude")) null else o.optDouble("latitude"),
                longitude = if (o.isNull("longitude")) null else o.optDouble("longitude"),
                name = o.optString("name"),
                album = o.optString("album", GallerySaver.DEFAULT_ALBUM),
                title = o.optString("title"),
            )

            fun fromArgs(a: Map<*, *>) = Item(
                key = a["key"] as String,
                url = a["url"] as? String,
                path = a["path"] as? String,
                deleteAfter = a["deleteAfter"] == true,
                kind = a["kind"] as? String ?: GallerySaver.KIND_PHOTO,
                takenAt = (a["takenAt"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                offsetMinutes = (a["offsetMinutes"] as? Number)?.toInt() ?: 0,
                latitude = (a["latitude"] as? Number)?.toDouble(),
                longitude = (a["longitude"] as? Number)?.toDouble(),
                name = a["name"] as? String ?: "Togetherly",
                album = a["album"] as? String ?: GallerySaver.DEFAULT_ALBUM,
                title = a["title"] as? String ?: "",
            )
        }
    }

    data class Result(val key: String, val code: String, val uri: String?, val error: String?) {
        fun toMap(): Map<String, Any?> = mapOf("key" to key, "code" to code, "uri" to uri, "error" to error)
        fun toJson(): JSONObject = JSONObject().apply {
            put("key", key)
            put("code", code)
            put("uri", uri ?: JSONObject.NULL)
            put("error", error ?: JSONObject.NULL)
        }
    }

    const val OK = "OK"
    const val FAILED = "FAILED"
    const val ACCESS_DENIED = "ACCESS_DENIED"
    const val CANCELLED = "CANCELLED"

    private val pending = LinkedHashMap<String, Item>()
    private val running = HashMap<String, Item>()
    private val results = LinkedHashMap<String, Result>()

    /** Идущие файлы, которые сняли: поток бросит загрузку, итога не будет. */
    private val dropped = HashSet<String>()

    /** Идущие файлы, остановленные из уведомления: итог CANCELLED — так Dart
     *  узнает, что задание погасили не крестиком в приложении. */
    private val stopped = HashSet<String>()

    /** Подписи уведомления на языке приложения — их присылает Dart. */
    var labels: Map<String, String> = emptyMap()
        private set

    // Ход текущей пачки для уведомления: сколько поставлено с последнего
    // простоя, сколько сделано и не сделано.
    var batchTotal = 0
        private set
    var batchDone = 0
        private set
    var batchFailed = 0
        private set
    var lastTitle = ""
        private set
    var lastUri: String? = null
        private set

    private var loaded = false

    @Synchronized
    private fun load(ctx: Context) {
        if (loaded) return
        loaded = true
        try {
            val f = File(ctx.filesDir, FILE)
            if (!f.exists()) return
            val o = JSONObject(f.readText())
            o.optJSONArray("pending")?.let { a ->
                for (i in 0 until a.length()) {
                    val it = Item.fromJson(a.getJSONObject(i))
                    pending[it.key] = it
                }
            }
            o.optJSONArray("results")?.let { a ->
                for (i in 0 until a.length()) {
                    val r = a.getJSONObject(i)
                    val key = r.getString("key")
                    results[key] = Result(key, r.optString("code", FAILED),
                        r.optStringOrNull("uri"), r.optStringOrNull("error"))
                }
            }
            o.optJSONObject("labels")?.let { l ->
                labels = l.keys().asSequence().associateWith { k -> l.optString(k) }
            }
            batchTotal = pending.size
        } catch (e: Exception) {
            Log.w(TAG, "load", e)
        }
    }

    @Synchronized
    private fun persist(ctx: Context) {
        try {
            val o = JSONObject()
            // Идущие сохраняются как ждущие: умрёт процесс — начнутся заново.
            o.put("pending", JSONArray().apply {
                running.values.forEach { put(it.toJson()) }
                pending.values.forEach { put(it.toJson()) }
            })
            o.put("results", JSONArray().apply { results.values.forEach { put(it.toJson()) } })
            o.put("labels", JSONObject(labels))
            File(ctx.filesDir, FILE).writeText(o.toString())
        } catch (e: Exception) {
            Log.w(TAG, "persist", e)
        }
    }

    @Synchronized
    fun submit(ctx: Context, args: Map<*, *>) {
        load(ctx)
        (args["labels"] as? Map<*, *>)?.let { l ->
            labels = l.entries.associate { (k, v) -> k.toString() to v.toString() }
        }
        val item = Item.fromArgs(args)
        val known = results.containsKey(item.key) ||
            pending.containsKey(item.key) || running.containsKey(item.key)
        if (!known) {
            pending[item.key] = item
            batchTotal++
            if (item.title.isNotEmpty()) lastTitle = item.title
            persist(ctx)
        }
        if (pending.isNotEmpty()) MediaSaveService.ensureRunning(ctx)
    }

    @Synchronized
    fun status(ctx: Context): Map<String, Any?> {
        load(ctx)
        // Служба могла не подняться (приложение ушло в фон раньше, чем её
        // успели запустить) — первый же опрос с экрана её поднимет.
        if (pending.isNotEmpty()) MediaSaveService.ensureRunning(ctx)
        return mapOf(
            "results" to results.values.map { it.toMap() },
            "pending" to pending.size + running.size,
        )
    }

    @Synchronized
    fun ack(ctx: Context, keys: List<String>) {
        load(ctx)
        keys.forEach { results.remove(it) }
        persist(ctx)
    }

    /** Крестик в приложении: Dart уже знает, итогов не нужно. */
    @Synchronized
    fun cancel(ctx: Context, keys: List<String>) {
        load(ctx)
        for (k in keys) {
            if (pending.remove(k) != null) batchTotal = (batchTotal - 1).coerceAtLeast(0)
            if (running.containsKey(k)) dropped.add(k)
        }
        persist(ctx)
    }

    /** «Остановить» в уведомлении: всё несделанное получает итог CANCELLED. */
    @Synchronized
    fun stopAll(ctx: Context) {
        load(ctx)
        for (k in pending.keys) results[k] = Result(k, CANCELLED, null, null)
        pending.clear()
        stopped.addAll(running.keys)
        persist(ctx)
    }

    /** Следующий файл для потока службы. */
    @Synchronized
    fun take(ctx: Context): Item? {
        load(ctx)
        val it = pending.values.firstOrNull() ?: return null
        pending.remove(it.key)
        running[it.key] = it
        return it
    }

    @Synchronized
    fun isDropped(key: String): Boolean = dropped.contains(key) || stopped.contains(key)

    @Synchronized
    fun finish(ctx: Context, item: Item, result: Result) {
        running.remove(item.key)
        when {
            dropped.remove(item.key) -> {
                stopped.remove(item.key)
            }
            stopped.remove(item.key) -> {
                results[item.key] = Result(item.key, CANCELLED, null, null)
            }
            else -> {
                results[item.key] = result
                if (result.code == OK) {
                    batchDone++
                    if (result.uri != null) lastUri = result.uri
                } else {
                    batchFailed++
                }
            }
        }
        persist(ctx)
    }

    @Synchronized
    fun isIdle(): Boolean = pending.isEmpty() && running.isEmpty()

    /** Итог пачки для уведомления «В галерее: 94» и обнуление счётчиков. */
    @Synchronized
    fun closeBatch(): Triple<Int, Int, String> {
        val out = Triple(batchDone, batchFailed, lastTitle)
        batchTotal = 0
        batchDone = 0
        batchFailed = 0
        return out
    }
}

private fun JSONObject.optStringOrNull(name: String): String? =
    if (isNull(name)) null else optString(name).takeIf { it.isNotEmpty() }
