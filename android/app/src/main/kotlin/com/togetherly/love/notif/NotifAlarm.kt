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
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id).put("when", whenMs).put("cover", cover).put("title", title).put("body", body)
            .put("tag", tag).put("channel", channel).put("exact", exact).put("daily", daily)

        companion object {
            fun of(o: JSONObject) = Entry(
                id = o.optInt("id"), whenMs = o.optLong("when"), cover = o.optString("cover"),
                title = o.optString("title"), body = o.optString("body"), tag = o.optString("tag"),
                channel = o.optString("channel"), exact = o.optBoolean("exact"), daily = o.optBoolean("daily"),
            )
        }
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
        NotifChannel.showOrPlain(ctx, entry.cover, entry.title, entry.body, entry.tag, entry.id, entry.channel)
        if (entry.daily) {
            schedule(ctx, entry.copy(whenMs = nextDay(entry.whenMs, System.currentTimeMillis())))
        } else {
            prefs(ctx).edit().remove(id.toString()).apply()
        }
    }

    /**
     * После перезагрузки будильников нет: ставим заново. Прошедший разовый
     * не показываем (как плагин уведомлений), ежедневный — на ближайший день.
     */
    fun rearm(ctx: Context) {
        val now = System.currentTimeMillis()
        for (e in all(ctx)) {
            when {
                e.whenMs > now -> arm(ctx, e)
                e.daily -> schedule(ctx, e.copy(whenMs = nextDay(e.whenMs, now)))
                else -> prefs(ctx).edit().remove(e.id.toString()).apply()
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
            -> NotifAlarm.rearm(context.applicationContext)
        }
    }
}
