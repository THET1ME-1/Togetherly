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
open class TogetherWidgetProvider : HomeWidgetProvider() {

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
        val daysLabel = data.getString("${prefix}days_label", null).orEmpty()
        val milePercent = data.getString("${prefix}mile_percent", null)?.toIntOrNull() ?: 0
        val milePrevTitle = data.getString("${prefix}mile_prev_title", null).orEmpty()
        val milePrevSub = data.getString("${prefix}mile_prev_sub", null).orEmpty()
        val mileTodayTitle = data.getString("${prefix}mile_today_title", null).orEmpty()
        val mileTodaySub = data.getString("${prefix}mile_today_sub", null).orEmpty()
        val mileNextTitle = data.getString("${prefix}mile_next_title", null).orEmpty()
        val mileNextSub = data.getString("${prefix}mile_next_sub", null).orEmpty()
        val mileAnniTitle = data.getString("${prefix}mile_anni_title", null).orEmpty()
        val mileAnniSub = data.getString("${prefix}mile_anni_sub", null).orEmpty()
        val myAvatarPath = data.getString("${prefix}my_avatar_path", null)
        val partnerAvatarPath = data.getString("${prefix}partner_avatar_path", null)

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        // Ячейка на телефоне ≈ 70dp: 2×2 ≈ 140dp, 4×2 ≈ 300×140, 4×4 ≈ 300×300.
        // Если виджет поставлен из «своей» позиции списка, раскладка закреплена;
        // иначе подбираем по фактическому размеру после растягивания.
        val layout = forcedLayout ?: when {
            minWidth >= 200 && minHeight >= 200 -> R.layout.tg_together_4x4
            minWidth >= 200 -> R.layout.tg_together_4x2
            else -> R.layout.tg_together_2x2
        }

        // Разметка свёрстана под нижнюю границу вилки из гайдлайнов; на высокой
        // ячейке (лончер Xiaomi) кегли растягиваются, иначе карточка пустует.
        val baseDp = when (layout) {
            R.layout.tg_together_4x4 -> 185
            else -> 115
        }
        val scale = WidgetSizing.scale(minHeight, baseDp)
        // Цвета берём из активной темы приложения; пока её не прислали —
        // из хендофа (см. WidgetTheme.FALLBACK).
        val theme = WidgetTheme.from(data)

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
            val bigDp = when (layout) {
                R.layout.tg_together_2x2 -> 38f
                R.layout.tg_together_4x2 -> 36f
                else -> 46f
            }
            setTextViewTextSize(R.id.days_value, TypedValue.COMPLEX_UNIT_DIP, bigDp * scale)

            val density = context.resources.displayMetrics.density
            val cellW = minWidth.coerceAtLeast(120).toFloat()
            val cellH = minHeight.coerceAtLeast(90).toFloat()

            // Фон рисуем сами: растр точками поверх заливки. У RemoteViews нет
            // способа перекрасить обычный drawable, а тем в приложении двадцать.
            val onFill = layout != R.layout.tg_together_4x4
            val bgColor = if (onFill) theme.primary else theme.surface
            val dotColor = if (onFill) theme.blockOnPrimary else theme.trackOnSurface
            WidgetImages.halftone(cellW, cellH, density, bgColor, dotColor)
                ?.let { setImageViewBitmap(R.id.bg, it) }

            val ink = if (onFill) theme.onPrimary else theme.onSurface
            val inkSoft = if (onFill) theme.onPrimarySoft else theme.onSurfaceVariant
            val lineTrack = if (onFill) theme.blockOnPrimary else theme.trackOnSurface

            setTextColor(R.id.days_value, ink)
            tint(R.id.avatar_me_bg, theme.avatarMine)
            tint(R.id.avatar_partner_bg, theme.avatarPartner)
            setTextColor(R.id.avatar_me, theme.onPrimaryContainer)
            setTextColor(R.id.avatar_partner, theme.onTertiaryContainer)
            setTextViewText(R.id.avatar_me, myInitial)
            setTextViewText(R.id.avatar_partner, partnerInitial)

            val myPhoto = WidgetImages.circularFromFile(myAvatarPath)
            if (myPhoto != null) {
                setImageViewBitmap(R.id.avatar_me_photo, myPhoto)
                setViewVisibility(R.id.avatar_me_photo, View.VISIBLE)
                setViewVisibility(R.id.avatar_me, View.INVISIBLE)
            } else {
                setViewVisibility(R.id.avatar_me_photo, View.GONE)
                setViewVisibility(R.id.avatar_me, View.VISIBLE)
            }
            val partnerPhoto = WidgetImages.circularFromFile(partnerAvatarPath)
            if (partnerPhoto != null) {
                setImageViewBitmap(R.id.avatar_partner_photo, partnerPhoto)
                setViewVisibility(R.id.avatar_partner_photo, View.VISIBLE)
                setViewVisibility(R.id.avatar_partner, View.INVISIBLE)
            } else {
                setViewVisibility(R.id.avatar_partner_photo, View.GONE)
                setViewVisibility(R.id.avatar_partner, View.VISIBLE)
            }

