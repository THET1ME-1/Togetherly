package com.togetherly.love.notif

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.util.Calendar

/**
 * Свои уведомления по расписанию видом «А» (капсула, праздники, «Ту
 * скучает», приглашение, дни вместе). Плагин уведомлений рисует
 * запланированное сам в момент срабатывания, мимо `NotifCover`, поэтому
 * расписание здесь своё: обложка хранится до срабатывания и рисуется тем же
 * `NotifChannel.showOrPlain`, что пуш.
 *
 * Хранится в prefs `notif_alarms` (номер → запись), после перезагрузки и
 * обновления приложения `NotifAlarmBoot` ставит будильники заново.
 * Ежедневное (`daily`) после срабатывания переставляется на завтра на то же
 * время по часам телефона.
 */
object NotifAlarm {
    private const val TAG = "NotifAlarm"
    private const val PREFS = "notif_alarms"
    const val EXTRA_ID = "tg_alarm_id"

    /** Запись расписания: всё, что нужно показать без Dart. */
    data class Entry(
        val id: Int,
        val whenMs: Long,
        val cover: String,
        val title: String,
        val body: String,
        val tag: String,
        val channel: String,
        val exact: Boolean,
        val daily: Boolean,
        /** Постоянная плашка («Дни вместе»): смахнуть нельзя. */
        val ongoing: Boolean = false,
        val silent: Boolean = false,
        /**
         * Заголовок на каждый день от первого срабатывания ([titlesFrom]):
         * число «N дней вместе» меняется, а Dart в момент срабатывания не
         * запущен. Кончились — остаётся последний, до открытия приложения.
         */
        val titles: List<String> = emptyList(),
        val titlesFrom: Long = whenMs,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id).put("when", whenMs).put("cover", cover).put("title", title).put("body", body)
            .put("tag", tag).put("channel", channel).put("exact", exact).put("daily", daily)
            .put("ongoing", ongoing).put("silent", silent)
            .put("titles", org.json.JSONArray(titles)).put("titles_from", titlesFrom)

        /** Заголовок дня срабатывания [atMs]; списка нет — общий [title]. */
        fun titleAt(atMs: Long): String {
            if (titles.isEmpty()) return title
            return titles[dayIndex(titlesFrom, atMs).coerceIn(0, titles.size - 1)]
        }

