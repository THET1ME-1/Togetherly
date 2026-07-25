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

            when (layout) {
                R.layout.tg_together_2x2 -> {
                    // Тёмная карточка primary: число и подпись поверх неё.
                    tint(R.id.bg, theme.primary)
                    setTextColor(R.id.days_value, theme.onPrimary)
                    setTextColor(R.id.days_label, theme.onPrimarySoft)
                    tint(R.id.avatar_me_bg, theme.avatarMine)
                    tint(R.id.avatar_partner_bg, theme.avatarPartner)
                    setTextColor(R.id.avatar_me, theme.onPrimaryContainer)
                    setTextColor(R.id.avatar_partner, theme.onTertiaryContainer)

                    setTextViewText(R.id.avatar_me, myInitial)
                    setTextViewText(R.id.avatar_partner, partnerInitial)

                    // Настоящие аватарки поверх кружка с инициалом. Инициал —
                    // фолбэк: остаётся, только если фото нет или не читается.
                    val myPhoto = WidgetImages.circularFromFile(myAvatarPath)
                    val partnerPhoto = WidgetImages.circularFromFile(partnerAvatarPath)
                    if (myPhoto != null) {
                        setImageViewBitmap(R.id.avatar_me_photo, myPhoto)
                        setViewVisibility(R.id.avatar_me_photo, View.VISIBLE)
                        setViewVisibility(R.id.avatar_me, View.INVISIBLE)
                    } else {
                        setViewVisibility(R.id.avatar_me_photo, View.GONE)
                        setViewVisibility(R.id.avatar_me, View.VISIBLE)
                    }
                    if (partnerPhoto != null) {
                        setImageViewBitmap(R.id.avatar_partner_photo, partnerPhoto)
                        setViewVisibility(R.id.avatar_partner_photo, View.VISIBLE)
                        setViewVisibility(R.id.avatar_partner, View.INVISIBLE)
                    } else {
                        setViewVisibility(R.id.avatar_partner_photo, View.GONE)
                        setViewVisibility(R.id.avatar_partner, View.VISIBLE)
                    }
                }

                R.layout.tg_together_4x2 -> {
                    // Светлая карточка primary-container.
                    tint(R.id.bg, theme.primaryContainer)
                    setTextColor(R.id.start_date, theme.onContainerSoft)
                    setTextColor(R.id.days_value, theme.onPrimaryContainer)
                    setTextColor(R.id.days_word, theme.onPrimaryContainer)
                    setTextColor(R.id.next_label, theme.onContainerSoft)
                    setTextColor(R.id.next_percent, theme.onContainerSoft)
                    tint(R.id.heart_icon, theme.primary)

                    if (startDate.isNotEmpty()) {
                        setTextViewText(R.id.start_date, startDate)
                    }
                    setTextViewText(R.id.days_word, daysWord(days))
                    val milestone = nextMilestone(days)
                    setTextViewText(
                        R.id.next_label,
                        "До ${milestone.label} — ${milestone.daysLeft} " +
                            daysWord(milestone.daysLeft),
                    )
                    setTextViewText(R.id.next_percent, "${milestone.percent}%")

                    // Полоса — картинка: перекрасить progressDrawable нельзя.
                    val density = context.resources.displayMetrics.density
                    val barWidthPx = (((minWidth - 28).coerceAtLeast(80)) * density).toInt()
                    val barHeightPx = (8 * density).toInt()
                    WidgetImages.progress(
                        barWidthPx,
                        barHeightPx,
                        milestone.percent,
                        theme.trackOnContainer,
                        theme.primary,
                    )?.let { setImageViewBitmap(R.id.progress, it) }
                }

                else -> {
                    // Светлая карточка surface с блоком primary внутри.
                    tint(R.id.bg, theme.surface)
                    tint(R.id.counter_bg, theme.primary)
                    tint(R.id.next_round_bg, theme.surfaceContainer)
                    tint(R.id.anniversary_bg, theme.tertiaryContainer)
                    tint(R.id.heart_icon, theme.primary)
                    setTextColor(R.id.couple_names, theme.onSurfaceVariant)
                    setTextColor(R.id.days_value, theme.onPrimary)
                    setTextColor(R.id.days_label, theme.onPrimarySoft)
                    setTextColor(R.id.months_value, theme.onPrimary)
                    setTextColor(R.id.months_label, theme.accentOnPrimary)
                    setTextColor(R.id.next_section, theme.outline)
                    setTextColor(R.id.next_round_title, theme.onSurface)
                    setTextColor(R.id.next_round_when, theme.onSurfaceVariant)
                    setTextColor(R.id.anniversary_title, theme.onTertiaryContainer)
                    setTextColor(R.id.anniversary_when, theme.tertiary)

                    if (names.isNotEmpty()) {
                        setTextViewText(R.id.couple_names, names.uppercase())
                    }
                    val months = days / 30
                    setTextViewText(R.id.months_value, months.toString())
                    setTextViewText(R.id.months_label, monthsWord(months))

                    val milestone = nextMilestone(days)
                    setTextViewText(
                        R.id.next_round_title,
                        "${milestone.value} ${daysWord(milestone.value)}",
                    )
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
