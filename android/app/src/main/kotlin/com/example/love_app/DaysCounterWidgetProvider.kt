package com.example.love_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Счётчик дней вместе» — крупное число дней,
 * имена пары, эмодзи отношений, дата начала.
 */
class DaysCounterWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.days_counter_widget).apply {

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://home")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ── Данные ──
                val daysStr = widgetData.getString("days_count", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "0"
                val daysCount = daysStr.toIntOrNull() ?: 0

                val coupleNames = widgetData.getString("couple_names", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val emoji = widgetData.getString("relationship_emoji", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "❤️"
                val startDate = widgetData.getString("start_date_label", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                setTextViewText(R.id.days_number, daysCount.toString())
                setTextViewText(R.id.days_label, "дней вместе")
                setTextViewText(R.id.couple_names, coupleNames)
                setTextViewText(R.id.love_emoji, emoji)
                setTextViewText(
                    R.id.start_date,
                    if (startDate.isNotEmpty()) "с $startDate" else ""
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
