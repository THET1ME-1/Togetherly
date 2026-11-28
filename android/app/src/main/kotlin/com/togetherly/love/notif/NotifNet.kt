package com.togetherly.love.notif

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Сеть уведомлений: картинки обложки и действия из шторки (ответ, «обнять»,
 * «прочитано», снежок), пока Dart не запущен.
 *
 * Вход берётся из prefs приложения (`flutter.pb_auth` — то же, что хранит
 * `PocketBaseService`). Путь — как у `ServerRoute` в Dart: прямой
 * `togetherly.day`, а если приложение запомнило запасной
 * (`server_route_spare_since_ms`), сперва `edge.togetherly.day`; не ответил
 * один — пробуем второй. Сертификат у обоих имён наш.
 */
object NotifNet {
    private const val TAG = "NotifNet"
    private const val PREFS = "FlutterSharedPreferences"
    const val HOST = "togetherly.day"
    const val SPARE = "edge.togetherly.day"

    /** Ответ сервера: код и тело; код 0 — до сервера не дошли. */
    class Reply(val code: Int, val body: ByteArray) {
        val ok: Boolean get() = code in 200..299
        fun text(): String = String(body, Charsets.UTF_8)
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun authJson(ctx: Context): JSONObject? = try {
        prefs(ctx).getString("flutter.pb_auth", null)?.let { JSONObject(it) }
    } catch (_: Exception) {
        null
    }

    /** Пропуск входа или null — человек не вошёл. */
    fun token(ctx: Context): String? = authJson(ctx)?.optString("token", "")?.takeIf { it.isNotEmpty() }

    /** Свой номер: из записи входа, запасной — `flutter.uid`. */
    fun myUid(ctx: Context): String {
        val fromAuth = authJson(ctx)?.optJSONObject("model")?.optString("id", "") ?: ""
        if (fromAuth.isNotEmpty()) return fromAuth
        return prefs(ctx).getString("flutter.uid", "") ?: ""
    }

    /** Своё имя для подписи сообщения. */
    fun myName(ctx: Context): String {
        val model = authJson(ctx)?.optJSONObject("model")
        val name = model?.optString("display_name", "")?.trim().orEmpty()
        if (name.isNotEmpty()) return name
        return (prefs(ctx).getString("flutter.displayName", "") ?: "").trim()
    }

    /** Приложение ходит запасным путём (Dart пишет int как long). */
    private fun spareFirst(ctx: Context): Boolean = try {
        prefs(ctx).getLong("flutter.server_route_spare_since_ms", 0L) > 0L
    } catch (_: ClassCastException) {
        false
    }

    /** Порядок имён для запроса: запомненный путь первым. */
    fun hosts(ctx: Context): List<String> = if (spareFirst(ctx)) listOf(SPARE, HOST) else listOf(HOST, SPARE)

    /**
     * Запрос к нашему серверу по [path] (`/api/...`) или полной ссылке нашего
     * имени. Сетевая ошибка на первом пути — второй. [budgetMs] — на оба.
     */
    fun call(
        ctx: Context,
        method: String,
        pathOrUrl: String,
        json: JSONObject? = null,
        auth: Boolean = true,
        budgetMs: Long = 12_000,
        maxBytes: Int = 4 * 1024 * 1024,
        idempotent: Boolean = true,
    ): Reply {
        val deadline = System.currentTimeMillis() + budgetMs
        val path = toPath(pathOrUrl) ?: return Reply(0, ByteArray(0))
        val token = if (auth) token(ctx) else null
        for (host in hosts(ctx)) {
            val left = deadline - System.currentTimeMillis()
            if (left < 800) break
            try {
                return once("https://$host$path", method, json, token, left, maxBytes)
            } catch (e: AfterConnect) {
                // Запрос мог дойти: повтор вторым путём засчитал бы «обнять»
                // дважды. Повторяем только то, что повторять безопасно.
                Log.i(TAG, "$host: оборвалось после соединения (${e.cause?.javaClass?.simpleName})")
                if (!idempotent) return Reply(0, ByteArray(0))
            } catch (e: IOException) {
                Log.i(TAG, "$host: ${e.javaClass.simpleName}")
            }
        }
        return Reply(0, ByteArray(0))
    }

    /** Сбой после того, как соединение открылось: сервер мог принять запрос. */
    private class AfterConnect(cause: IOException) : IOException(cause)

    /** Путь нашей ссылки (`https://togetherly.day/...` → `/...`); чужая — null. */
    fun toPath(pathOrUrl: String): String? {
        if (pathOrUrl.startsWith("/")) return pathOrUrl
        for (host in listOf(HOST, SPARE)) {
            val prefix = "https://$host/"
            if (pathOrUrl.startsWith(prefix)) return pathOrUrl.substring(prefix.length - 1)
        }
        return null
    }

    private fun once(
        url: String,
        method: String,
        json: JSONObject?,
        token: String?,
        budgetMs: Long,
        maxBytes: Int,
    ): Reply {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = minOf(budgetMs, 5_000L).toInt()
            conn.readTimeout = minOf(budgetMs, 8_000L).toInt()
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("User-Agent", "Togetherly-Android-Notif")
            if (token != null) conn.setRequestProperty("Authorization", token)
            val bytes = json?.toString()?.toByteArray(Charsets.UTF_8)
            if (bytes != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setFixedLengthStreamingMode(bytes.size)
            }
            // До этой строки сбой значит «до сервера не дошли» — можно другим путём.
            conn.connect()
            try {
                if (bytes != null) conn.outputStream.use { it.write(bytes) }
                val code = conn.responseCode
                val stream = if (code in 200..399) conn.inputStream else conn.errorStream
                val body = stream?.use { input ->
                    val out = ByteArrayOutputStream()
                    val buf = ByteArray(16 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        if (out.size() > maxBytes) throw IOException("слишком большой ответ")
                    }
                    out.toByteArray()
                } ?: ByteArray(0)
                return Reply(code, body)
            } catch (e: IOException) {
                throw AfterConnect(e)
            }
        } finally {
            conn.disconnect()
        }
    }

    // Пропуск к закрытым файлам (`/api/files/token`) живёт у PocketBase две
    // минуты; берём один на пачку картинок.
    @Volatile private var fileToken: Pair<String, Long>? = null

    /** Ссылка закрытого файла с пропуском или null — пропуск не дали. */
    fun withFileToken(ctx: Context, url: String, budgetMs: Long): String? {
        val now = System.currentTimeMillis()
        val cached = fileToken
        val tokenValue = if (cached != null && now - cached.second < 90_000) {
            cached.first
        } else {
            val reply = call(ctx, "POST", "/api/files/token", JSONObject(), budgetMs = budgetMs)
            if (!reply.ok) return null
            val t = try {
                JSONObject(reply.text()).optString("token", "")
            } catch (_: Exception) {
                ""
            }
            if (t.isEmpty()) return null
            fileToken = t to now
            t
        }
        val sep = if (url.contains('?')) '&' else '?'
        return "$url${sep}token=$tokenValue"
    }
}
