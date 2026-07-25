package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
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
}