        companion object {
            fun of(o: JSONObject): Entry {
                val arr = o.optJSONArray("titles")
                val titles = if (arr == null) emptyList() else (0 until arr.length()).map { arr.optString(it) }
                val whenMs = o.optLong("when")
                return Entry(
                    id = o.optInt("id"), whenMs = whenMs, cover = o.optString("cover"),
                    title = o.optString("title"), body = o.optString("body"), tag = o.optString("tag"),
                    channel = o.optString("channel"), exact = o.optBoolean("exact"), daily = o.optBoolean("daily"),
                    ongoing = o.optBoolean("ongoing"), silent = o.optBoolean("silent"),
                    titles = titles, titlesFrom = o.optLong("titles_from", whenMs),
                )
            }
        }
    }

    /** Сколько календарных дней от [fromMs] до [atMs] по часам телефона. */
    fun dayIndex(fromMs: Long, atMs: Long): Int {
        fun dayStart(ms: Long) = Calendar.getInstance().apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        // Сутки перевода часов длятся 23 или 25 часов — округление, а не деление нацело.
        return Math.round((dayStart(atMs) - dayStart(fromMs)) / 86_400_000.0).toInt()
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(ctx: Context, id: Int): Entry? = prefs(ctx).getString(id.toString(), null)?.let {
        try {
            Entry.of(JSONObject(it))
        } catch (_: Exception) {
            null
        }
    }

    fun all(ctx: Context): List<Entry> = prefs(ctx).all.values.mapNotNull { v ->
        (v as? String)?.let {
            try {
                Entry.of(JSONObject(it))
            } catch (_: Exception) {
                null
            }
        }
    }

    fun schedule(ctx: Context, entry: Entry) {
        prefs(ctx).edit().putString(entry.id.toString(), entry.toJson().toString()).apply()
        arm(ctx, entry)
    }

    /**
     * Картинки обложки скачать сейчас, пока приложение открыто и сеть есть:
     * в момент срабатывания (00:10, сон телефона, самолёт) их берут с диска
     * (`NotifArt`), и вместо Ту не встаёт иконка.
     */
    fun prefetch(ctx: Context, entry: Entry) {
        val cover = CoverParser.parse(entry.cover) ?: return
        val arts = buildMap<String, Art> {
            if (cover.art.url.isNotEmpty() && !cover.art.auth) put("art", cover.art)
            val big = cover.artBig
            if (big != null && big.url.isNotEmpty() && !big.auth) put("big", big)
        }
        if (arts.isNotEmpty()) NotifArt.fetchAll(ctx, arts, NotifCover.IMAGES_BUDGET_MS)
    }

    /**
     * Показать ли запись сразу после перезагрузки: постоянная плашка («Дни
     * вместе») пропадает вместе со шторкой, а до своего часа (00:10) ждать
     * её не должны. Разовые — только в свой срок.
     */
    fun showsAtBoot(entry: Entry): Boolean = entry.ongoing && entry.daily

    fun cancel(ctx: Context, id: Int) {
        prefs(ctx).edit().remove(id.toString()).apply()
        ctx.getSystemService(AlarmManager::class.java)?.cancel(pending(ctx, id))
    }

    /** Поставить будильник. Точный — если разрешён, иначе система сдвинет на минуты. */
    fun arm(ctx: Context, entry: Entry) {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        val pi = pending(ctx, entry.id)
        val canExact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        try {
            if (entry.exact && canExact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, entry.whenMs, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, entry.whenMs, pi)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "точный будильник не дали — неточный: ${e.message}")
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, entry.whenMs, pi)
        }
    }

    private fun pending(ctx: Context, id: Int): PendingIntent {
        val intent = Intent(ctx, NotifAlarmReceiver::class.java)
            .setAction("com.togetherly.love.NOTIF_ALARM")
            .setPackage(ctx.packageName)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(
            ctx, 0x7A000000 or (id and 0x00FFFFFF), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Следующий день то же время по часам телефона (перевод часов учтён). */
    fun nextDay(whenMs: Long, nowMs: Long): Long {
        val c = Calendar.getInstance().apply { timeInMillis = whenMs }
        while (c.timeInMillis <= nowMs) c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    /** Сработал будильник [id]: показать и, если ежедневный, переставить. */
    fun fire(ctx: Context, id: Int) {
        val entry = load(ctx, id) ?: return
        show(ctx, entry, entry.whenMs)
        if (entry.daily) {
            schedule(ctx, entry.copy(whenMs = nextDay(entry.whenMs, System.currentTimeMillis())))
        } else {
            prefs(ctx).edit().remove(id.toString()).apply()
        }
    }

    /** Показать запись с заголовком дня [atMs]. */
    private fun show(ctx: Context, entry: Entry, atMs: Long) {
        val title = entry.titleAt(atMs)
        val cover = if (entry.titles.isEmpty()) entry.cover else try {
            JSONObject(entry.cover).put("title", title).toString()
        } catch (_: Exception) {
            entry.cover
        }
        NotifChannel.showOrPlain(
            ctx, cover, title, entry.body, entry.tag, entry.id, entry.channel, entry.ongoing, entry.silent,
        )
    }

    /**
     * После перезагрузки будильников нет: ставим заново. Прошедший разовый
     * не показываем (как плагин уведомлений), ежедневный — на ближайший день.
     * Постоянную плашку показываем сразу, с сегодняшним числом. Зовётся не с
     * главного потока: показ качает картинки.
     */
    fun rearm(ctx: Context) {
        val now = System.currentTimeMillis()
        for (e in all(ctx)) {
            when {
                e.whenMs > now -> arm(ctx, e)
                e.daily -> schedule(ctx, e.copy(whenMs = nextDay(e.whenMs, now)))
                else -> prefs(ctx).edit().remove(e.id.toString()).apply()
            }
            if (showsAtBoot(e)) {
                try {
                    show(ctx, e, now)
                } catch (err: Exception) {
                    Log.w(TAG, "плашка после перезагрузки не встала: ${err.message}")
                }
            }
        }
    }
}

/** Срабатывание будильника: картинки качаются, поэтому в своём потоке. */
class NotifAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(NotifAlarm.EXTRA_ID, Int.MIN_VALUE)
        if (id == Int.MIN_VALUE) return
        val app = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                NotifAlarm.fire(app, id)
            } catch (e: Exception) {
                Log.w("NotifAlarm", "показ по расписанию сорвался: ${e.message}")
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/** Перезагрузка, обновление приложения, смена часов — расписание заново. */
class NotifAlarmBoot : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            -> {
                // Плашка «Дней вместе» встаёт сразу, а это картинки и диск —
                // не на главном потоке.
                val app = context.applicationContext
                val pending = goAsync()
                Thread {
                    try {
                        NotifAlarm.rearm(app)
                    } catch (e: Exception) {
                        Log.w("NotifAlarm", "расписание после перезагрузки сорвалось: ${e.message}")
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}
