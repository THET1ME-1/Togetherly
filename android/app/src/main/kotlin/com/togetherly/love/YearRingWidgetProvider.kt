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
 * Виджет «Кольцо года» — обратный отсчёт до следующей годовщины.
 *
 * Раскладка «Отсчёт» (макет 14.09.2026) одна на Android, iPhone и превью в
 * каталоге: 4×2 — кольцо с числом дней и меткой сегодняшнего дня, справа
 * сколько осталось до годовщины, дата и под чертой месяцы с воспоминаниями;
 * 2×2 — кольцо и строка под ним. Числа и правила подгонки текста живут в
 * `lib/models/year_ring_spec.dart`, здесь они повторены и сверяются тестом
 * `test/models/year_ring_spec_test.dart`.
 *
 * Кольцо и фон рисуются картинками (`WidgetImages.yearRing`, `ringBackdrop`):
 * дуг и градиентов в цвет темы RemoteViews не умеет. Подписи красятся цветом
 * надписи темы с прозрачностью, а не светлым акцентом: тот на заливке давал
 * контраст 1,4 и сливался с фоном. Данные кладёт Flutter (`home_widget`)
 * ключами `ring_<gid>_*`.
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
        val daysLeft = m?.daysToNextAnniversary ?: 0
        val months = m?.monthsCompleted ?: 0
        val anniversary = m?.let {
            YearMath.dayMonth(it.nextAnniversaryDay, it.nextAnniversaryMonth)
        }.orEmpty()

        val options = manager.getAppWidgetOptions(widgetId)
        val widthDp = WidgetSizing.widthDp(options)
        val heightDp = WidgetSizing.heightDp(options)

        val layout = forcedLayout ?: if (widthDp >= 200) {
            R.layout.tg_ring_4x2
        } else {
            R.layout.tg_ring_2x2
        }
        val small = layout == R.layout.tg_ring_2x2
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density
        val progress = m?.ringProgress ?: 0f

        // Пока лончер не сообщил размер, берём ячейку из макета.
        val w = (if (widthDp > 0) widthDp else if (small) 158 else 338).toFloat()
        val h = (if (heightDp > 0) heightDp else 158).toFloat()
        val px = density

        val on = theme.onPrimary
        val soft = WidgetImages.alpha(on, SOFT_ALPHA)

        val views = RemoteViews(context.packageName, layout).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://history"),
                ),
            )
            setTextColor(R.id.empty_label, soft)

            if (small) {
                renderSmall(this, w, h, px, theme, soft, progress, days, daysLeft)
            } else {
                renderMedium(
                    this, w, h, px, theme, soft, progress,
                    days, daysLeft, months, memories, anniversary,
                )
            }

            // Пара не завела дату начала — считать нечего, показываем просьбу.
            if (!hasStart) {
                setViewVisibility(R.id.empty_label, View.VISIBLE)
                setViewVisibility(R.id.content, View.GONE)
                return@apply
            }
            setViewVisibility(R.id.empty_label, View.GONE)
            setViewVisibility(R.id.content, View.VISIBLE)
        }

        manager.updateAppWidget(widgetId, views)
    }

    /**
     * 4×2 «Отсчёт»: кольцо слева, справа до годовщины, дата и под чертой
     * месяцы с воспоминаниями. Размеры — из `lib/models/year_ring_spec.dart`
     * в точках ячейки 338×158, умноженные на [k] под фактическую ячейку.
     */
    private fun renderMedium(
        v: RemoteViews,
        w: Float,
        h: Float,
        px: Float,
        theme: WidgetTheme,
        soft: Int,
        progress: Float,
        days: Int,
        daysLeft: Int,
        months: Int,
        memories: Int,
        anniversary: String,
    ) = with(v) {
        val k = minOf(h / 158f, w / 338f).coerceIn(0.7f, 1.5f)
        val ring = ringDp(minOf(128f * k, h - 16f), px)
        val stroke = 10f * k
        val padL = 14f * k
        val padR = 16f * k
        val gap = 16f * k
        val right = w - padL - padR - gap - ring
        val on = theme.onPrimary

        // Фон со свечением у конца дуги.
        val r = (ring - stroke) / 2f
        val cx = padL + ring / 2f
        val cy = h / 2f
        val (gx, gy) = arcEnd(cx, cy, r, progress)
        WidgetImages.ringBackdrop(
            w, h, backdropPxPerDp(w, h), theme.primary, on, theme.tertiaryContainer,
            gx, gy, arcs = true,
        )?.let { setImageViewBitmap(R.id.bg, it) }
        WidgetImages.yearRing(
            ring, stroke, px, progress,
            WidgetImages.alpha(on, TRACK_ALPHA), on, theme.primary,
        )?.let { setImageViewBitmap(R.id.ring, it) }

        setViewPadding(R.id.content, dp(padL, px), 0, dp(padR, px), 0)
        setViewPadding(R.id.info, dp(gap, px), 0, 0, 0)

        val inner = ring - 2 * stroke
        val number = days.toString()
        setTextViewText(R.id.ring_days, number)
        setTextColor(R.id.ring_days, on)
        size(R.id.ring_days, numberSize(inner, number.length, 36f * k))
        val caption = "${WidgetWords.cap(WidgetWords.days(days))} вместе"
        setTextViewText(R.id.ring_days_word, caption)
        setTextColor(R.id.ring_days_word, soft)
        size(R.id.ring_days_word, fitText(11.5f * k, caption.length, inner * 0.86f))
        setViewPadding(R.id.ring_days_word, 0, dp(3f * k, px), 0, 0)

        val eyebrow = "До годовщины"
        setTextViewText(R.id.year_label, eyebrow)
        setTextColor(R.id.year_label, soft)
        size(R.id.year_label, fitText(maxOf(11f * k, 9f), eyebrow.length, right))

        val leftNum = daysLeft.toString()
        val leftWord = WidgetWords.days(daysLeft)
        // Число и слово в 0.375 его кегля делят строку, между ними 6 точек.
        val countSize = minOf(
            40f * k,
            (right - 6f * k) / (leftNum.length * DIGIT_EM + leftWord.length * LETTER_EM * 0.375f),
        )
        setTextViewText(R.id.left_value, leftNum)
        setTextColor(R.id.left_value, on)
        size(R.id.left_value, countSize)
        setTextViewText(R.id.left_word, leftWord)
        setTextColor(R.id.left_word, on)
        size(R.id.left_word, countSize * 0.375f)
        setViewPadding(R.id.left_word, dp(6f * k, px), 0, 0, 0)

        val date = listOf("Годовщина", anniversary).filter { it.isNotEmpty() }.joinToString(" ")
        setTextViewText(R.id.next_date, date)
        setTextColor(R.id.next_date, soft)
        size(R.id.next_date, fitText(maxOf(12f * k, 9.5f), date.length, right))
        setViewPadding(R.id.next_date, 0, dp(2f * k, px), 0, 0)

        tint(R.id.divider, WidgetImages.alpha(on, HAIRLINE_ALPHA))
        setViewPadding(R.id.divider_box, 0, dp(10f * k, px), 0, dp(8f * k, px))

        val monthsWord = "мес."
        val memoriesWord = WidgetWords.memories(memories)
        val stats = "$months $monthsWord    $memories $memoriesWord"
        val statsSize = fitText(maxOf(12.5f * k, 9.5f), stats.length, right)
        setTextViewText(R.id.stat_months_value, months.toString())
        setTextViewText(R.id.stat_months_word, monthsWord)
        setTextViewText(R.id.stat_memories_value, memories.toString())
        setTextViewText(R.id.stat_memories_word, memoriesWord)
        listOf(R.id.stat_months_value, R.id.stat_memories_value).forEach {
            setTextColor(it, on)
            size(it, statsSize)
        }
        listOf(R.id.stat_months_word, R.id.stat_memories_word).forEach {
            setTextColor(it, soft)
            size(it, statsSize)
            setViewPadding(it, dp(3f * k, px), 0, 0, 0)
        }
        setViewPadding(R.id.stat_memories_value, dp(16f * k, px), 0, 0, 0)
    }

    /** 2×2: кольцо сверху, под ним сколько осталось до годовщины. */
    private fun renderSmall(
        v: RemoteViews,
        w: Float,
        h: Float,
        px: Float,
        theme: WidgetTheme,
        soft: Int,
        progress: Float,
        days: Int,
        daysLeft: Int,
    ) = with(v) {
        val k = (minOf(w, h) / 158f).coerceIn(0.7f, 1.6f)
        val ring = ringDp(112f * k, px)
        val stroke = 10f * k
        val on = theme.onPrimary
        val line = "Ещё $daysLeft ${WidgetWords.days(daysLeft)}"
        val lineSize = fitText(maxOf(11.5f * k, 9.5f), line.length, w - 24f * k)
        val lineGap = 9f * k

        // Кольцо и строка стоят блоком по центру ячейки.
        val block = ring + lineGap + lineSize * 1.2f
        val cy = (h - block) / 2f + ring / 2f
        val r = (ring - stroke) / 2f
        val (gx, gy) = arcEnd(w / 2f, cy, r, progress)
        WidgetImages.ringBackdrop(
            w, h, backdropPxPerDp(w, h), theme.primary, on, theme.tertiaryContainer,
            gx, gy, arcs = false,
        )?.let { setImageViewBitmap(R.id.bg, it) }
        WidgetImages.yearRing(
            ring, stroke, px, progress,
            WidgetImages.alpha(on, TRACK_ALPHA), on, theme.primary,
        )?.let { setImageViewBitmap(R.id.ring, it) }

        val inner = ring - 2 * stroke
        val number = days.toString()
        setTextViewText(R.id.ring_days, number)
        setTextColor(R.id.ring_days, on)
        size(R.id.ring_days, numberSize(inner, number.length, 34f * k))
        val caption = WidgetWords.cap(WidgetWords.days(days))
        setTextViewText(R.id.ring_days_word, caption)
        setTextColor(R.id.ring_days_word, soft)
        size(R.id.ring_days_word, fitText(11f * k, caption.length, inner * 0.86f))
        setViewPadding(R.id.ring_days_word, 0, dp(3f * k, px), 0, 0)

        setTextViewText(R.id.next_label, line)
        setTextColor(R.id.next_label, on)
        size(R.id.next_label, lineSize)
        setViewPadding(R.id.next_label, 0, dp(lineGap, px), 0, 0)
    }

    private fun RemoteViews.size(id: Int, dp: Float) =
        setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, dp)

    private fun dp(value: Float, px: Float): Int = (value * px).toInt()

    /**
     * Сторона кольца, которую реально покажет лончер. Картинка рисуется в
     * экранной плотности: `Bitmap.density` лончер не учитывает и кладёт её
     * пиксель в пиксель (на эмуляторе кольцо 122 dp выходило 96). Сторона
     * ограничена 380 пикселями — фон и кольцо едут одной транзакцией, — и
     * кегли дальше считаются от того, что поместилось.
     */
    private fun ringDp(wantedDp: Float, px: Float): Float =
        minOf(wantedDp * px, MAX_RING_PX) / px

    /** Фон мягкий и растягивается без потерь: не больше 60 тысяч пикселей. */
    private fun backdropPxPerDp(w: Float, h: Float): Float =
        minOf(1f, kotlin.math.sqrt(MAX_BACKDROP_PX / (w * h)))

    private fun arcEnd(cx: Float, cy: Float, r: Float, progress: Float): Pair<Float, Float> {
        val a = -Math.PI / 2 + progress.coerceIn(0f, 1f) * 2 * Math.PI
        return Pair(cx + r * Math.cos(a).toFloat(), cy + r * Math.sin(a).toFloat())
    }

    private companion object {
        // Правила подгонки общие с iPhone и превью: lib/models/year_ring_spec.dart.
        const val NUMBER_SHARE = 0.74f
        const val DIGIT_EM = 0.58f
        const val LETTER_EM = 0.56f
        const val SOFT_ALPHA = 0.90f
        const val TRACK_ALPHA = 0.22f
        const val HAIRLINE_ALPHA = 0.28f
        const val MAX_RING_PX = 380f
        const val MAX_BACKDROP_PX = 60_000f

        /** Кегль числа: помещается во внутренний диаметр при любом числе цифр. */
        fun numberSize(inner: Float, digits: Int, max: Float): Float =
            minOf(max, inner * NUMBER_SHARE / (maxOf(digits, 1) * DIGIT_EM))

        /** Кегль строки: базовый, пока помещается в [width], дальше меньше. */
        fun fitText(base: Float, chars: Int, width: Float): Float =
            if (chars <= 0) base else minOf(base, width / (chars * LETTER_EM))
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
