package com.togetherly.love.notif

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Что делают кнопки шторки. Запросы те же, что у приложения:
 * сообщение — `chat_messages` (номер свой, повтор безопасен, как у очереди
 * `chatUpsert`), «обнять» — `/api/group/miss-you` с `want_hug`, «прочитано» —
 * `chat_reads` по паре и человеку (`PbDataService.chatRead`), снежок —
 * `/api/group/snowball`.
 */
object NotifActions {
    private const val TAG = "NotifActions"
    private const val BUDGET_MS = 8_000L

    /** Итог отправки: дошло, стоит повторить, повторять бесполезно. */
    enum class Sent { OK, RETRY, GIVE_UP }

    fun run(ctx: Context, cover: Cover, raw: String, action: String, reply: String, tag: String, id: Int) {
        val chat = cover.chat
        val group = cover.group.ifEmpty { chat?.groupId.orEmpty() }
        if (action.startsWith("mood:")) {
            pickMood(ctx, cover, raw, action.removePrefix("mood:"), group, tag, id)
            return
        }
        // Смена пароля — дело аккаунта, а не пары: пара тут не нужна.
        if (action == "cancel_reset") {
            cancelReset(ctx, cover, raw, tag, id)
            return
        }
        when (action) {
            "reply" -> {
                if (chat == null || reply.isEmpty() || group.isEmpty()) return
                val msgId = PbId.next()
                val ts = System.currentTimeMillis()
                when (sendMessage(ctx, group, msgId, reply, ts, BUDGET_MS)) {
                    Sent.OK -> NotifChat.appendMine(ctx, tag, id, reply)
                    Sent.RETRY -> {
                        NotifSendWorker.reply(ctx, group, msgId, reply, ts)
                        NotifChat.appendMine(ctx, tag, id, reply, note = chat.queued)
                    }
                    Sent.GIVE_UP -> NotifChat.appendMine(ctx, tag, id, reply, note = cover.failed)
                }
            }
            "hug" -> {
                if (group.isEmpty()) return
                val ok = hug(ctx, group, cover.eventId)
                if (chat != null) {
                    NotifChat.appendMine(ctx, tag, id, if (ok) chat.hugged else cover.failed)
                } else if (ok) {
                    NotifCover.cancel(ctx, tag, id)
                } else {
                    NotifCover.plain(ctx, cover.title, cover.failed, tag, id, cover.link)
                }
            }
            "read" -> {
                if (chat == null || group.isEmpty()) return
                val ts = if (chat.ts > 0) chat.ts else System.currentTimeMillis()
                // Человек сказал «прочитано» — уведомление уходит сразу, отметка
                // дойдёт, когда сможет.
                NotifCover.cancel(ctx, tag, id)
                if (markRead(ctx, group, ts, BUDGET_MS) == Sent.RETRY) NotifSendWorker.read(ctx, group, ts)
            }
            "throw" -> {
                if (group.isEmpty()) return
                if (snowball(ctx, group)) NotifCover.cancel(ctx, tag, id)
                else NotifCover.plain(ctx, cover.title, cover.failed, tag, id, cover.link)
            }
            else -> Log.i(TAG, "незнакомое действие $action")
        }
    }

    /**
     * Котик со шторки экрана блокировки: настроение уходит тем же путём, что
     * с плиток виджета (фоновый Dart, `loveapp://mood?id=…`, `main.dart`), а
     * плашка сразу показывает выбранного котика.
     */
    private fun pickMood(ctx: Context, cover: Cover, raw: String, moodId: String, group: String, tag: String, id: Int) {
        val choice = cover.moods.firstOrNull { it.id == moodId } ?: return
        try {
            // Без пары в ссылке Dart возьмёт пару виджета (`tgmood_latest_group`).
            val uri = if (group.isEmpty()) "loveapp://mood?id=$moodId" else "loveapp://mood?group=$group&id=$moodId"
            es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(ctx, android.net.Uri.parse(uri)).send()
        } catch (e: Exception) {
            Log.w(TAG, "не удалось разбудить Dart: ${e.message}")
        }
        val updated = try {
            JSONObject(raw)
                .put("title", choice.label.ifEmpty { cover.title })
                .put("art", JSONObject().put("url", choice.url))
                .toString()
        } catch (_: Exception) {
            raw
        }
        NotifChannel.showOrPlain(
            ctx, updated, choice.label, cover.body, tag, id,
            NotifCover.activeChannel(ctx, tag, id) ?: NotifCover.CHANNEL_PARTNER, ongoing = true, silent = true,
        )
    }

