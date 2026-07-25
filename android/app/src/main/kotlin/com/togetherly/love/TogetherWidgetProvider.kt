package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Виджет «Вместе» — счётчик дней и следующая круглая дата.
 *
 * Три размера из хендофа: 2×2 (тёмный primary с аватарами), 4×2 (светлый
 * контейнер с прогрессом до годовщины) и 4×4 (крупный блок + список ближайших
 * дат). Раскладка выбирается по фактическому размеру ячейки — Android отдаёт
 * его в `OPTION_APPWIDGET_MIN_WIDTH/HEIGHT`.
 *
 * Данные кладёт Flutter (`home_widget`) ключами `together_<groupId>_*`.
 */
class TogetherWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            render(context, appWidgetManager, widgetId, widgetData)
        }
    }

    /** Пользователь потянул виджет за край — перерисовываем под новый размер. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences(
            "HomeWidgetPreferences", Context.MODE_PRIVATE
        )
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "together", widgetId)
        val prefix = if (g.isEmpty()) "" else "together_${g}_"

        val days = data.getString("${prefix}days", null)?.toIntOrNull() ?: 0
        val startDate = data.getString("${prefix}start_date", null).orEmpty()
        val myInitial = data.getString("${prefix}my_initial", null).orEmpty().ifEmpty { "?" }
        val partnerInitial =
            data.getString("${prefix}partner_initial", null).orEmpty().ifEmpty { "?" }
        val names = data.getString("${prefix}names", null).orEmpty()
        val anniversary = data.getString("${prefix}anniversary", null).orEmpty()

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        // Пороги в dp: одна ячейка ≈ 70dp. Широкий и высокий — 4×4, широкий и
        // низкий — 4×2, остальное — 2×2.
        val layout = when {
            minWidth >= 250 && minHeight >= 250 -> R.layout.tg_together_4x4
            minWidth >= 250 -> R.layout.tg_together_4x2
            else -> R.layout.tg_together_2x2
        }

        val views = RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://home"),
                ),
            )
            setTextViewText(R.id.days_value, days.toString())

            when (layout) {
                R.layout.tg_together_2x2 -> {
                    setTextViewText(R.id.avatar_me, myInitial)
                    setTextViewText(R.id.avatar_partner, partnerInitial)
                }

                R.layout.tg_together_4x2 -> {
                    if (startDate.isNotEmpty()) {
                        setTextViewText(R.id.start_date, startDate)
                    }
                    val milestone = nextMilestone(days)
                    setTextViewText(
                        R.id.next_label,
                        "До ${milestone.label} — ${milestone.daysLeft} дней",
                    )
                    setTextViewText(R.id.next_percent, "${milestone.percent}%")
                    setProgressBar(R.id.progress, 100, milestone.percent, false)
                }

                else -> {
                    if (names.isNotEmpty()) {
                        setTextViewText(R.id.couple_names, names.uppercase())
                    }
                    val months = days / 30
                    setTextViewText(R.id.months_value, months.toString())
                    setTextViewText(R.id.months_label, monthsWord(months))

                    val milestone = nextMilestone(days)
                    setTextViewText(R.id.next_round_title, "${milestone.value} дней")
                    setTextViewText(
                        R.id.next_round_when,
                        "через ${milestone.daysLeft} ${daysWord(milestone.daysLeft)}",
                    )

                    val years = max(1, days / 365 + 1)
                    setTextViewText(R.id.anniversary_title, "$years ${yearsWord(years)}")
                    if (anniversary.isNotEmpty()) {
                        setTextViewText(R.id.anniversary_when, anniversary)
                    }
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }

    /** Ближайшая круглая дата: сотни дней и годовщины, что раньше — то и берём. */
    private fun nextMilestone(days: Int): Milestone {
        val nextHundred = ((days / 100) + 1) * 100
        val nextYear = ((days / 365) + 1) * 365
        val target = if (nextHundred <= nextYear) nextHundred else nextYear
        val prev = if (nextHundred <= nextYear) target - 100 else target - 365
        val span = (target - prev).coerceAtLeast(1)
        val percent = (((days - prev).toFloat() / span) * 100).roundToInt().coerceIn(0, 100)
        val label = if (target % 365 == 0) "года" else "$target дней"
        return Milestone(target, target - days, percent, label)
    }

    private data class Milestone(
        val value: Int,
        val daysLeft: Int,
        val percent: Int,
        val label: String,
    )

    private fun daysWord(n: Int): String {
        val a = n % 100
        val b = n % 10
        return when {
            a in 11..19 -> "дней"
            b == 1 -> "день"
            b in 2..4 -> "дня"
            else -> "дней"
        }
    }

    private fun monthsWord(n: Int): String {
        val a = n % 100
        val b = n % 10
        return when {
            a in 11..19 -> "месяцев"
            b == 1 -> "месяц"
            b in 2..4 -> "месяца"
            else -> "месяцев"
        }
    }

    private fun yearsWord(n: Int): String {
        val a = n % 100
        val b = n % 10
        return when {
            a in 11..19 -> "лет"
            b == 1 -> "год"
            b in 2..4 -> "года"
            else -> "лет"
        }
    }
}
