package com.togetherly.love

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * Виджет «Маскот на столе» — пиксельный персонаж пары живёт на рабочем столе.
 *
 * Кадры режет приложение и кладёт файлами: день, ночь и грусть. Натив выбирает
 * между ними и увеличивает картинку целое число раз без сглаживания, иначе
 * пиксель-арт превращается в мыло.
 *
 * Ночь считается ЗДЕСЬ по окну сна из ключей: в 23:00 Flutter может и не
 * работать, а персонаж обязан лечь спать вовремя. Всё остальное — ступень,
 * серия, подписи — приходит готовым: у виджета нет локализации.
 */
open class MascotWidgetProvider : HomeWidgetProvider() {

    /** Раскладка, закреплённая за провайдером; null — выбирать по размеру. */
    protected open val forcedLayout: Int? = null

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_PLAY) {
            playFor(context, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))
            return
        }
        super.onReceive(context, intent)
    }

    /**
     * Оживляет персонажа в одном экземпляре виджета.
     *
     * `goAsync` даёт приёмнику около десяти секунд живого времени — на четыре
     * секунды показа хватает, и не нужен ни сервис, ни уведомление в шторке.
     * Тот же приём крутит живое фото в парном виджете.
     */
    private fun playFor(context: Context, widgetId: Int) {
        if (widgetId == 0) return
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val group = WidgetGroupHelper.getOrBind(context, "mascot", widgetId)
        val prefix = if (group.isEmpty()) "mascot_solo_" else "mascot_${group}_"

        val manifest = data.getString("${prefix}anim", null)
        val asleep = asleep(
            data.getString("${prefix}sleep_from", null)?.toIntOrNull() ?: -1,
            data.getString("${prefix}sleep_to", null)?.toIntOrNull() ?: -1,
        )
        val strip = data.getString(
            if (asleep) "${prefix}strip_night" else "${prefix}strip_day",
            null,
        ) ?: data.getString("${prefix}strip_day", null)
        if (strip.isNullOrEmpty() || manifest.isNullOrEmpty()) return
        // Грустит — стоит на месте: движение сглаживало бы то, о чём виджет
        // как раз и должен сказать молча.
        if (data.getString("${prefix}sad", null) == "1") return

        val manager = AppWidgetManager.getInstance(context)
        val theme = WidgetTheme.from(data)
        val layout = forcedLayout ?: R.layout.tg_mascot_2x2
        val options = manager.getAppWidgetOptions(widgetId)
        val (cellW, cellH) = WidgetSizing.cellDp(context, options)
        val heightDp = if (cellH > 0) cellH else WidgetSizing.heightDp(options)
        val targetPx = (mascotDp(layout, heightDp) * context.resources.displayMetrics.density).toInt()

        val finish = goAsync()
        Thread {
            try {
                WidgetAnimPlayer.playPixel(
                    context = context,
                    widgetIds = intArrayOf(widgetId),
                    path = strip,
                    manifest = manifest,
                    imageViewId = R.id.mascot,
                    targetPx = targetPx,
                    backgroundColor = tileColor(layout, theme),
                ) {
                    buildViews(context, manager, widgetId, data)
                }
                // Последним кадром возвращаем обычный вид: иначе персонаж
                // застынет в середине движения.
                manager.updateAppWidget(widgetId, buildViews(context, manager, widgetId, data))
            } catch (e: Exception) {
                android.util.Log.e("MascotWidget", "анимация не пошла", e)
            } finally {
                finish.finish()
            }
        }.start()
    }

    /// Цвет плитки под персонажем: на нём рисуются кадры прокрутки.
    private fun tileColor(layout: Int, theme: WidgetTheme): Int = when (layout) {
        R.layout.tg_mascot_4x1 -> theme.primaryContainer
        R.layout.tg_mascot_2x2 -> theme.surface
        else -> theme.primaryContainer
    }

    private fun mascotDp(layout: Int, heightDp: Int): Float = when (layout) {
        R.layout.tg_mascot_4x1 -> 46f
        R.layout.tg_mascot_2x2 -> (heightDp - 62).coerceIn(40, 120).toFloat()
        R.layout.tg_mascot_4x2 -> (heightDp - 30).coerceIn(48, 140).toFloat()
        // Минус пол (44) и пилюли сверху (30): кадру остаётся середина.
        else -> (heightDp - 80).coerceIn(64, 190).toFloat()
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetGroupHelper.clearBindings(context, "mascot", appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        manager.updateAppWidget(widgetId, buildViews(context, manager, widgetId, data))
        maybeAnimate(context, widgetId, data)
    }

    /**
     * Собирает разметку со всеми текстами и обработчиками.
     *
     * Отдельно от [render], потому что прокрутка кадров просит свежий
     * `RemoteViews` на каждом шаге: иначе пришлось бы дублировать вёрстку.
     */
    private fun buildViews(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ): RemoteViews {
        val group = WidgetGroupHelper.getOrBind(context, "mascot", widgetId)
        val prefix = if (group.isEmpty()) "mascot_solo_" else "mascot_${group}_"

        fun str(key: String): String = data.getString("$prefix$key", null).orEmpty()
        fun num(key: String, fallback: Int = 0): Int = str(key).toIntOrNull() ?: fallback

        val options = manager.getAppWidgetOptions(widgetId)
        // Настоящая ячейка, а не минимумы обеих сторон: у 4×2 на Pixel
        // Launcher они врут почти вдвое, и картинка выходила бы вполовину.
        val (cellWidthDp, cellHeightDp) = WidgetSizing.cellDp(context, options)
        val widthDp = if (cellWidthDp > 0) cellWidthDp else WidgetSizing.widthDp(options)
        val heightDp = if (cellHeightDp > 0) cellHeightDp else WidgetSizing.heightDp(options)

        val layout = forcedLayout ?: when {
            widthDp >= 200 && heightDp >= 200 -> R.layout.tg_mascot_4x4
            widthDp >= 200 && heightDp >= 100 -> R.layout.tg_mascot_4x2
            widthDp >= 200 -> R.layout.tg_mascot_4x1
            else -> R.layout.tg_mascot_2x2
        }

        val baseDp = when (layout) {
            R.layout.tg_mascot_4x4 -> 250
            R.layout.tg_mascot_4x1 -> 56
            else -> 115
        }
        val scale = WidgetSizing.scale(heightDp, baseDp)
        val theme = WidgetTheme.from(data)
        val density = context.resources.displayMetrics.density

        val name = str("name")
        val hasMascot = name.isNotEmpty() && str("frame_day").isNotEmpty()

        val views = RemoteViews(context.packageName, layout)
        views.tint(R.id.bg, if (layout == R.layout.tg_mascot_4x1) theme.primaryContainer else theme.surface)

        // Персонажа не выбрали: виджет обязан назвать себя, а не висеть
        // пустой плиткой — иначе человек решит, что он не добавился.
        views.setViewVisibility(R.id.empty_label, if (hasMascot) View.GONE else View.VISIBLE)
        if (!hasMascot) {
            views.setTextViewText(R.id.empty_label, context.getString(R.string.tg_mascot_empty))
            views.setTextColor(R.id.empty_label, theme.onSurfaceVariant)
            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            return views
        }

        val framePx = num("frame_px", 48)
        val path = framePath(data, prefix, num("sleep_from", -1), num("sleep_to", -1), str("sad") == "1")
        val targetPx = (mascotDp(layout, heightDp) * density).toInt()
        // Пиксельный кадр увеличиваем целым числом раз, рисунок человека
        // вписываем: у него свои пропорции и свой размер.
        val bitmap = if (str("pixel") == "0") {
            WidgetImages.fitted(path, targetPx)
        } else {
            WidgetImages.pixelArt(path, targetPx, framePx)
        }
        if (bitmap != null) views.setImageViewBitmap(R.id.mascot, bitmap)

        val stage = str("stage_label")
        val streak = num("streak")
        val streakLabel = str("streak_label")
        val nextLabel = str("next_label")

        views.setTextColor(R.id.name, theme.onSurface)
        views.setTextColor(R.id.sub, theme.onSurfaceVariant)
        views.setTextColor(R.id.next_label, theme.onSurfaceVariant)
        views.setTextColor(R.id.streak_label, theme.onSurfaceVariant)
        views.setTextColor(R.id.record_label, theme.onSurfaceVariant)

        when (layout) {
            R.layout.tg_mascot_4x1 -> {
                views.setTextViewText(R.id.name, name)
                views.setTextViewText(R.id.sub, listOf(stage, nextLabel).filter { it.isNotEmpty() }.joinToString(" · "))
                views.setTextViewText(R.id.streak_value, "$streak")
                views.setTextViewText(R.id.streak_label, streakLabel)
                views.setTextColor(R.id.streak_value, theme.onPrimaryContainer)
                views.size(R.id.streak_value, 24f * scale)
            }

            R.layout.tg_mascot_2x2 -> {
                views.setTextViewText(R.id.name, name)
                views.setTextViewText(R.id.stage, stage)
                views.setTextViewText(R.id.next_label, nextLabel)
                views.tint(R.id.stage_chip, theme.tertiaryContainer)
                views.setTextColor(R.id.stage, theme.onTertiaryContainer)
                views.progressInto(R.id.progress, widthDp - 24, theme, num("progress"), density)
            }

            R.layout.tg_mascot_4x2 -> {
                views.setTextViewText(R.id.name, name)
                views.setTextViewText(
                    R.id.sub,
                    listOf(stage, "$streak $streakLabel").filter { it.isNotBlank() }.joinToString(" · "),
                )
                views.setTextViewText(R.id.next_label, nextLabel)
                views.tint(R.id.tile_streak, theme.primaryContainer)
                views.size(R.id.name, 19f * scale)
                views.progressInto(R.id.progress, widthDp - 156, theme, num("progress"), density)
            }

            else -> {
                views.setTextViewText(R.id.name, listOf(name, stage).filter { it.isNotEmpty() }.joinToString(" · "))
                // Ночная сцена есть не у всех, а у рисованных её нет вовсе:
                // пустая подпись убирает пилюлю целиком.
                val sleepText = sleepLabel(
                    str("sleep_label_day"),
                    str("sleep_label_night"),
                    num("sleep_from", -1),
                    num("sleep_to", -1),
                )
                val hasSleep = sleepText.isNotEmpty()
                views.setViewVisibility(R.id.sleep_chip, if (hasSleep) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.sleep_label, if (hasSleep) View.VISIBLE else View.GONE)
                views.setTextViewText(R.id.sleep_label, sleepText)
                views.setTextViewText(R.id.streak_value, "$streak")
                views.setTextViewText(R.id.streak_label, streakLabel)
                views.setTextViewText(R.id.next_label, nextLabel)
                views.setTextViewText(R.id.record_value, "${num("record")}")
                views.setTextViewText(R.id.record_label, str("record_label").substringBefore(' '))
                views.tint(R.id.tile_streak, theme.primaryContainer)
                views.tint(R.id.floor, theme.trackOnContainer)
                views.tint(R.id.tile_progress, theme.primaryContainer)
                views.tint(R.id.tile_record, theme.primaryContainer)
                views.tint(R.id.stage_chip, theme.surface)
                views.tint(R.id.sleep_chip, theme.tertiaryContainer)
                views.setTextColor(R.id.name, theme.onSurface)
                views.setTextColor(R.id.sleep_label, theme.onTertiaryContainer)
                views.setTextColor(R.id.streak_value, theme.onPrimaryContainer)
                views.setTextColor(R.id.record_value, theme.onPrimaryContainer)
                views.size(R.id.streak_value, 24f * scale)
                views.size(R.id.record_value, 24f * scale)
                views.progressInto(R.id.progress, (widthDp - 36) / 3, theme, num("progress"), density)
            }
        }

        views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
        // Тап по самому зверьку оживляет его, как на главной: там персонажа
        // тоже трогают пальцем. Остальная карточка открывает приложение.
        if (str("anim").isNotEmpty()) {
            views.setOnClickPendingIntent(R.id.mascot, playIntent(context, widgetId))
        }
        return views
    }

    /** Какой кадр показывать прямо сейчас: грусть старше сна, сон старше дня. */
    private fun framePath(
        data: SharedPreferences,
        prefix: String,
        sleepFrom: Int,
        sleepTo: Int,
        sad: Boolean,
    ): String? {
        val day = data.getString("${prefix}frame_day", null)
        if (sad) {
            val sadPath = data.getString("${prefix}frame_sad", null)
            if (!sadPath.isNullOrEmpty()) return sadPath
        }
        if (asleep(sleepFrom, sleepTo)) {
            val night = data.getString("${prefix}frame_night", null)
            if (!night.isNullOrEmpty()) return night
        }
        return day
    }

    private fun sleepLabel(day: String, night: String, from: Int, to: Int): String =
        if (asleep(from, to) && night.isNotEmpty()) night else day

    /**
     * Спит ли персонаж сейчас. Начало окна включено, конец нет — ровно как
     * `SleepWindow.contains` в приложении. Окно через полночь (23:00→07:00)
     * разворачивается в две половины.
     */
    private fun asleep(from: Int, to: Int): Boolean {
        if (from < 0 || to < 0 || from == to) return false
        val calendar = Calendar.getInstance()
        val now = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        return if (from < to) now >= from && now < to else now >= from || now < to
    }

    private fun RemoteViews.progressInto(
        viewId: Int,
        widthDp: Int,
        theme: WidgetTheme,
        percent: Int,
        density: Float,
    ) {
        val w = (widthDp.coerceAtLeast(40) * density).toInt()
        val h = (8 * density).toInt()
        WidgetImages.progress(w, h, percent, theme.trackOnContainer, theme.primary)
            ?.let { setImageViewBitmap(viewId, it) }
    }

    private fun RemoteViews.size(viewId: Int, sp: Float) =
        setTextViewTextSize(viewId, TypedValue.COMPLEX_UNIT_DIP, sp)

    /** Тап по персонажу: широковещательный интент самому себе. */
    private fun playIntent(context: Context, widgetId: Int): PendingIntent {
        val intent = Intent(context, javaClass).apply {
            action = ACTION_PLAY
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            // Без data разные экземпляры делят один PendingIntent, и крутился
            // бы всегда первый виджет.
            data = android.net.Uri.parse("mascot://play/$widgetId")
        }
        return PendingIntent.getBroadcast(
            context,
            widgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Персонаж шевелится и сам, не только по тапу: иначе на столе он выглядит
     * наклейкой. Но не чаще раза в [ANIMATE_EVERY_MS] — прокрутка держит
     * приёмник живым несколько секунд и стоит батареи.
     */
    private fun maybeAnimate(context: Context, widgetId: Int, data: SharedPreferences) {
        if (data.getString("mascot_anim_off", null) == "1") return
        val key = "mascot_played_$widgetId"
        val now = System.currentTimeMillis()
        val last = data.getString(key, null)?.toLongOrNull() ?: 0L
        if (now - last < ANIMATE_EVERY_MS) return
        data.edit().putString(key, "$now").apply()
        playFor(context, widgetId)
    }

    private fun openApp(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        android.net.Uri.parse("loveapp://mascot"),
    )

    companion object {
        const val ACTION_PLAY = "com.togetherly.love.action.MASCOT_PLAY"

        /** Как часто персонаж оживает сам. */
        private const val ANIMATE_EVERY_MS = 10 * 60 * 1000L
    }
}

class MascotWidget4x1Provider : MascotWidgetProvider() {
    override val forcedLayout = R.layout.tg_mascot_4x1
}

class MascotWidget2x2Provider : MascotWidgetProvider() {
    override val forcedLayout = R.layout.tg_mascot_2x2
}

class MascotWidget4x2Provider : MascotWidgetProvider() {
    override val forcedLayout = R.layout.tg_mascot_4x2
}

class MascotWidget4x4Provider : MascotWidgetProvider() {
    override val forcedLayout = R.layout.tg_mascot_4x4
}