            when (layout) {
                R.layout.tg_together_2x2 -> {
                    setTextColor(R.id.days_label, inkSoft)
                    setTextColor(R.id.mile_prev, inkSoft)
                    setTextColor(R.id.mile_next, inkSoft)
                    setTextViewText(R.id.days_label, daysLabel)
                    setTextViewText(R.id.mile_prev, milePrevTitle)
                    setTextViewText(R.id.mile_next, mileNextTitle)

                    WidgetImages.trackLine(
                        cellW - 28f, 22f, density, milePercent,
                        milePrevTitle.isNotEmpty(), false,
                        lineTrack, theme.onPrimary, theme.primary,
                    )?.let { setImageViewBitmap(R.id.track, it) }
                }

                R.layout.tg_together_4x2 -> {
                    setTextColor(R.id.days_word, inkSoft)
                    setTextColor(R.id.start_date, inkSoft)
                    setTextColor(R.id.mile_prev, inkSoft)
                    setTextColor(R.id.mile_next, ink)
                    setTextColor(R.id.mile_anni, inkSoft)

                    setTextViewText(R.id.days_word, daysLabel)
                    setTextViewText(R.id.start_date, startDate)
                    setTextViewText(R.id.mile_prev, milePrevTitle)
                    setTextViewText(
                        R.id.mile_next,
                        listOf(mileNextTitle, mileNextSub)
                            .filter { it.isNotEmpty() }
                            .joinToString(" · "),
                    )
                    setTextViewText(R.id.mile_anni, mileAnniTitle)

                    WidgetImages.trackLine(
                        cellW - 32f, 26f, density, milePercent,
                        milePrevTitle.isNotEmpty(), true,
                        lineTrack, theme.onPrimary, theme.primary,
                    )?.let { setImageViewBitmap(R.id.track, it) }
                }

                else -> {
                    setTextColor(R.id.couple_names, theme.onSurfaceVariant)
                    setTextColor(R.id.days_label, theme.onSurfaceVariant)
                    setTextColor(R.id.start_date, theme.outline)
                    setTextColor(R.id.prev_title, theme.onSurface)
                    setTextColor(R.id.prev_sub, theme.onSurfaceVariant)
                    setTextColor(R.id.today_title, theme.onSurface)
                    setTextColor(R.id.today_sub, theme.onSurfaceVariant)
                    setTextColor(R.id.next_round_title, theme.onSurface)
                    setTextColor(R.id.next_round_when, theme.onSurfaceVariant)
                    setTextColor(R.id.anniversary_title, theme.onSurface)
                    setTextColor(R.id.anniversary_when, theme.tertiary)

                    if (names.isNotEmpty()) setTextViewText(R.id.couple_names, names)
                    setTextViewText(R.id.days_label, daysLabel)
                    setTextViewText(R.id.start_date, startDate)
                    setTextViewText(R.id.prev_title, milePrevTitle)
                    setTextViewText(R.id.prev_sub, milePrevSub)
                    setTextViewText(R.id.today_title, mileTodayTitle)
                    setTextViewText(R.id.today_sub, mileTodaySub)
                    setTextViewText(R.id.next_round_title, mileNextTitle)
                    setTextViewText(R.id.next_round_when, mileNextSub)
                    setTextViewText(R.id.anniversary_title, mileAnniTitle)
                    setTextViewText(R.id.anniversary_when, mileAnniSub)

                    // Пара в первой сотне: пройденной вехи ещё нет, и строка
                    // «0 дней» читалась бы поломкой — прячем её целиком.
                    val hasPrev = milePrevTitle.isNotEmpty()
                    setViewVisibility(R.id.row_prev, if (hasPrev) View.VISIBLE else View.GONE)

                    // Высота ленты — ровно та, что осталась под строки; точки
                    // ставим в середину каждой.
                    val rows = if (hasPrev) 4 else 3
                    val stops = FloatArray(rows) { (it + 0.5f) / rows }
                    val trackH = (cellH - 150f).coerceAtLeast(60f)
                    WidgetImages.trackColumn(
                        24f, trackH, density, stops,
                        if (hasPrev) 1 else 0,
                        theme.trackOnSurface, theme.primary, theme.surface,
                        theme.tertiaryContainer,
                    )?.let { setImageViewBitmap(R.id.track, it) }
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }
}

/** «Вместе» в размере 2×2 — отдельная позиция в списке виджетов лончера. */
class TogetherWidget2x2Provider : TogetherWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_together_2x2
}

/** «Вместе» 4×2. */
class TogetherWidget4x2Provider : TogetherWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_together_4x2
}

/** «Вместе» 4×4. */
class TogetherWidget4x4Provider : TogetherWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_together_4x4
}
