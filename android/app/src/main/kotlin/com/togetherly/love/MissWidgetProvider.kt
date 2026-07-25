package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Скучаю» — парный, интерактивный.
 *
 * Три размера из хендофа: 2×2 (карточка на tertiary-container с пилюлей),
 * 4×2 (счётчики обоих + кнопка отправки) и 4×1 (полоска на primary).
 * Раскладку выбираем по фактическому размеру ячейки.
 *
 * Тап отправляет «скучаю»: `HomeWidgetBackgroundIntent` будит Dart-колбэк
 * (`loveapp://miss`) даже когда процесс приложения мёртв, а тот пишет в
 * PocketBase и обновляет данные виджета. Локально сразу переводим карточку в
 * состояние «отправлено», чтобы палец получил отклик без ожидания сети.
 */
class MissWidgetProvider : HomeWidgetProvider() {

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
        val g = WidgetGroupHelper.getOrBind(context, "miss", widgetId)
        val prefix = if (g.isEmpty()) "" else "miss_${g}_"

        val partnerName = data.getString("${prefix}partner_name", null).orEmpty()
        val partnerInitial = data.getString("${prefix}partner_initial", null)
            .orEmpty().ifEmpty { partnerName.take(1).uppercase().ifEmpty { "?" } }
        val myCount = data.getString("${prefix}my_count", null)?.toIntOrNull() ?: 0
        val partnerCount = data.getString("${prefix}partner_count", null)?.toIntOrNull() ?: 0
        val lastTime = data.getString("${prefix}last_time", null).orEmpty()
        // Отправляли ли сегодня — состояние живёт до конца дня, как в хендофе.
        val sent = data.getString("${prefix}sent_today", null) == "1"

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        val layout = when {
            minWidth >= 250 && minHeight < 120 -> R.layout.tg_miss_4x1
            minWidth >= 250 -> R.layout.tg_miss_4x2
            else -> R.layout.tg_miss_2x2
        }

        val stateIcon = if (sent) R.drawable.ic_tg_check else R.drawable.ic_tg_heart
        val tapIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("loveapp://miss?group=$g"),
        )

        val views = RemoteViews(context.packageName, layout).apply {
            setImageViewResource(R.id.state_icon, stateIcon)

            when (layout) {
                R.layout.tg_miss_2x2 -> {
                    setTextViewText(
                        R.id.partner_name,
                        if (partnerName.isEmpty()) "Партнёру" else dativeName(partnerName),
                    )
                    setTextViewText(R.id.title, if (sent) "Отправлено" else "Скучаю")
                    setTextViewText(R.id.cta, if (sent) lastTime.ifEmpty { "сегодня" } else "Отправить")
                    setOnClickPendingIntent(R.id.widget_root, tapIntent)
                }

                R.layout.tg_miss_4x2 -> {
                    setTextViewText(R.id.my_count, myCount.toString())
                    setTextViewText(R.id.partner_count, partnerCount.toString())
                    setTextViewText(
                        R.id.partner_label,
                        partnerName.ifEmpty { "Партнёр" },
                    )
                    setTextViewText(
                        R.id.last_time,
                        when {
                            sent -> "только что"
                            lastTime.isNotEmpty() -> "последний раз в $lastTime"
                            else -> ""
                        },
                    )
                    // Отправляет кнопка, но по самой карточке открываем приложение.
                    setOnClickPendingIntent(R.id.send_button, tapIntent)
                    setOnClickPendingIntent(
                        R.id.widget_root,
                        HomeWidgetLaunchIntentCompat.home(context),
                    )
                }

                else -> {
                    setTextViewText(R.id.avatar, partnerInitial)
                    setTextViewText(R.id.title, if (sent) "Отправлено" else "Скучаю")
                    setTextViewText(
                        R.id.subtitle,
                        if (sent) {
                            "${partnerName.ifEmpty { "Партнёр" }} уже видит"
                        } else {
                            "один тап — и он узнает"
                        },
                    )
                    setOnClickPendingIntent(R.id.widget_root, tapIntent)
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }

    /** «Мише», «Ане» — дательный падеж для коротких русских имён. */
    private fun dativeName(name: String): String {
        val n = name.trim()
        if (n.isEmpty()) return "Партнёру"
        return when {
            n.endsWith("а", true) || n.endsWith("я", true) -> n.dropLast(1) + "е"
            n.endsWith("й", true) -> n.dropLast(1) + "ю"
            else -> n + "у"
        }
    }
}

/** Открытие приложения из виджета — вынесено, чтобы не плодить дубли. */
object HomeWidgetLaunchIntentCompat {
    fun home(context: Context) = es.antonborri.home_widget.HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("loveapp://home"),
    )
}
