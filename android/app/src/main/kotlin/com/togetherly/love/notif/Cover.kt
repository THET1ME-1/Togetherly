package com.togetherly.love.notif

import org.json.JSONArray
import org.json.JSONObject

/**
 * Уведомление «А. Обложка» (28.11.2026): что показать, собранное сервером
 * (`pocketbase/hotpath/push_cover.py`) или приложением для своих уведомлений
 * (`lib/models/push_cover.dart`). Формы одинаковые, тексты уже на языке
 * хозяина телефона.
 *
 * Здесь только разбор: без Android, чтобы проверяться на JVM.
 */
data class Cover(
    val kind: String,
    val kicker: String,
    val title: String,
    val body: String,
    val tone: String,
    val art: Art,
    /** Картинка развёрнутого вида у уведомлений самого приложения. */
    val artBig: Art?,
    val actions: List<CoverAction>,
    /** Куда ведёт нажатие: `loveapp://open/<экран>`. */
    val link: String,
    /** Пара события: «обнять» и снежок телефон шлёт в неё сам. */
    val group: String,
    /** Импульс «Скучаю», на который отвечает «обнять в ответ». */
    val eventId: String,
    /** Подпись, если действие из шторки не дошло. */
    val failed: String,
    val chat: ChatPart?,
    /** Котики «Моти» — кнопки настроения на экране блокировки (`mood_lock`). */
    val moods: List<MoodChoice> = emptyList(),
    /** Подпись после действия из шторки, которое дошло («Смена пароля отменена»). */
    val done: String = "",
    /** Цвета темы человека вместо тона («Дни вместе», макет). */
    val accent: Tone? = null,
) {
    /** Пуш от самого приложения: слева иконка, картинка события — в развёрнутом. */
    val fromApp: Boolean get() = art.app && artBig != null

    /** Цвета обложки: тема человека, если дана, иначе тон события. */
    val colors: Tone get() = accent ?: Tones.of(tone)
}

/** Картинка обложки: ссылка, значок даты или иконка приложения. */
data class Art(
    val url: String = "",
    /** Файл закрыт (фото воспоминания): нужен пропуск своим входом. */
    val auth: Boolean = false,
    /** Значок Material Symbols по имени (`theater_comedy`). */
    val symbol: String = "",
    /**
     * Слои поверх картинки [url] того же размера — наряд Ту: [under] под
     * ней, [over] над ней, снизу вверх. Склеивает `NotifArt`.
     */
    val under: List<String> = emptyList(),
    val over: List<String> = emptyList(),
) {
    /** Иконка приложения: ни ссылки, ни значка. */
    val app: Boolean get() = url.isEmpty() && symbol.isEmpty()

    companion object {
        val APP = Art()

        fun of(json: JSONObject?): Art {
            if (json == null) return APP
            val url = json.optString("url", "")
            val symbol = json.optString("symbol", "")
            // Ссылки только наши и только https: обложку собирает сервер, но
            // уведомление не должно ходить куда попало, даже если её подменят.
            val safe = if (url.startsWith("https://")) url else ""
            fun layers(key: String): List<String> {
                val arr = json.optJSONArray(key) ?: return emptyList()
                return (0 until arr.length()).map { arr.optString(it, "") }.filter { it.startsWith("https://") }.take(6)
            }
            return Art(
                url = safe, auth = json.optBoolean("auth", false), symbol = symbol,
                under = if (safe.isEmpty()) emptyList() else layers("under"),
                over = if (safe.isEmpty()) emptyList() else layers("over"),
            )
        }
    }
}

/** Кнопка: [link] — открыть экран; без ссылки — действие телефона по [id]. */
data class CoverAction(val id: String, val label: String, val link: String) {
    val native: Boolean get() = link.isEmpty()
}

/** Котик «Моти»: номер настроения, подпись, картинка. */
data class MoodChoice(val id: String, val label: String, val url: String)

/** Часть обложки чата: переписка как в мессенджере. */
data class ChatPart(
    val fromUid: String,
    val fromName: String,
    val groupId: String,
    val messageId: String,
    val ts: Long,
    val avatar: String,
    val frame: String,
    /** Радиус фото под рамкой в единицах 0..100 (`AvatarFrame.hole`). */
    val frameHole: Double,
    /** Фото или кадр кружка из сообщения. */
    val image: String,
    /** Волна голосового: до 40 цифр 0–9 (`VoicePeaks`), пусто — не голосовое. */
    val peaks: String = "",
    val quick: List<String>,
    val you: String,
    val queued: String,
    val hugged: String,
)

