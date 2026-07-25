package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader

/**
 * Картинки для виджетов рабочего стола.
 *
 * Тот же приём, что в `DaysCounterWidgetProvider`, но вынесенный наружу:
 * аватары понадобились и виджету «Вместе». RemoteViews не умеет обрезать
 * ImageView по кругу, поэтому круг вырезаем сами и отдаём готовый bitmap.
 */
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
}
