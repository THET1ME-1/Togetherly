package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.BitmapFactory
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

    /**
     * Кадр пиксель-арта из файла, увеличенный ЦЕЛОЕ число раз и без
     * сглаживания.
     *
     * Дробное увеличение и любая фильтрация превращают пиксель-арт в мыло —
     * то же правило держит `PixelMascotView` на стороне Flutter. Поэтому кадр
     * приезжает один к одному (48 или 96 точек), а здесь домножается на
     * целое: картинка выходит не больше [targetPx], и `scaleType="center"`
     * рисует её точка в точку.
     */
    fun pixelArt(path: String?, targetPx: Int, framePx: Int): Bitmap? {
        if (path.isNullOrEmpty() || targetPx <= 0) return null
        val file = java.io.File(path)
        if (!file.exists()) return null
        val opts = BitmapFactory.Options().apply { inScaled = false }
        val src = BitmapFactory.decodeFile(path, opts) ?: return null
        val base = if (framePx > 0) framePx else maxOf(src.width, src.height)
        if (base <= 0) return src
        val k = maxOf(1, targetPx / base)
        val size = base * k
        if (size == src.width && size == src.height) return src
        return try {
            Bitmap.createScaledBitmap(src, size, size, false)
        } catch (e: OutOfMemoryError) {
            src
        }
    }

    /**
     * Обычная картинка маскота, вписанная в квадрат [targetPx] по большей
     * стороне. Нарисованный человеком зверёк приезжает произвольного размера
     * и произвольных пропорций, растягивать его в квадрат нельзя.
     */
    fun fitted(path: String?, targetPx: Int): Bitmap? {
        if (path.isNullOrEmpty() || targetPx <= 0) return null
        val src = PhotoDayWidgetProvider.loadScaledBitmapStatic(path, targetPx) ?: return null
        val longest = maxOf(src.width, src.height)
        if (longest <= targetPx) return src
        val k = targetPx.toFloat() / longest
        val w = maxOf(1, (src.width * k).toInt())
        val h = maxOf(1, (src.height * k).toInt())
        return try {
            Bitmap.createScaledBitmap(src, w, h, true)
        } catch (e: OutOfMemoryError) {
            src
        }
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
     * Размеры в dp, рисуется с плотностью [pxPerDp]. Передавать экранную:
     * `Bitmap.density` лончер не учитывает и кладёт картинку пиксель в пиксель,
     * поэтому ImageView с wrap_content покажет ровно [sideDp] только при ней
     * (эмулятор, 14.09.2026: кольцо 122 dp при двух пикселях на dp выходило 96).
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

    /**
     * Фон виджета «Вместе»: заливка [bgColor] со скруглением [cornerDp] и
     * растр точками [dotColor], растущими к правому нижнему углу.
     *
     * Та же логика, что у HalftonePainter на главной кнопке листа
     * «Добавить воспоминание»: точки мельчают к левому верху, где лежит текст,
     * поэтому рябь не мешает читать число.
     */
    fun halftone(
        widthDp: Float,
        heightDp: Float,
        pxPerDp: Float,
        bgColor: Int,
        dotColor: Int,
        cornerDp: Float = 28f,
    ): Bitmap? {
        val wPx = (widthDp * pxPerDp).toInt()
        val hPx = (heightDp * pxPerDp).toInt()
        if (wPx <= 0 || hPx <= 0) return null
        val output = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.scale(pxPerDp, pxPerDp)

        val paint = Paint().apply { isAntiAlias = true }
        paint.color = bgColor
        canvas.drawRoundRect(
            RectF(0f, 0f, widthDp, heightDp), cornerDp, cornerDp, paint,
        )

        // Рисуем точки только внутри скругления: вне его они лезли бы на угол.
        canvas.save()
        val clip = android.graphics.Path().apply {
            addRoundRect(
                RectF(0f, 0f, widthDp, heightDp), cornerDp, cornerDp,
                android.graphics.Path.Direction.CW,
            )
        }
        canvas.clipPath(clip)

        // Точки полупрозрачные: непрозрачный растр на 2×2 превращался в
        // горошек и спорил с числом.
        paint.color = alpha(dotColor, 0.55f)
        val step = 15f
        val maxR = 5.2f
        val far = Math.hypot(widthDp.toDouble(), heightDp.toDouble()).toFloat()
        var y = step / 2f
        while (y < heightDp) {
            var x = step / 2f
            while (x < widthDp) {
                val t = Math.hypot(x.toDouble(), y.toDouble()).toFloat() / far
                val r = (t - 0.18f) * maxR
                if (r >= 0.5f) canvas.drawCircle(x, y, r, paint)
                x += step
            }
            y += step
        }
        canvas.restore()
        return output
    }

    /**
     * Горизонтальная дорожка вех: линия, пройденная часть и три отметки —
     * прошлая веха слева, сегодня по доле [percent], будущие справа.
     *
     * Подписи рисует не картинка, а TextView разметки: их собирает приложение
     * на языке человека (см. `trackLabels` в models/together_milestones.dart).
     */
    fun trackLine(
        widthDp: Float,
        heightDp: Float,
        pxPerDp: Float,
        percent: Int,
        hasPrevious: Boolean,
        midStop: Boolean,
        trackColor: Int,
        fillColor: Int,
        ringColor: Int,
    ): Bitmap? {
        val wPx = (widthDp * pxPerDp).toInt()
        val hPx = (heightDp * pxPerDp).toInt()
        if (wPx <= 0 || hPx <= 0) return null
        val output = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.scale(pxPerDp, pxPerDp)

        val pad = 9f
        val left = pad
        val right = widthDp - pad
        val cy = heightDp / 2f
        val stroke = 5f

        val paint = Paint().apply {
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
            strokeWidth = stroke
        }
        paint.color = trackColor
        canvas.drawLine(left, cy, right, cy, paint)

        val here = left + (right - left) * percent.coerceIn(0, 100) / 100f
        paint.color = fillColor
        canvas.drawLine(left, cy, here, cy, paint)

        val dot = Paint().apply { isAntiAlias = true }
        dot.color = if (hasPrevious) fillColor else trackColor
        canvas.drawCircle(left, cy, 6f, dot)
        if (midStop) {
            dot.color = trackColor
            canvas.drawCircle(left + (right - left) / 2f, cy, 6f, dot)
        }
        dot.color = trackColor
        canvas.drawCircle(right, cy, 6f, dot)

        // Сегодняшняя отметка крупнее и с обводкой цвета фона: она главная.
        dot.color = ringColor
        canvas.drawCircle(here, cy, 9.5f, dot)
        dot.color = fillColor
        canvas.drawCircle(here, cy, 7f, dot)
        return output
    }

    /**
     * Вертикальная лента вех для 4×4: линия сверху вниз, отметки на [stops]
     * долях высоты (0…1) и заполненная часть до [current].
     */
    fun trackColumn(
        widthDp: Float,
        heightDp: Float,
        pxPerDp: Float,
        stops: FloatArray,
        current: Int,
        trackColor: Int,
        fillColor: Int,
        ringColor: Int,
        lastColor: Int,
    ): Bitmap? {
        val wPx = (widthDp * pxPerDp).toInt()
        val hPx = (heightDp * pxPerDp).toInt()
        if (wPx <= 0 || hPx <= 0 || stops.isEmpty()) return null
        val output = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.scale(pxPerDp, pxPerDp)

        val cx = widthDp / 2f
        val top = heightDp * stops.first()
        val bottom = heightDp * stops.last()
        val paint = Paint().apply {
            isAntiAlias = true
            strokeWidth = 4f
            strokeCap = Paint.Cap.ROUND
        }
        paint.color = trackColor
        canvas.drawLine(cx, top, cx, bottom, paint)
        if (current in stops.indices) {
            paint.color = fillColor
            canvas.drawLine(cx, top, cx, heightDp * stops[current], paint)
        }

        val dot = Paint().apply { isAntiAlias = true }
        stops.forEachIndexed { i, s ->
            val y = heightDp * s
            when {
                i == current -> {
                    dot.color = ringColor
                    canvas.drawCircle(cx, y, 9.5f, dot)
                    dot.color = fillColor
                    canvas.drawCircle(cx, y, 7f, dot)
                }
                i == stops.lastIndex -> {
                    dot.color = lastColor
                    canvas.drawCircle(cx, y, 7f, dot)
                }
                i < current -> {
                    dot.color = fillColor
                    canvas.drawCircle(cx, y, 7f, dot)
                }
                else -> {
                    dot.color = trackColor
                    canvas.drawCircle(cx, y, 7f, dot)
                }
            }
        }
        return output
    }
}
