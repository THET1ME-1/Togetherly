package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle

/**
 * Подгонка виджета под фактическую ячейку лончера.
 *
 * Гайдлайны Android дают для телефонов вилку: 2×2 и 4×2 — от 115 до 276dp в
 * высоту, 4×1 — от 56 до 130dp. Разброс двукратный, и это не теория: Nova
 * выдаёт ячейку у нижней границы (низ карточки срезался), стандартный лончер
 * Xiaomi — почти у верхней (посреди карточки зияла пустота).
 *
 * Одной разметкой под фиксированный кегль такую вилку не закрыть, поэтому
 * размеры текста считаются от реальной высоты ячейки и проставляются через
 * `setTextViewTextSize` — он есть с API 16, в отличие от карты `SizeF`
 * (API 31), а minSdk у проекта 24.
 */
object WidgetSizing {

    /** Высота ячейки в dp, как её сообщает лончер. 0 — ещё не сообщил. */
    fun heightDp(options: Bundle?): Int =
        options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0

    /** Ширина ячейки в dp. */
    fun widthDp(options: Bundle?): Int =
        options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0

    /**
     * Настоящая ячейка на экране (ширина, высота) в dp. Лончер сообщает две
     * пары: MIN_WIDTH × MAX_HEIGHT — портрет, MAX_WIDTH × MIN_HEIGHT — альбом.
     * Минимумы обеих сторон — это ни то ни другое: у 4×2 на Pixel Launcher
     * они дают 360×135 при настоящих 360×224. Нули — лончер ещё не сообщил.
     */
    fun cellDp(context: Context, options: Bundle?): Pair<Int, Int> {
        if (options == null) return 0 to 0
        val landscape = context.resources.configuration.orientation ==
            Configuration.ORIENTATION_LANDSCAPE
        val w = options.getInt(
            if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
            else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0,
        )
        val h = options.getInt(
            if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0,
        )
        return w to h
    }

    /**
     * Во сколько раз растягивать кегли: 1.0 на нижней границе вилки и до
     * [max] на верхней. Пока лончер не сообщил размер — 1.0, то есть
     * компактный вариант: лучше пустовато, чем срезано.
     *
     * @param heightDp фактическая высота ячейки
     * @param baseDp высота, под которую свёрстана разметка
     * @param max потолок растяжения
     */
    fun scale(heightDp: Int, baseDp: Int, max: Float = 1.6f): Float {
        if (heightDp <= 0 || baseDp <= 0) return 1f
        val raw = heightDp.toFloat() / baseDp.toFloat()
        return raw.coerceIn(1f, max)
    }
}
