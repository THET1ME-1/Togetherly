package com.example.love_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.abs

/**
 * Виджет «Таймер / Обратный отсчёт» — показывает выбранный таймер:
 * название, эмодзи, количество дней (прошло / осталось), дату.
 */
class TimerWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.timer_widget).apply {

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://home")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ── Данные ──
                val title = widgetData.getString("timer_title", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "Таймер"
                val daysStr = widgetData.getString("timer_days", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "0"
                val days = daysStr.toIntOrNull() ?: 0
                val emoji = widgetData.getString("timer_emoji", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "⏱"
                val isCountdown =
                    widgetData.getString("timer_is_countdown", "0") == "1"
                val date = widgetData.getString("timer_date", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                val daysAbs = abs(days)
                val daysLabel = if (isCountdown) "дней осталось" else "дней прошло"

                setTextViewText(R.id.timer_emoji, emoji)
                setTextViewText(R.id.timer_title, title)
                setTextViewText(R.id.timer_days_number, daysAbs.toString())
                setTextViewText(R.id.timer_days_label, daysLabel)
                setTextViewText(R.id.timer_date, date)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
