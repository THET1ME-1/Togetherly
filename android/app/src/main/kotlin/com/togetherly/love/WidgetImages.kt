package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
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
     * Кольцо года: трек [trackColor] на всю окружность и дуга [fillColor] на
     * долю [progress] (0…1). Старт в двенадцать часов, дальше по часовой,
     * концы дуги круглые.
     *
     * Дуги в RemoteViews нет: ни `ProgressBar` со стилем circular, ни поворот
     * вью цвет темы не примут. Поэтому кольцо рисуется целиком и уходит в
     * `ImageView` как bitmap.
     */
    fun ring(
        sizePx: Int,
        strokePx: Float,
        progress: Float,
        trackColor: Int,
        fillColor: Int,
    ): Bitmap? {
        if (sizePx <= 0 || strokePx <= 0f) return null
        val output = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply {
            isAntiAlias = true
            style = Paint.Style.STROKE
            strokeWidth = strokePx
        }

        // Радиус из хендофа: r = 42 в системе координат 100×100.
        val radius = sizePx * 0.42f
        val c = sizePx / 2f
        val box = RectF(c - radius, c - radius, c + radius, c + radius)

        paint.color = trackColor
        paint.strokeCap = Paint.Cap.BUTT
        canvas.drawCircle(c, c, radius, paint)

        val sweep = 360f * progress.coerceIn(0f, 1f)
        // Круглый конец на нулевой дуге рисует точку на двенадцати часах —
        // в первый день года это читается как сбой, поэтому порог.
        if (sweep > 0.5f) {
            paint.color = fillColor
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawArc(box, -90f, sweep, false, paint)
        }
        return output
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
