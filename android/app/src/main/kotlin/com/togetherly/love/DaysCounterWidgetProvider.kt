package com.togetherly.love

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
                val totalDays = daysStr.toIntOrNull() ?: 0

                val startDate = widgetData.getString("start_date_label", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                // ── Гендер и выбор картинки пары ──
                val myGender = widgetData.getString("my_gender", "male") ?: "male"
                val partnerGender = widgetData.getString("partner_gender", "female") ?: "female"

                val coupleResName = when {
                    myGender == "female" && partnerGender == "female" -> "widget_couple_ff"
                    myGender == "male" && partnerGender == "male" -> "widget_couple_mm"
                    else -> "widget_couple_mf"
                }

                val coupleResId = context.resources.getIdentifier(coupleResName, "drawable", context.packageName)
                if (coupleResId != 0) {
                    setImageViewResource(R.id.couple_image, coupleResId)
                }

                // ── Расчёт лет ──
                val years = totalDays / 365
                val yearsText = when {
                    years % 10 == 1 && years % 100 != 11 -> "$years год уже ❤️"
                    years % 10 in 2..4 && (years % 100 < 10 || years % 100 >= 20) -> "$years года уже ❤️"
                    else -> "$years лет уже ❤️"
                }
                setTextViewText(R.id.years_label, yearsText)

                // ── Дни и дата ──
                setTextViewText(R.id.days_number, totalDays.toString())
                setTextViewText(R.id.days_label_text, "дней") // Или "Days" как в фото
                setTextViewText(R.id.start_date, startDate)

                // ── Совместимость (скрытые поля) ──
                setTextViewText(R.id.days_label, "")
                setTextViewText(R.id.couple_names, "")
                setTextViewText(R.id.love_emoji, "")
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
