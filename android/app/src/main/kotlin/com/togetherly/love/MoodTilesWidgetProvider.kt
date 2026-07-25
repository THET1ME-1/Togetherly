package com.togetherly.love

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Настроение» — парный, интерактивный.
 *
 * Два размера из хендофа: 2×2 (настроение обоих на сегодня плюс три кнопки,
 * которыми своё настроение отмечается прямо с рабочего стола) и 4×2 (неделя
 * двумя рядами столбиков).
 *
 * Тап по кнопке обрабатывается здесь же: сначала виджет показывает выбор,
 * потом будится Dart и пишет настроение в PocketBase. Ждать сеть до отклика
 * нельзя — кнопка выглядит мёртвой (так уже было со «Скучаю»).
 */
open class MoodTilesWidgetProvider : HomeWidgetProvider() {

    protected open val forcedLayout: Int? = null

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PICK) {
            super.onReceive(context, intent)
            return
        }

        val g = intent.getStringExtra(EXTRA_GROUP).orEmpty()
        val moodId = intent.getStringExtra(EXTRA_MOOD).orEmpty()
        if (moodId.isEmpty()) return

        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val prefix = if (g.isEmpty()) "" else "tgmood_${g}_"
        prefs.edit()
            .putString("${prefix}my_id", moodId)
            .putString("${prefix}my_label", localLabel(moodId))
            // Отметка «ждёт сервера»: если фоновый движок не поднимется,
            // приложение допишет настроение при следующем запуске.
            .putString("${prefix}pending_mood", moodId)
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        listOf(MoodTilesWidget2x2Provider::class.java, MoodTilesWidget4x2Provider::class.java)
            .forEach { cls ->
                manager.getAppWidgetIds(ComponentName(context, cls)).forEach { id ->
                    render(context, manager, id, prefs)
                }
            }

        try {
            HomeWidgetBackgroundIntent
                .getBroadcast(context, Uri.parse("loveapp://mood?group=$g&id=$moodId"))
                .send()
        } catch (e: Exception) {
            android.util.Log.w("MoodTilesWidget", "не удалось разбудить Dart: $e")
        }
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "tgmood", widgetId)
        val prefix = if (g.isEmpty()) "" else "tgmood_${g}_"

        val myLabel = data.getString("${prefix}my_label", null).orEmpty()
        val myId = data.getString("${prefix}my_id", null).orEmpty()
        val partnerLabel = data.getString("${prefix}partner_label", null).orEmpty()
        val partnerName = data.getString("${prefix}partner_name", null).orEmpty()
        val weekRaw = data.getString("${prefix}week", null).orEmpty()
        val matched = data.getString("${prefix}matched", null)?.toIntOrNull() ?: 0

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        val layout = forcedLayout ?: when {
            minWidth >= 200 -> R.layout.tg_mood_4x2
            else -> R.layout.tg_mood_2x2
        }
        val scale = WidgetSizing.scale(minHeight, 115)
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density

        val views = RemoteViews(context.packageName, layout).apply {
            tint(R.id.bg, theme.surface)
            setTextColor(R.id.header, theme.onSurfaceVariant)

            when (layout) {
                R.layout.tg_mood_2x2 -> {
                    setTextColor(R.id.my_line, theme.onSurface)
                    setTextColor(R.id.partner_line, theme.onSurface)
                    tint(R.id.my_dot, if (myLabel.isEmpty()) theme.outline else theme.primary)
                    tint(
                        R.id.partner_dot,
                        if (partnerLabel.isEmpty()) theme.outline else theme.tertiary,
                    )

                    setTextViewText(
                        R.id.my_line,
                        if (myLabel.isEmpty()) "Я · не отмечено" else "Я · $myLabel",
                    )
                    val pName = partnerName.ifEmpty { "Партнёр" }
                    setTextViewText(
                        R.id.partner_line,
                        if (partnerLabel.isEmpty()) "$pName · не отмечено"
                        else "$pName · $partnerLabel",
                    )
                    setTextViewTextSize(
                        R.id.my_line, TypedValue.COMPLEX_UNIT_DIP, 12f * scale)
                    setTextViewTextSize(
                        R.id.partner_line, TypedValue.COMPLEX_UNIT_DIP, 12f * scale)

                    // Выбранная кнопка получает контейнерный цвет, остальные —
                    // нейтральную заливку.
                    listOf(
                        Triple(MOOD_GOOD, R.id.pick_good_bg, R.id.pick_good_icon),
                        Triple(MOOD_OK, R.id.pick_ok_bg, R.id.pick_ok_icon),
                        Triple(MOOD_BAD, R.id.pick_bad_bg, R.id.pick_bad_icon),
                    ).forEach { (id, bgId, iconId) ->
                        val active = id == myId
                        tint(bgId, if (active) theme.primaryContainer else theme.surfaceContainer)
                        tint(iconId, if (active) theme.onPrimaryContainer else theme.onSurfaceVariant)
                    }

                    setOnClickPendingIntent(R.id.pick_good, pickIntent(context, widgetId, g, MOOD_GOOD))
                    setOnClickPendingIntent(R.id.pick_ok, pickIntent(context, widgetId, g, MOOD_OK))
                    setOnClickPendingIntent(R.id.pick_bad, pickIntent(context, widgetId, g, MOOD_BAD))
                }

                else -> {
                    setTextColor(R.id.matched, theme.outline)
                    listOf(
                        R.id.day_1, R.id.day_2, R.id.day_3, R.id.day_4,
                        R.id.day_5, R.id.day_6, R.id.day_7,
                    ).forEach { setTextColor(it, theme.outline) }

                    setTextViewText(
                        R.id.matched,
                        if (matched > 0) "совпало $matched из 7" else "",
                    )

                    val week = parseWeek(weekRaw)
                    val chartWidthPx = (((minWidth - 30).coerceAtLeast(120)) * density).toInt()
                    val chartHeightPx = (52 * density).toInt()
                    WidgetImages.moodWeek(
                        chartWidthPx,
                        chartHeightPx,
                        week,
                        theme.primary,
                        theme.tertiary,
                        theme.surfaceContainer,
                    )?.let { setImageViewBitmap(R.id.chart, it) }

                    setOnClickPendingIntent(
                        R.id.widget_root,
                        HomeWidgetLaunchIntentCompat.home(context),
                    )
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }

    private fun pickIntent(
        context: Context,
        widgetId: Int,
        group: String,
        moodId: String,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        // Свой requestCode на каждую кнопку — иначе система переиспользует
        // один PendingIntent и все три кнопки шлют одно и то же настроение.
        widgetId * 10 + moodId.hashCode().and(7),
        Intent(context, javaClass).apply {
            action = ACTION_PICK
            putExtra(EXTRA_GROUP, group)
            putExtra(EXTRA_MOOD, moodId)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** «58/46,72/78,…» → семь пар. Битый день превращается в «нет отметки». */
    private fun parseWeek(raw: String): List<Pair<Int, Int>> {
        if (raw.isBlank()) return List(7) { -1 to -1 }
        val days = raw.split(',').map { chunk ->
            val parts = chunk.split('/')
            val mine = parts.getOrNull(0)?.trim()?.toIntOrNull() ?: -1
            val partner = parts.getOrNull(1)?.trim()?.toIntOrNull() ?: -1
            mine to partner
        }
        return if (days.size >= 7) days.take(7) else days + List(7 - days.size) { -1 to -1 }
    }

    /** Подпись выбранного настроения до того, как ответит сервер. */
    private fun localLabel(moodId: String): String = when (moodId) {
        MOOD_GOOD -> "хорошо"
        MOOD_OK -> "обычно"
        MOOD_BAD -> "грустно"
        else -> ""
    }

    companion object {
        const val ACTION_PICK = "com.togetherly.love.action.MOOD_PICK"
        const val EXTRA_GROUP = "group"
        const val EXTRA_MOOD = "mood"

        // Идентификаторы из каталога настроений приложения.
        const val MOOD_GOOD = "happy"
        const val MOOD_OK = "no_emotion"
        const val MOOD_BAD = "sad"
    }
}

/** «Настроение» 2×2 — отдельная позиция в списке виджетов. */
class MoodTilesWidget2x2Provider : MoodTilesWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_mood_2x2
}

/** «Настроение» 4×2 — неделя. */
class MoodTilesWidget4x2Provider : MoodTilesWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_mood_4x2
}
