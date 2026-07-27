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
 * Виджет «Календарь лет» — сетка точек: точка равна месяцу, ряд равен году.
 *
 * Два размера из хендофа: 4×2 (крупное число дней, сетка и плитка обратного
 * отсчёта) и 2×2 (сетка сверху, число снизу). Карточка светлая — заливка
 * `surface` активной темы с волосяным контуром.
 *
 * Сетка приходит картинкой (`WidgetImages.monthsGrid`): семьдесят две
 * отдельные вью раздувают транзакцию RemoteViews до отказа лончера.
 * Данные кладёт Flutter ключами `grid_<gid>_*`.
 */
open class YearGridWidgetProvider : HomeWidgetProvider() {

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
        WidgetGroupHelper.clearBindings(context, "year_grid", appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "year_grid", widgetId)
        val prefix = if (g.isEmpty()) "" else "grid_${g}_"

        // Дни считаются здесь, а не берутся готовыми: иначе сетка застывала бы
        // до следующего открытия приложения (см. YearMath).
        val startMs = data.getString("${prefix}start_ms", null)?.toLongOrNull() ?: 0L
        val startDate = data.getString("${prefix}start_date", null).orEmpty()
        val hasStart = startMs > 0L

        val m = if (hasStart) YearMath.from(startMs) else null
        val days = m?.daysTotal ?: 0
        val years = m?.yearsCompleted ?: 0
        val monthsDone = m?.monthsCompleted ?: 0
        val daysIntoYear = m?.daysIntoYear ?: 0
        val daysLeft = m?.daysToNextAnniversary ?: 0

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = WidgetSizing.widthDp(options)
        val minHeight = WidgetSizing.heightDp(options)

        val layout = forcedLayout ?: if (minWidth >= 200) {
            R.layout.tg_grid_4x2
        } else {
            R.layout.tg_grid_2x2
        }
        val scale = WidgetSizing.scale(minHeight, 115)
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density

        // Сетка растёт шестилетиями: колонок всегда двенадцать, рядов —
        // столько, чтобы текущий месяц в неё попал. Точка при этом мельчает,
        // число колонок не меняется (правило хендофа).
        val rows = ((monthsDone / 72) + 1) * 6
        val dotDp = if (layout == R.layout.tg_grid_4x2) 4.5f else 4f
        val gapDp = if (layout == R.layout.tg_grid_4x2) 2.5f else 2f
        val shrink = 6f / rows

        val views = RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://history"),
                ),
            )

            tint(R.id.bg, theme.surface)
            tint(R.id.bg_stroke, theme.trackOnSurface)
            setTextColor(R.id.empty_label, theme.onSurfaceVariant)

            if (!hasStart) {
                setViewVisibility(R.id.empty_label, View.VISIBLE)
                setViewVisibility(R.id.content, View.GONE)
                return@apply
            }
            setViewVisibility(R.id.empty_label, View.GONE)
            setViewVisibility(R.id.content, View.VISIBLE)

            WidgetImages.monthsGrid(
                monthsDone,
                rows,
                12,
                dotDp * shrink * scale * density,
                gapDp * shrink * scale * density,
                theme.primary,
                theme.tertiary,
                theme.trackOnSurface,
            )?.let { setImageViewBitmap(R.id.grid, it) }

            setTextColor(R.id.days_value, theme.onSurface)
            setTextViewText(R.id.days_value, days.toString())

            when (layout) {
                R.layout.tg_grid_4x2 -> {
                    setTextColor(R.id.days_word, theme.onSurfaceVariant)
                    setTextColor(R.id.years_label, theme.primary)
                    setTextColor(R.id.start_date, theme.onSurfaceVariant)
                    tint(R.id.tile_bg, theme.surfaceContainer)
                    setTextColor(R.id.left_value, theme.primary)
                    setTextColor(R.id.left_label, theme.onSurfaceVariant)

                    setTextViewText(R.id.days_word, WidgetWords.cap(WidgetWords.days(days)))
                    setTextViewText(
                        R.id.years_label,
                        "$years ${WidgetWords.cap(WidgetWords.years(years))} " +
                            "$daysIntoYear ${WidgetWords.cap(WidgetWords.days(daysIntoYear))}",
                    )
                    if (startDate.isNotEmpty()) {
                        setTextViewText(R.id.start_date, startDate)
                    }
                    setTextViewText(R.id.left_value, daysLeft.toString())
                    val nextYears = years + 1
                    setTextViewText(
                        R.id.left_label,
                        "До $nextYears ${WidgetWords.yearsGenitive(nextYears)}",
                    )

                    setTextViewTextSize(
                        R.id.days_value, TypedValue.COMPLEX_UNIT_DIP, 30f * scale,
                    )
                    listOf(R.id.days_word, R.id.years_label, R.id.start_date).forEach {
                        setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_DIP, 9f * scale)
                    }
                    setTextViewTextSize(
                        R.id.left_value, TypedValue.COMPLEX_UNIT_DIP, 14f * scale,
                    )
                    setTextViewTextSize(
                        R.id.left_label, TypedValue.COMPLEX_UNIT_DIP, 8f * scale,
                    )
                }

                else -> {
                    setTextColor(R.id.days_word, theme.primary)
                    setTextColor(R.id.year_label, theme.onSurfaceVariant)

                    setTextViewText(R.id.days_word, "${WidgetWords.cap(WidgetWords.days(days))} вместе")
                    val nextYears = years + 1
                    setTextViewText(
                        R.id.year_label,
                        "$nextYears-й год · ещё $daysLeft",
                    )

                    setTextViewTextSize(
                        R.id.days_value, TypedValue.COMPLEX_UNIT_DIP, 26f * scale,
                    )
                    setTextViewTextSize(
                        R.id.days_word, TypedValue.COMPLEX_UNIT_DIP, 9f * scale,
                    )
                    setTextViewTextSize(
                        R.id.year_label, TypedValue.COMPLEX_UNIT_DIP, 8f * scale,
                    )
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }
}

/** «Календарь лет» 4×2 — отдельная позиция в списке лончера. */
class YearGridWidget4x2Provider : YearGridWidgetProvider() {
    override val forcedLayout = R.layout.tg_grid_4x2
}

/** «Календарь лет» 2×2. */
class YearGridWidget2x2Provider : YearGridWidgetProvider() {
    override val forcedLayout = R.layout.tg_grid_2x2
}