    /**
     * «Это не я»: хозяин аккаунта гасит смену пароля через партнёра — тот же
     * запрос, что лист «Ваш пароль меняют» в приложении. Дошло — уведомление
     * тем же видом говорит «Смена пароля отменена», без кнопок.
     */
    private fun cancelReset(ctx: Context, cover: Cover, raw: String, tag: String, id: Int) {
        val r = if (NotifNet.token(ctx) == null) null
        else NotifNet.call(ctx, "POST", "/api/auth/partner-reset/cancel", JSONObject(), budgetMs = BUDGET_MS)
        if (r?.ok != true) {
            NotifCover.plain(ctx, cover.title, cover.failed, tag, id, cover.link)
            return
        }
        val updated = try {
            JSONObject(raw).put("body", cover.done.ifEmpty { cover.body }).put("actions", org.json.JSONArray()).toString()
        } catch (_: Exception) {
            raw
        }
        NotifChannel.showOrPlain(
            ctx, updated, cover.title, cover.done, tag, id,
            NotifCover.activeChannel(ctx, tag, id) ?: NotifCover.CHANNEL_PARTNER, silent = true,
        )
    }

    /** Сообщение в чат пары. «Уже есть» — тоже успех: прошлый повтор дошёл. */
    fun sendMessage(ctx: Context, group: String, msgId: String, text: String, ts: Long, budgetMs: Long): Sent {
        val uid = NotifNet.myUid(ctx)
        if (uid.isEmpty() || NotifNet.token(ctx) == null) return Sent.GIVE_UP
        val body = JSONObject()
            .put("id", msgId)
            .put("group_id", group)
            .put("user_uid", uid)
            .put("user_name", NotifNet.myName(ctx))
            .put("text", text)
            .put("ts", ts)
            .put("deleted", false)
            // Часы телефона в момент отправки: по ним сервер узнаёт время
            // написания, если ответ досылается позже (`_withSentAt`).
            .put("sent_at", System.currentTimeMillis())
        val r = NotifNet.call(ctx, "POST", "/api/collections/chat_messages/records", body, budgetMs = budgetMs)
        return when {
            r.ok -> Sent.OK
            r.code == 400 && r.text().contains("Value must be unique") -> Sent.OK
            r.code == 401 || r.code == 403 || r.code == 400 -> Sent.GIVE_UP
            else -> Sent.RETRY
        }
    }

    /** «Обнять» — импульс `want_hug`; [replyTo] — на какой «Скучаю» это ответ. */
    private fun hug(ctx: Context, group: String, replyTo: String): Boolean {
        val uid = NotifNet.myUid(ctx)
        if (uid.isEmpty()) return false
        val body = JSONObject()
            .put("groupId", group)
            .put("uid", uid)
            .put("vibe", "want_hug")
            .put("text", "")
            .put("weekday", weekday())
            .put("count", 1)
        if (replyTo.isNotEmpty()) body.put("replyTo", replyTo)
        // Не повторяем вторым путём, если запрос мог дойти: объятие удвоилось бы.
        val r = NotifNet.call(ctx, "POST", "/api/group/miss-you", body, budgetMs = BUDGET_MS, idempotent = false)
        return r.ok
    }

    /** День недели как у приложения: 1 — понедельник. */
    private fun weekday(): Int {
        val dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK) // 1 — воскресенье
        return if (dow == Calendar.SUNDAY) 7 else dow - 1
    }

    /** Отметка прочтения до [ts]; назад не двигается. */
    fun markRead(ctx: Context, group: String, ts: Long, budgetMs: Long): Sent {
        val uid = NotifNet.myUid(ctx)
        if (uid.isEmpty() || NotifNet.token(ctx) == null) return Sent.GIVE_UP
        val filter = URLEncoder.encode("group_id = \"$group\" && user_uid = \"$uid\"", "UTF-8")
        val found = NotifNet.call(ctx, "GET", "/api/collections/chat_reads/records?perPage=1&filter=$filter", budgetMs = budgetMs / 2)
        if (!found.ok) return if (found.code in listOf(401, 403)) Sent.GIVE_UP else Sent.RETRY
        val item = try {
            JSONObject(found.text()).optJSONArray("items")?.optJSONObject(0)
        } catch (_: Exception) {
            null
        }
        if (item != null && item.optLong("last_read_ts", 0L) >= ts) return Sent.OK
        val body = JSONObject().put("last_read_ts", ts).put("updated_at", isoNow())
        val r = if (item != null) {
            NotifNet.call(ctx, "PATCH", "/api/collections/chat_reads/records/${item.optString("id")}", body, budgetMs = budgetMs / 2)
        } else {
            body.put("group_id", group).put("user_uid", uid)
            NotifNet.call(ctx, "POST", "/api/collections/chat_reads/records", body, budgetMs = budgetMs / 2)
        }
        return when {
            r.ok -> Sent.OK
            r.code in listOf(400, 401, 403, 404) -> Sent.GIVE_UP
            else -> Sent.RETRY
        }
    }

    private fun isoNow(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        .apply { timeZone = TimeZone.getTimeZone("UTC") }
        .format(Date())

    /** Снежок в ответ. «Слишком часто» (429) — снежок уже летит, это успех. */
    private fun snowball(ctx: Context, group: String): Boolean {
        val r = NotifNet.call(ctx, "POST", "/api/group/snowball", JSONObject().put("groupId", group), budgetMs = BUDGET_MS, idempotent = false)
        return r.ok || r.code == 429
    }
}
