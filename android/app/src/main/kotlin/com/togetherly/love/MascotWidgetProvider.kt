package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
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

        val views = RemoteViews(context.packageName, layout).apply {
            tint(R.id.bg, if (layout == R.layout.tg_mascot_4x1) theme.primaryContainer else theme.surfaceContainer)

            // Персонажа не выбрали: виджет обязан назвать себя, а не висеть
            // пустой плиткой — иначе человек решит, что он не добавился.
            setViewVisibility(R.id.empty_label, if (hasMascot) View.GONE else View.VISIBLE)
            if (!hasMascot) {
                setTextViewText(R.id.empty_label, context.getString(R.string.tg_mascot_empty))
                setTextColor(R.id.empty_label, theme.onSurfaceVariant)
                setOnClickPendingIntent(R.id.widget_root, openApp(context))
                manager.updateAppWidget(widgetId, this)
                return
            }

            val framePx = num("frame_px", 48)
            val mascotDp = when (layout) {
                R.layout.tg_mascot_4x1 -> 46f
                R.layout.tg_mascot_2x2 -> (heightDp - 62).coerceIn(40, 120).toFloat()
                R.layout.tg_mascot_4x2 -> (heightDp - 30).coerceIn(48, 140).toFloat()
                else -> (heightDp * 0.42f).coerceIn(64f, 200f)
            }
            val path = framePath(data, prefix, num("sleep_from", -1), num("sleep_to", -1), str("sad") == "1")
            val targetPx = (mascotDp * density).toInt()
            // Пиксельный кадр увеличиваем целым числом раз, рисунок человека
            // вписываем: у него свои пропорции и свой размер.
            val bitmap = if (str("pixel") == "0") {
                WidgetImages.fitted(path, targetPx)
            } else {
                WidgetImages.pixelArt(path, targetPx, framePx)
            }
            if (bitmap != null) setImageViewBitmap(R.id.mascot, bitmap)

            val stage = str("stage_label")
            val streak = num("streak")
            val streakLabel = str("streak_label")
            val nextLabel = str("next_label")

            setTextColor(R.id.name, theme.onSurface)
            setTextColor(R.id.sub, theme.onSurfaceVariant)
            setTextColor(R.id.next_label, theme.onSurfaceVariant)
            setTextColor(R.id.streak_label, theme.onSurfaceVariant)
            setTextColor(R.id.record_label, theme.onSurfaceVariant)

            when (layout) {
                R.layout.tg_mascot_4x1 -> {
                    setTextViewText(R.id.name, name)
                    setTextViewText(R.id.sub, listOf(stage, nextLabel).filter { it.isNotEmpty() }.joinToString(" · "))
                    setTextViewText(R.id.streak_value, "$streak")
                    setTextViewText(R.id.streak_label, streakLabel)
                    setTextColor(R.id.streak_value, theme.onPrimaryContainer)
                    size(R.id.streak_value, 24f * scale)
                }

                R.layout.tg_mascot_2x2 -> {
                    setTextViewText(R.id.name, name)
                    setTextViewText(R.id.stage, stage)
                    setTextViewText(R.id.next_label, nextLabel)
                    tint(R.id.stage_chip, theme.tertiaryContainer)
                    setTextColor(R.id.stage, theme.onTertiaryContainer)
                    progressInto(R.id.progress, widthDp - 24, theme, num("progress"), density)
                }

                R.layout.tg_mascot_4x2 -> {
                    setTextViewText(R.id.name, name)
                    setTextViewText(
                        R.id.sub,
                        listOf(stage, "$streak $streakLabel").filter { it.isNotBlank() }.joinToString(" · "),
                    )
                    setTextViewText(R.id.next_label, nextLabel)
                    tint(R.id.tile_streak, theme.primaryContainer)
                    size(R.id.name, 19f * scale)
                    progressInto(R.id.progress, widthDp - 156, theme, num("progress"), density)
                }

                else -> {
                    setTextViewText(R.id.name, listOf(name, stage).filter { it.isNotEmpty() }.joinToString(" · "))
                    // Ночная сцена есть не у всех, а у рисованных её нет вовсе:
                    // пустая подпись убирает пилюлю целиком.
                    val sleepText = sleepLabel(
                        str("sleep_label_day"),
                        str("sleep_label_night"),
                        num("sleep_from", -1),
                        num("sleep_to", -1),
                    )
                    val hasSleep = sleepText.isNotEmpty()
                    setViewVisibility(R.id.sleep_chip, if (hasSleep) View.VISIBLE else View.GONE)
                    setViewVisibility(R.id.sleep_label, if (hasSleep) View.VISIBLE else View.GONE)
                    setTextViewText(R.id.sleep_label, sleepText)
                    setTextViewText(R.id.streak_value, "$streak")
                    setTextViewText(R.id.streak_label, streakLabel)
                    setTextViewText(R.id.next_label, nextLabel)
                    setTextViewText(R.id.record_value, "${num("record")}")
                    setTextViewText(R.id.record_label, str("record_label").substringBefore(' '))
                    tint(R.id.tile_streak, theme.primaryContainer)
                    tint(R.id.floor, theme.trackOnContainer)
                    tint(R.id.tile_progress, theme.primaryContainer)
                    tint(R.id.tile_record, theme.primaryContainer)
                    tint(R.id.stage_chip, theme.surfaceContainer)
                    tint(R.id.sleep_chip, theme.tertiaryContainer)
                    setTextColor(R.id.name, theme.onSurface)
                    setTextColor(R.id.sleep_label, theme.onTertiaryContainer)
                    setTextColor(R.id.streak_value, theme.onPrimaryContainer)
                    setTextColor(R.id.record_value, theme.onPrimaryContainer)
                    size(R.id.streak_value, 24f * scale)
                    size(R.id.record_value, 24f * scale)
                    progressInto(R.id.progress, (widthDp - 36) / 3, theme, num("progress"), density)
                }
            }

            setOnClickPendingIntent(R.id.widget_root, openApp(context))
        }

        manager.updateAppWidget(widgetId, views)
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

    private fun openApp(context: Context) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        android.net.Uri.parse("loveapp://mascot"),
    )
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
