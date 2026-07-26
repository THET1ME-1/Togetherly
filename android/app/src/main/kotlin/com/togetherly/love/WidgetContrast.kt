package com.togetherly.love

import android.graphics.Bitmap
import android.graphics.Color
import kotlin.math.pow

/**
 * Читаемый текст поверх фотографии.
 *
 * Раньше подпись на фото всегда была белой, а поверх снимка лежала вуаль в 10%
 * чёрного. На светлом кадре — рисунок на белом листе, снег, небо — белые буквы
 * пропадали (жалоба от @Vidming). Теперь цвет считается по самой картинке: тем
 * же способом, что и текст в чате (`lib/utils/readable_text.dart`) — контраст
 * по WCAG 2.1, побеждает вариант с большим значением.
 *
 * Заодно подбирается вуаль: под тёмный текст она светлая, под белый — тёмная.
 * Фото под ней остаётся видно, но буквы не спорят с фоном.
 */
object WidgetContrast {

    /** Тёмный вариант текста — почти чёрный с синевой, как в чате. */
    const val DARK_TEXT = 0xFF16161A.toInt()
    const val LIGHT_TEXT = 0xFFFFFFFF.toInt()

    /** Вуаль поверх фото: та же плотность у обоих вариантов. */
    private const val VEIL_ALPHA = 0x59 // 35%

    /** Подобранное оформление подписи. */
    data class Ink(
        /** Основной текст (статус). */
        val primary: Int,
        /** Второстепенный — сообщение. */
        val secondary: Int,
        /** Третьестепенный — музыка. */
        val tertiary: Int,
        /** Вуаль поверх фотографии. */
        val veil: Int,
    )

    /**
     * Оформление для подписи поверх [bitmap].
     *
     * Считаем среднюю яркость только той полосы, где реально лежит текст:
     * у светлого неба сверху и тёмной земли снизу средние по всему кадру
     * совпадают, а подпись при этом на земле.
     */
    fun inkFor(bitmap: Bitmap?, top: Float = 0.35f, bottom: Float = 1f): Ink {
        val luminance = bitmap?.let { averageLuminance(it, top, bottom) }
        // Фото нет — обычный тёмный текст на светлой карточке.
        if (luminance == null) {
            return Ink(
                primary = Color.argb(204, 0, 0, 0),
                secondary = Color.argb(153, 0, 0, 0),
                tertiary = Color.argb(136, 0, 0, 0),
                veil = Color.TRANSPARENT,
            )
        }

        val onLight = contrast(luminance, 1.0) < contrast(luminance, darkLuminance())
        return if (onLight) {
            Ink(
                primary = DARK_TEXT,
                secondary = withAlpha(DARK_TEXT, 224),
                tertiary = withAlpha(DARK_TEXT, 190),
                veil = Color.argb(VEIL_ALPHA, 255, 255, 255),
            )
        } else {
            Ink(
                primary = LIGHT_TEXT,
                secondary = withAlpha(LIGHT_TEXT, 224),
                tertiary = withAlpha(LIGHT_TEXT, 190),
                veil = Color.argb(VEIL_ALPHA, 0, 0, 0),
            )
        }
    }

    /**
     * Средняя относительная яркость полосы [top]..[bottom] (доли высоты).
     *
     * Пиксели берём через шаг: на снимке 220×220 полный обход — сорок восемь
     * тысяч точек на каждую перерисовку виджета, а для средней хватает выборки.
     */
    fun averageLuminance(bitmap: Bitmap, top: Float, bottom: Float): Double {
        val h = bitmap.height
        val w = bitmap.width
        if (w <= 0 || h <= 0) return 1.0

        val y0 = (h * top).toInt().coerceIn(0, h - 1)
        val y1 = (h * bottom).toInt().coerceIn(y0 + 1, h)
        val step = maxOf(1, minOf(w, y1 - y0) / 24)

        var sum = 0.0
        var count = 0
        var y = y0
        while (y < y1) {
            var x = 0
            while (x < w) {
                sum += relativeLuminance(bitmap.getPixel(x, y))
                count++
                x += step
            }
            y += step
        }
        return if (count == 0) 1.0 else sum / count
    }

    /** Относительная яркость цвета по WCAG 2.1. */
    fun relativeLuminance(color: Int): Double {
        fun channel(v: Int): Double {
            val c = v / 255.0
            return if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * channel(Color.red(color)) +
            0.7152 * channel(Color.green(color)) +
            0.0722 * channel(Color.blue(color))
    }

    /** Контраст двух яркостей: от 1 (одинаковые) до 21 (чёрный с белым). */
    private fun contrast(a: Double, b: Double): Double {
        val hi = maxOf(a, b)
        val lo = minOf(a, b)
        return (hi + 0.05) / (lo + 0.05)
    }

    private fun darkLuminance(): Double = relativeLuminance(DARK_TEXT)

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
}
