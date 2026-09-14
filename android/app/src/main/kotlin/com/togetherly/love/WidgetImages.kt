package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.util.DisplayMetrics
import android.widget.RemoteViews

/**
 * Картинки для виджетов рабочего стола.
 *
 * Тот же приём, что в `DaysCounterWidgetProvider`, но вынесенный наружу:
 * аватары понадобились и виджету «Вместе». RemoteViews не умеет обрезать
 * ImageView по кругу, поэтому круг вырезаем сами и отдаём готовый bitmap.
 */
/**
 * Красит подложку виджета в цвет темы.
 *
 * Заливки лежат в разметке как `ImageView` с нейтральной белой фигурой:
 * обычный `background` из RemoteViews перекрасить нечем, а `setBackgroundColor`
 * съел бы скругления. `setColorFilter` есть на всех поддерживаемых версиях,
 * в отличие от `setColorStateList` (API 31).
 */
fun RemoteViews.tint(viewId: Int, color: Int) {
    setInt(viewId, "setColorFilter", color)
}

object WidgetImages {

    /**
     * Кадрирует bitmap в круг: центр-кроп до квадрата плюс круглая маска.
     * Возвращает ARGB_8888 с прозрачными углами — годится для
     * `setImageViewBitmap`. null, если исходника нет или он вырожденный.
     */
    fun circular(src: Bitmap?): Bitmap? {
        if (src == null) return null
        val size = minOf(src.width, src.height)
        if (size <= 0) return null
        val square = try {
            Bitmap.createBitmap(
                src,
                (src.width - size) / 2,
                (src.height - size) / 2,
                size,
                size,
            )
        } catch (e: Exception) {
            return null
        }
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val paint = Paint().apply {
            isAntiAlias = true
            shader = BitmapShader(square, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val r = size / 2f
        Canvas(output).drawCircle(r, r, r, paint)
        return output
    }

    /** Круглый аватар из файла: путь → уменьшенный bitmap → круг. */
    fun circularFromFile(path: String?, sizePx: Int = 160): Bitmap? =
        circular(PhotoDayWidgetProvider.loadScaledBitmapStatic(path, sizePx))

    /**
     * Неделя настроений: семь пар столбиков, мой цвет [mineColor], партнёра —
     * [partnerColor]. Значения в процентах высоты, отрицательное — день без
     * отметки, столбик не рисуется.
     *
     * Картинкой, а не четырнадцатью View: у RemoteViews нельзя менять ни
     * высоту, ни вес детей, а столбики целиком зависят от данных.
     */
    fun moodWeek(
        widthPx: Int,
        heightPx: Int,
        week: List<Pair<Int, Int>>,
        mineColor: Int,
        partnerColor: Int,
        emptyColor: Int,
    ): Bitmap? {
        if (widthPx <= 0 || heightPx <= 0 || week.isEmpty()) return null
        val output = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply { isAntiAlias = true }

        val dayGap = widthPx * 0.022f      // между днями
        val barGap = widthPx * 0.008f      // между двумя полосами одного дня
        val dayWidth = (widthPx - dayGap * (week.size - 1)) / week.size
        val barWidth = (dayWidth - barGap) / 2f
        val radius = barWidth / 2.4f
        // Совсем короткий столбик выглядит грязью, поэтому у него есть пол.
        val minBar = heightPx * 0.12f

        week.forEachIndexed { i, day ->
            val left = i * (dayWidth + dayGap)
            listOf(day.first to mineColor, day.second to partnerColor)
                .forEachIndexed { j, (value, color) ->
                    val x = left + j * (barWidth + barGap)
                    if (value < 0) {
                        // День без отметки — тонкая подложка вместо столбика.
                        paint.color = emptyColor
                        val y = heightPx - minBar * 0.5f
                        canvas.drawRoundRect(
                            x, y, x + barWidth, heightPx.toFloat(), radius, radius, paint,
                        )
                    } else {
                        paint.color = color
                        val h = (heightPx * value / 100f).coerceAtLeast(minBar)
                        canvas.drawRoundRect(
                            x,
                            heightPx - h,
                            x + barWidth,
                            heightPx.toFloat(),
                            radius,
                            radius,
                            paint,
                        )
                    }
                }
        }
        return output
    }

    /**
     * Полоса прогресса: подложка [trackColor] и заливка [fillColor] на
     * [percent] процентов, оба конца скруглены.
     *
     * Рисуется картинкой, а не `ProgressBar`: у RemoteViews нет способа
     * перекрасить `progressDrawable`, а цвета должны идти от темы приложения.
     */
    fun progress(
        widthPx: Int,
        heightPx: Int,
        percent: Int,
        trackColor: Int,
        fillColor: Int,
    ): Bitmap? {
        if (widthPx <= 0 || heightPx <= 0) return null
        val output = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val r = heightPx / 2f
        val paint = Paint().apply { isAntiAlias = true }

        paint.color = trackColor
        canvas.drawRoundRect(0f, 0f, widthPx.toFloat(), heightPx.toFloat(), r, r, paint)

        val filled = widthPx * percent.coerceIn(0, 100) / 100f
        // Меньше собственной высоты полоска выглядит обрубком, поэтому пустой
        // прогресс просто не рисуем.
        if (filled >= heightPx) {
            paint.color = fillColor
            canvas.drawRoundRect(0f, 0f, filled, heightPx.toFloat(), r, r, paint)
        }
        return output
    }

    /**
     * Кольцо года: дорожка [trackColor], дуга [fillColor] на долю [progress]
     * (0…1) от двенадцати часов по часовой и метка сегодняшнего дня на конце —
     * кружок цвета [dotColor] с обводкой цветом дуги. Раскладка общая с iPhone
     * и превью в каталоге (`lib/models/year_ring_spec.dart`).
     *
     * Размеры в dp, картинка рисуется с плотностью [pxPerDp] и получает её в
     * `Bitmap.density`: ImageView с wrap_content покажет кольцо ровно в
     * [sideDp], даже если плотность картинки ниже экранной (так её вес
     * укладывается в транзакцию обновления виджета).
     */
    fun yearRing(
        sideDp: Float,
        strokeDp: Float,
        pxPerDp: Float,
        progress: Float,
        trackColor: Int,
        fillColor: Int,
        dotColor: Int,
    ): Bitmap? {
        val sizePx = (sideDp * pxPerDp).toInt()
        if (sizePx <= 0 || strokeDp <= 0f) return null
        val output = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        output.density = (DisplayMetrics.DENSITY_DEFAULT * pxPerDp).toInt()
        val canvas = Canvas(output)
        canvas.scale(pxPerDp, pxPerDp)

        val c = sideDp / 2f
        val radius = (sideDp - strokeDp) / 2f
        val paint = Paint().apply {
            isAntiAlias = true
            style = Paint.Style.STROKE
            strokeWidth = strokeDp
            color = trackColor
        }
        canvas.drawCircle(c, c, radius, paint)

        val p = progress.coerceIn(0f, 1f)
        // Круглый конец на нулевой дуге рисует точку на двенадцати часах — в
        // первый день года это читается как сбой, поэтому порог.
        if (p > 0.002f) {
            paint.color = fillColor
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawArc(
                RectF(c - radius, c - radius, c + radius, c + radius),
                -90f, 360f * p, false, paint,
            )
        }

        val a = -Math.PI / 2 + p * 2 * Math.PI
        val ex = c + radius * Math.cos(a).toFloat()
        val ey = c + radius * Math.sin(a).toFloat()
        val dotR = strokeDp * 0.95f
        canvas.drawCircle(ex, ey, dotR, Paint().apply { isAntiAlias = true; color = dotColor })
        canvas.drawCircle(ex, ey, dotR, Paint().apply {
            isAntiAlias = true
            style = Paint.Style.STROKE
            strokeWidth = strokeDp * 0.55f
            color = fillColor
        })
        return output
    }

    /**
     * Фон «Кольца года»: градиент от светлого тона [primary] к глубокому под
     * 140°, пятно [tertiary] в правом верхнем углу, свечение [onPrimary] у
     * конца дуги ([glowXDp], [glowYDp]) и, если [arcs], две полупрозрачные дуги
     * в углу. Повторяет `YearRingBackdropPainter` из приложения.
     *
     * Плотность нарочно низкая: фон мягкий и растягивается без потерь, а вес
     * картинки не должен вытеснить кольцо из транзакции обновления.
     */
    fun ringBackdrop(
        widthDp: Float,
        heightDp: Float,
        pxPerDp: Float,
        primary: Int,
        onPrimary: Int,
        tertiary: Int,
        glowXDp: Float,
        glowYDp: Float,
        arcs: Boolean,
    ): Bitmap? {
        val wPx = (widthDp * pxPerDp).toInt()
        val hPx = (heightDp * pxPerDp).toInt()
        if (wPx <= 0 || hPx <= 0) return null
        val output = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.scale(pxPerDp, pxPerDp)

        val dx = 0.6428f
        val dy = 0.7660f
        val len = widthDp * dx + heightDp * dy
        val cx = widthDp / 2f
        val cy = heightDp / 2f
        canvas.drawRect(0f, 0f, widthDp, heightDp, Paint().apply {
            shader = LinearGradient(
                cx - dx * len / 2, cy - dy * len / 2,
                cx + dx * len / 2, cy + dy * len / 2,
                intArrayOf(lerp(primary, Color.WHITE, 0.08f), primary, lerp(primary, Color.BLACK, 0.18f)),
                floatArrayOf(0f, 0.45f, 1f),
                Shader.TileMode.CLAMP,
            )
        })

        canvas.save()
        canvas.translate(widthDp, 0f)
        canvas.scale(1f, 140f / 180f)
        canvas.drawCircle(0f, 0f, 180f, Paint().apply {
            isAntiAlias = true
            shader = RadialGradient(
                0f, 0f, 180f,
                intArrayOf(alpha(tertiary, 0.38f), alpha(tertiary, 0f)),
                floatArrayOf(0f, 0.7f),
                Shader.TileMode.CLAMP,
            )
        })
        canvas.restore()

        canvas.drawCircle(glowXDp, glowYDp, 120f, Paint().apply {
            isAntiAlias = true
            shader = RadialGradient(
                glowXDp, glowYDp, 120f,
                intArrayOf(alpha(onPrimary, 0.26f), alpha(onPrimary, 0f)),
                floatArrayOf(0f, 0.7f),
                Shader.TileMode.CLAMP,
            )
        })

        if (arcs) {
            val ax = widthDp - 38f
            val paint = Paint().apply { isAntiAlias = true; style = Paint.Style.STROKE }
            paint.strokeWidth = 18f
            paint.color = alpha(onPrimary, 0.10f)
            canvas.drawCircle(ax, -10f, 90f, paint)
            paint.strokeWidth = 10f
            paint.color = alpha(onPrimary, 0.06f)
            canvas.drawCircle(ax, -10f, 130f, paint)
        }
        return output
    }

    /** Цвет [color] с прозрачностью [a] (0…1). */
    fun alpha(color: Int, a: Float): Int =
        (color and 0x00FFFFFF) or ((a.coerceIn(0f, 1f) * 255f).toInt() shl 24)

    private fun lerp(from: Int, to: Int, t: Float): Int {
        fun ch(shift: Int): Int {
            val a = (from shr shift) and 0xFF
            val b = (to shr shift) and 0xFF
            return (a + (b - a) * t).toInt().coerceIn(0, 255)
        }
        return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }

    /**
     * Календарь лет: сетка круглых точек, точка — месяц, ряд — год.
     *
     * Первые [filled] точек залиты [pastColor], следующая — [currentColor]
     * (текущий месяц), остальные [futureColor]. Ряды и колонки задаёт
     * вызывающий: 12 колонок неизменны, а рядов становится больше, когда пара
     * переживает верхнюю границу сетки.
     *
     * Картинкой, а не семьюдесятью двумя `ImageView`: столько вью в одном
     * RemoteViews раздувают транзакцию до отказа лончера.
     */
    fun monthsGrid(
        filled: Int,
        rows: Int,
        columns: Int,
        dotPx: Float,
        gapPx: Float,
        pastColor: Int,
        currentColor: Int,
        futureColor: Int,
    ): Bitmap? {
        if (rows <= 0 || columns <= 0 || dotPx <= 0f) return null
        val width = (columns * dotPx + (columns - 1) * gapPx).toInt()
        val height = (rows * dotPx + (rows - 1) * gapPx).toInt()
        if (width <= 0 || height <= 0) return null

        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply { isAntiAlias = true }
        val r = dotPx / 2f

        for (row in 0 until rows) {
            for (col in 0 until columns) {
                val i = row * columns + col
                paint.color = when {
                    i < filled -> pastColor
                    i == filled -> currentColor
                    else -> futureColor
                }
                canvas.drawCircle(
                    col * (dotPx + gapPx) + r,
                    row * (dotPx + gapPx) + r,
                    r,
                    paint,
                )
            }
        }
        return output
    }
}
