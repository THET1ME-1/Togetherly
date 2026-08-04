package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Rect
import android.os.SystemClock
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File

/**
 * Живое фото в виджете: покадровый показ раскадровки.
 *
 * Анимации внутри виджета не существует. `RemoteViews` инфлейтит только классы
 * из белого списка (плеера там нет), а `ImageView` в чужом процессе не
 * проигрывает ни gif, ни анимированный drawable — что через битмап, что через
 * Uri он покажет один кадр. Поэтому кадры подсовывает приложение: каждые
 * `stepMs` рисует очередную клетку атласа в битмап и вызывает
 * `updateAppWidget`. Проба на живом телефоне держала шаг 100 мс при худшем 121.
 *
 * Кадры готовит сервер (`tools/widget_anim.py`): один webp 6×3 по 300 px плюс
 * манифест. Здесь ровно тот же приём, которым рисуются анимированные маскоты —
 * `drawBitmap` по клетке атласа.
 */
object WidgetAnimPlayer {

    /** Ключи в HomeWidgetPreferences, которые пишет Dart. */
    const val KEY_PATH = "anim_sheet_path"
    const val KEY_MANIFEST = "anim_manifest"

    /** Сколько крутим по одному нажатию. Дальше остаётся статичный кадр. */
    private const val RUN_MS = 4_000L

    /** Быстрее сотни лончеры не держат, а батарею тратят заметно. */
    private const val MIN_STEP_MS = 90L

    data class Sheet(val cols: Int, val rows: Int, val cell: Int, val frames: Int, val stepMs: Long)

    /** Разобрать манифест. null — значит живого фото нет, работаем как раньше. */
    fun manifestOf(json: String?): Sheet? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            val cols = o.optInt("cols", 0)
            val rows = o.optInt("rows", 0)
            val cell = o.optInt("cell", 0)
            if (cols <= 0 || rows <= 0 || cell <= 0) return null
            val frames = o.optInt("frames", cols * rows).coerceIn(1, cols * rows)
            val step = o.optInt("step_ms", 100).toLong().coerceAtLeast(MIN_STEP_MS)
            Sheet(cols, rows, cell, frames, step)
        } catch (e: Exception) {
            null
        }
    }

    /** Готово ли живое фото: есть манифест и файл на диске. */
    fun ready(path: String?, manifest: String?): Boolean {
        val sheet = manifestOf(manifest) ?: return false
        val f = path?.let { File(it) } ?: return false
        return sheet.frames > 0 && f.exists() && f.length() > 0
    }

    /**
     * Прокрутить кадры в указанном виджете.
     *
     * [render] отдаёт свежий `RemoteViews` с уже расставленными текстами и
     * обработчиками — сюда остаётся вложить кадр. Так провайдер не дублирует
     * разметку, а игрок не знает про его поля.
     */
    fun play(
        context: Context,
        widgetIds: IntArray,
        path: String,
        manifest: String,
        imageViewId: Int,
        render: () -> RemoteViews,
    ) {
        val sheet = manifestOf(manifest) ?: return
        val atlas = decodeAtlas(path) ?: return
        val manager = AppWidgetManager.getInstance(context)

        // Кадр рисуется в один и тот же битмап: RGB_565 вдвое дешевле по
        // транзакции, чем ARGB_8888 (300×300 — это 180 КБ против 360 при лимите
        // Binder в мегабайт на процесс).
        val frame = Bitmap.createBitmap(sheet.cell, sheet.cell, Bitmap.Config.RGB_565)
        val canvas = Canvas(frame)
        val dst = Rect(0, 0, sheet.cell, sheet.cell)

        val started = SystemClock.elapsedRealtime()
        var index = 0
        try {
            while (SystemClock.elapsedRealtime() - started < RUN_MS) {
                val tick = SystemClock.elapsedRealtime()
                val i = index % sheet.frames
                val src = Rect(
                    (i % sheet.cols) * sheet.cell,
                    (i / sheet.cols) * sheet.cell,
                    (i % sheet.cols) * sheet.cell + sheet.cell,
                    (i / sheet.cols) * sheet.cell + sheet.cell,
                )
                canvas.drawBitmap(atlas, src, dst, null)

                val views = render()
                views.setImageViewBitmap(imageViewId, frame)
                widgetIds.forEach { manager.updateAppWidget(it, views) }

                index++
                val spent = SystemClock.elapsedRealtime() - tick
                if (spent < sheet.stepMs) Thread.sleep(sheet.stepMs - spent)
            }
        } catch (e: InterruptedException) {
            // Прервали — оставляем последний кадр, это нормальное завершение.
        } finally {
            atlas.recycle()
        }
    }

    /** Первый кадр: им виджет живёт в покое. */
    fun firstFrame(path: String, manifest: String): Bitmap? {
        val sheet = manifestOf(manifest) ?: return null
        val atlas = decodeAtlas(path) ?: return null
        return try {
            val out = Bitmap.createBitmap(sheet.cell, sheet.cell, Bitmap.Config.RGB_565)
            Canvas(out).drawBitmap(
                atlas,
                Rect(0, 0, sheet.cell, sheet.cell),
                Rect(0, 0, sheet.cell, sheet.cell),
                null,
            )
            out
        } finally {
            atlas.recycle()
        }
    }

    private fun decodeAtlas(path: String): Bitmap? {
        val f = File(path)
        if (!f.exists() || f.length() <= 0) return null
        return try {
            // Атлас 1800×900 в ARGB весит 6 МБ в памяти; 565 хватает с запасом,
            // фотографии на плитке 300 px разницы не показывают.
            val opts = BitmapFactory.Options().apply {
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            BitmapFactory.decodeFile(path, opts)
        } catch (e: Throwable) {
            null
        }
    }
}