object CoverParser {
    /** Действия, которые телефон выполняет сам (`ДЕЙСТВИЯ_ТЕЛЕФОНА` сервера). */
    val NATIVE_ACTIONS = setOf("reply", "hug", "read", "throw", "cancel_reset", "thank")

    /** Обложка из строки JSON или null: старая версия, мусор, пусто. */
    fun parse(raw: String?): Cover? {
        if (raw.isNullOrBlank()) return null
        val o = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return null
        }
        if (o.optInt("v", 0) != 1) return null
        val kind = o.optString("kind", "")
        if (kind.isEmpty()) return null
        return Cover(
            kind = kind,
            kicker = o.optString("kicker", ""),
            title = o.optString("title", ""),
            body = o.optString("body", ""),
            tone = o.optString("tone", "app"),
            art = Art.of(o.optJSONObject("art")),
            artBig = o.optJSONObject("art_big")?.let { Art.of(it) },
            actions = actions(o.optJSONArray("actions")),
            link = safeLink(o.optString("link", "")),
            group = o.optString("group", ""),
            eventId = o.optString("event_id", ""),
            failed = o.optString("failed", ""),
            chat = o.optJSONObject("chat")?.let { chat(it) },
            moods = moods(o.optJSONArray("moods")),
            done = o.optString("done", ""),
            accent = accent(o.optJSONObject("accent")),
        )
    }

    /** Четыре цвета `#RRGGBB` темы человека или null, если чего-то нет. */
    private fun accent(o: JSONObject?): Tone? {
        if (o == null) return null
        fun color(key: String): Int? {
            val v = o.optString(key, "")
            if (v.length != 7 || v[0] != '#') return null
            return v.substring(1).toLongOrNull(16)?.let { (0xFF000000 or it).toInt() }
        }
        return Tone(
            tint = color("tint") ?: return null,
            label = color("label") ?: return null,
            deep = color("deep") ?: return null,
            labelNight = color("label_night") ?: return null,
        )
    }

    private fun moods(arr: JSONArray?): List<MoodChoice> {
        if (arr == null) return emptyList()
        val out = ArrayList<MoodChoice>()
        for (i in 0 until arr.length()) {
            val m = arr.optJSONObject(i) ?: continue
            val id = m.optString("id", "")
            val url = m.optString("url", "")
            // Номер уходит в ссылку настроения — только буквы, цифры и `_`.
            if (id.isEmpty() || !id.all { it.isLetterOrDigit() || it == '_' } || !url.startsWith("https://")) continue
            out.add(MoodChoice(id, m.optString("label", ""), url))
        }
        return out.take(5)
    }

    /** Только свои ссылки уведомлений; чужая или пустая — главная. */
    fun safeLink(link: String): String =
        if (link.startsWith("loveapp://open/")) link else "loveapp://open/home"

    private fun actions(arr: JSONArray?): List<CoverAction> {
        if (arr == null) return emptyList()
        val out = ArrayList<CoverAction>()
        for (i in 0 until arr.length()) {
            val a = arr.optJSONObject(i) ?: continue
            val id = a.optString("id", "")
            val label = a.optString("label", "")
            if (id.isEmpty() || label.isEmpty()) continue
            val rawLink = a.optString("link", "")
            // Кнопка без ссылки, которую телефон делать не умеет, — пропускаем:
            // нажатие ничего бы не сделало.
            if (rawLink.isEmpty() && id !in NATIVE_ACTIONS) continue
            out.add(CoverAction(id, label, if (rawLink.isEmpty()) "" else safeLink(rawLink)))
        }
        // В шторке Android больше трёх кнопок не помещается.
        return out.take(3)
    }

    private fun chat(o: JSONObject): ChatPart {
        val quick = ArrayList<String>()
        o.optJSONArray("quick")?.let { q ->
            for (i in 0 until q.length()) q.optString(i, "").takeIf { it.isNotEmpty() }?.let(quick::add)
        }
        fun https(key: String) = o.optString(key, "").takeIf { it.startsWith("https://") } ?: ""
        return ChatPart(
            fromUid = o.optString("from_uid", ""),
            fromName = o.optString("from_name", ""),
            groupId = o.optString("group_id", ""),
            messageId = o.optString("message_id", ""),
            ts = o.optLong("ts", 0L),
            avatar = https("avatar"),
            frame = https("frame"),
            frameHole = o.optDouble("frame_hole", 31.0).let { if (it.isNaN()) 31.0 else it.coerceIn(18.0, 31.0) },
            image = https("image"),
            peaks = o.optString("peaks", "").filter { it in '0'..'9' }.take(40),
            quick = quick,
            you = o.optString("you", "").ifEmpty { "You" },
            queued = o.optString("queued", ""),
            hugged = o.optString("hugged", ""),
        )
    }
}
