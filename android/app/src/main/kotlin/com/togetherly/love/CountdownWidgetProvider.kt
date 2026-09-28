package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «До встречи» — обратный отсчёт до ближайшего события пары.
 *
 * Два размера из хендофа: 2×2 (название и крупное число дней) и 4×2 (дни,
 * часы, минуты плюс полоса пройденного пути).
 *
 * Секунды не тикают: лончер обновляет виджет раз в полчаса, и бегущие
 * секунды показывали бы неправду. Остаток считается ЗДЕСЬ по часам телефона
 * из списка событий `tgcd_<g>_events` — правило `countdownAt` в
 * `lib/models/countdown_widget.dart`. Пока приходили готовые числа, их писал
 * только экран «Виджеты», и виджет застывал (обращение 197).
 */
open class CountdownWidgetProvider : HomeWidgetProvider() {

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

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "tgcd", widgetId)
        val prefix = if (g.isEmpty()) "" else "tgcd_${g}_"

        var title = data.getString("${prefix}title", null).orEmpty()
        var dateLabel = data.getString("${prefix}date", null).orEmpty()
        var days = data.getString("${prefix}days", null)?.toIntOrNull() ?: 0
        var hours = data.getString("${prefix}hours", null)?.toIntOrNull() ?: 0
        var minutes = data.getString("${prefix}minutes", null)?.toIntOrNull() ?: 0
        var percent = data.getString("${prefix}percent", null)?.toIntOrNull() ?: 0

        val eventsRaw = data.getString("${prefix}events", null)
        if (eventsRaw != null) {
            val fromMs = data.getString("${prefix}from_ms", null)?.toLongOrNull() ?: 0L
            val tick = tick(eventsRaw, System.currentTimeMillis(), fromMs)
            title = tick?.title.orEmpty()
            dateLabel = tick?.date.orEmpty()
            days = tick?.days ?: 0
            hours = tick?.hours ?: 0
            minutes = tick?.minutes ?: 0
            percent = tick?.percent ?: 0
        }

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        val layout = forcedLayout ?: when {
            minWidth >= 200 -> R.layout.tg_countdown_4x2
            else -> R.layout.tg_countdown_2x2
        }
        val scale = WidgetSizing.scale(minHeight, 115)
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density

        val views = RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://home"),
                ),
            )
            setTextViewText(
                R.id.event_title,
                title.ifEmpty { "Нет ближайшего события" },
            )

            when (layout) {
                R.layout.tg_countdown_2x2 -> {
                    // Карточка на tertiary-container, как в хендофе.
                    tint(R.id.bg, theme.tertiaryContainer)
                    tint(R.id.event_icon, theme.tertiary)
                    setTextColor(R.id.event_title, theme.tertiary)
                    setTextColor(R.id.days_value, theme.onTertiaryContainer)
                    setTextColor(R.id.days_label, theme.onTertiaryContainer)

                    setTextViewText(R.id.days_value, days.toString())
                    setTextViewText(R.id.days_label, "${daysWord(days)} до встречи")
                    setTextViewTextSize(
                        R.id.days_value, TypedValue.COMPLEX_UNIT_DIP, 40f * scale)
                }

                else -> {
                    tint(R.id.bg, theme.surface)
                    tint(R.id.date_chip_bg, theme.tertiaryContainer)
                    tint(R.id.days_tile_bg, theme.primaryContainer)
                    tint(R.id.hours_tile_bg, theme.surfaceContainer)
                    tint(R.id.minutes_tile_bg, theme.surfaceContainer)
                    setTextColor(R.id.event_title, theme.onSurface)
                    setTextColor(R.id.date_chip, theme.onTertiaryContainer)
                    setTextColor(R.id.days_value, theme.onPrimaryContainer)
                    setTextColor(R.id.days_label, theme.onContainerSoft)
                    setTextColor(R.id.hours_value, theme.onSurface)
                    setTextColor(R.id.hours_label, theme.onSurfaceVariant)
                    setTextColor(R.id.minutes_value, theme.onSurface)
                    setTextColor(R.id.minutes_label, theme.onSurfaceVariant)

                    setTextViewText(R.id.date_chip, dateLabel)
                    setTextViewText(R.id.days_value, days.toString())
                    setTextViewText(R.id.days_label, daysWord(days))
                    setTextViewText(R.id.hours_value, hours.toString())
                    setTextViewText(R.id.hours_label, hoursWord(hours))
                    setTextViewText(R.id.minutes_value, minutes.toString())
                    setTextViewText(R.id.minutes_label, minutesWord(minutes))

                    val barWidthPx = (((minWidth - 30).coerceAtLeast(80)) * density).toInt()
                    val barHeightPx = (8 * density).toInt()
                    WidgetImages.progress(
                        barWidthPx,
                        barHeightPx,
                        percent,
                        theme.trackOnSurface,
                        theme.primary,
                    )?.let { setImageViewBitmap(R.id.progress, it) }
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }

    private data class Tick(
        val title: String,
        val date: String,
        val days: Int,
        val hours: Int,
        val minutes: Int,
        val percent: Int,
    )

    /** Остаток до первого ненаступившего события; null — все прошли. */
    private fun tick(raw: String, nowMs: Long, fromMs: Long): Tick? {
        var at = Long.MAX_VALUE
        var title = ""
        var date = ""
        try {
            val arr = org.json.JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val t = o.optLong("at", 0L)
                if (t > nowMs && t < at) {
                    at = t
                    title = o.optString("t", "")
                    date = o.optString("d", "")
                }
            }
        } catch (_: Exception) {
            return null
        }
        if (at == Long.MAX_VALUE) return null
        val leftMin = (at - nowMs) / 60000L
        val dayMin = 24L * 60L
        val from = if (fromMs in 1 until at) fromMs else at - 30L * dayMin * 60000L
        val start = if (from > nowMs) nowMs else from
        val total = at - start
        val passed = nowMs - start
        val percent = if (total <= 0) 100
        else Math.round(passed * 100.0 / total).toInt().coerceIn(0, 100)
        return Tick(
            title = title,
            date = date,
            days = (leftMin / dayMin).toInt(),
            hours = ((leftMin % dayMin) / 60L).toInt(),
            minutes = (leftMin % 60L).toInt(),
            percent = percent,
        )
    }

    private fun daysWord(n: Int): String = plural(n, "день", "дня", "дней")
    private fun hoursWord(n: Int): String = plural(n, "час", "часа", "часов")
    private fun minutesWord(n: Int): String = plural(n, "минута", "минуты", "минут")

    private fun plural(n: Int, one: String, few: String, many: String): String {
        val a = n % 100
        val b = n % 10
        return when {
            a in 11..19 -> many
            b == 1 -> one
            b in 2..4 -> few
            else -> many
        }
    }
}

/** «До встречи» 2×2 — отдельная позиция в списке виджетов. */
class CountdownWidget2x2Provider : CountdownWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_countdown_2x2
}

/** «До встречи» 4×2 — дни, часы и минуты. */
class CountdownWidget4x2Provider : CountdownWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_countdown_4x2
}
