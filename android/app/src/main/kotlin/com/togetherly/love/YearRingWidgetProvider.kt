package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Кольцо года» — круговой прогресс до следующей годовщины.
 *
 * Два размера из хендофа: 4×2 (кольцо слева, колонка со счётчиками справа) и
 * 2×2 (кольцо во всю карточку, число внутри). Карточка тёмная — заливка
 * `primary` активной темы, как у «Вместе» 2×2.
 *
 * Само кольцо рисуется картинкой: дуги RemoteViews не умеет, а круговой
 * `ProgressBar` не принимает цвет темы (`setColorStateList` — API 31, minSdk
 * у проекта 24). Данные кладёт Flutter (`home_widget`) ключами `ring_<gid>_*`.
 */
open class YearRingWidgetProvider : HomeWidgetProvider() {

    /** Раскладка, закреплённая за провайдером; null — выбирать по размеру. */
    protected open val forcedLayout: Int? = null

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
            "HomeWidgetPreferences", Context.MODE_PRIVATE,
        )
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetGroupHelper.clearBindings(context, "year_ring", appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "year_ring", widgetId)
        val prefix = if (g.isEmpty()) "" else "ring_${g}_"

        // Дни считаются здесь, а не берутся готовыми: иначе счётчик застывал
        // бы до следующего открытия приложения. Flutter кладёт только дату
        // начала и то, что сам по себе не меняется (воспоминания).
        val startMs = data.getString("${prefix}start_ms", null)?.toLongOrNull() ?: 0L
        val memories = data.getString("${prefix}memories", null)?.toIntOrNull() ?: 0
        val hasStart = startMs > 0L

        val m = if (hasStart) YearMath.from(startMs) else null
        val days = m?.daysTotal ?: 0
        val years = m?.yearsCompleted ?: 0
        val daysLeft = m?.daysToNextAnniversary ?: 0
        val months = m?.monthsCompleted ?: 0
        val anniversary = m?.let {
            YearMath.dayMonth(it.nextAnniversaryDay, it.nextAnniversaryMonth)
        }.orEmpty()

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = WidgetSizing.widthDp(options)
        val minHeight = WidgetSizing.heightDp(options)

        val layout = forcedLayout ?: if (minWidth >= 200) {
            R.layout.tg_ring_4x2
        } else {
            R.layout.tg_ring_2x2
        }
        val scale = WidgetSizing.scale(minHeight, 115)
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density
        val progress = m?.ringProgress ?: 0f

        val views = RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://history"),
                ),
            )

            tint(R.id.bg, theme.primary)
            setTextColor(R.id.empty_label, theme.onPrimarySoft)

            // Пара не завела дату начала — считать нечего, показываем просьбу.
            if (!hasStart) {
                setViewVisibility(R.id.empty_label, View.VISIBLE)
                setViewVisibility(R.id.content, View.GONE)
                return@apply
            }
            setViewVisibility(R.id.empty_label, View.GONE)
            setViewVisibility(R.id.content, View.VISIBLE)

            setTextColor(R.id.ring_days, theme.onPrimary)
            setTextColor(R.id.ring_days_word, theme.onPrimarySoft)
            setTextViewText(R.id.ring_days, days.toString())

            when (layout) {
                R.layout.tg_ring_4x2 -> {
                    setTextViewText(R.id.ring_days_word, WidgetWords.cap(WidgetWords.days(days)))
                    setTextViewTextSize(
                        R.id.ring_days, TypedValue.COMPLEX_UNIT_DIP, 22f * scale,
                    )
                    setTextViewTextSize(
                        R.id.ring_days_word, TypedValue.COMPLEX_UNIT_DIP, 9f * scale,
                    )

                    val ringDp = 80f * scale
                    WidgetImages.ring(
                        (ringDp * density).toInt(),
                        5f * scale * density,
                        progress,
                        theme.blockOnPrimary,
                        theme.accentOnPrimary,
                    )?.let { setImageViewBitmap(R.id.ring, it) }

                    setTextColor(R.id.year_label, theme.accentOnPrimary)
                    setTextColor(R.id.left_value, theme.onPrimary)
                    setTextColor(R.id.next_date, theme.onPrimarySoft)
                    tint(R.id.tile_left_bg, theme.blockOnPrimary)
                    tint(R.id.tile_right_bg, theme.blockOnPrimary)
                    setTextColor(R.id.tile_left_label, theme.accentOnPrimary)
                    setTextColor(R.id.tile_right_label, theme.accentOnPrimary)
                    setTextColor(R.id.tile_left_value, theme.onPrimary)
                    setTextColor(R.id.tile_right_value, theme.onPrimary)

                    setTextViewText(R.id.year_label, WidgetWords.yearOrdinal(years + 1))
                    setTextViewText(
                        R.id.left_value, "Ещё $daysLeft ${WidgetWords.days(daysLeft)}",
                    )
                    val nextYears = years + 1
                    setTextViewText(
                        R.id.next_date,
                        listOf(
                            "До $nextYears ${WidgetWords.yearsGenitive(nextYears)}",
                            anniversary,
                        ).filter { it.isNotEmpty() }.joinToString(" · "),
                    )
                    setTextViewText(R.id.tile_left_value, months.toString())
                    setTextViewText(R.id.tile_right_value, memories.toString())

                    setTextViewTextSize(
                        R.id.year_label, TypedValue.COMPLEX_UNIT_DIP, 9f * scale,
                    )
                    setTextViewTextSize(
                        R.id.left_value, TypedValue.COMPLEX_UNIT_DIP, 15f * scale,
                    )
                    setTextViewTextSize(
                        R.id.next_date, TypedValue.COMPLEX_UNIT_DIP, 9f * scale,
                    )
                    listOf(R.id.tile_left_label, R.id.tile_right_label).forEach {
                        setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_DIP, 8f * scale)
                    }
                    listOf(R.id.tile_left_value, R.id.tile_right_value).forEach {
                        setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_DIP, 14f * scale)
                    }
                }

                else -> {
                    setTextViewText(R.id.ring_days_word, "${WidgetWords.cap(WidgetWords.days(days))} вместе")
                    setTextViewTextSize(
                        R.id.ring_days, TypedValue.COMPLEX_UNIT_DIP, 26f * scale,
                    )
                    setTextViewTextSize(
                        R.id.ring_days_word, TypedValue.COMPLEX_UNIT_DIP, 9f * scale,
                    )

                    // Кольцо занимает карточку целиком, поэтому его сторона —
                    // меньшая сторона ячейки за вычетом полей разметки.
                    val sideDp = listOf(minWidth, minHeight)
                        .filter { it > 0 }
                        .minOrNull() ?: 110
                    WidgetImages.ring(
                        ((sideDp - 22).coerceAtLeast(60) * density).toInt(),
                        4f * scale * density,
                        progress,
                        theme.blockOnPrimary,
                        theme.accentOnPrimary,
                    )?.let { setImageViewBitmap(R.id.ring, it) }

                    setTextColor(R.id.next_label, theme.accentOnPrimary)
                    val nextYears = years + 1
                    setTextViewText(
                        R.id.next_label,
                        "До $nextYears ${WidgetWords.yearsGenitive(nextYears)} — $daysLeft",
                    )
                    setTextViewTextSize(
                        R.id.next_label, TypedValue.COMPLEX_UNIT_DIP, 8f * scale,
                    )
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }
}

/** «Кольцо года» 4×2 — отдельная позиция в списке лончера. */
class YearRingWidget4x2Provider : YearRingWidgetProvider() {
    override val forcedLayout = R.layout.tg_ring_4x2
}

/** «Кольцо года» 2×2. */
class YearRingWidget2x2Provider : YearRingWidgetProvider() {
    override val forcedLayout = R.layout.tg_ring_2x2
}
