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
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Заметка на двоих» — общий листик на рабочем столе.
 *
 * Что написал один, видит другой: текст живёт в `widget_data` пары и приезжает
 * той же дорогой, что настроение и сообщения.
 *
 * Печатать прямо в виджете Android не даёт — `EditText` в RemoteViews не
 * поддерживается. Поэтому тап открывает [NoteEditorActivity]: прозрачное окно
 * поверх рабочего стола в облике самого листика, без анимации и без перехода в
 * приложение. Так же устроены Google Keep и Todoist.
 *
 * Два стиля на выбор при установке: бумажный стикер (тёплая бумага, линейки,
 * «скрепка») и карточка M3 (перекрашивается вместе с темой приложения).
 */
open class NoteWidgetProvider : HomeWidgetProvider() {

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
        WidgetGroupHelper.clearBindings(context, "note", appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val group = WidgetGroupHelper.getOrBind(context, "note", widgetId)
        val prefix = if (group.isEmpty()) "" else "note_${group}_"

        val text = data.getString("${prefix}text", null).orEmpty()
        val author = data.getString("${prefix}author", null).orEmpty()
        val time = data.getString("${prefix}time", null).orEmpty()
        // Стиль выбирается в каталоге приложения до установки и живёт у
        // конкретного экземпляра: на столе могут стоять оба сразу.
        val paper = data.getString("widget_note_${widgetId}_style", null)
            ?: data.getString("note_next_style", null).also { style ->
                if (style != null) {
                    data.edit()
                        .putString("widget_note_${widgetId}_style", style)
                        .remove("note_next_style")
                        .apply()
                }
            } ?: "m3"
        val isPaper = paper == "paper"

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        val layout = forcedLayout ?: when {
            minWidth >= 200 && minHeight >= 200 -> R.layout.tg_note_4x4
            minWidth >= 200 -> R.layout.tg_note_4x2
            else -> R.layout.tg_note_2x2
        }

        val baseDp = if (layout == R.layout.tg_note_4x4) 250 else 115
        val scale = WidgetSizing.scale(minHeight, baseDp)
        val theme = WidgetTheme.from(data)

        // Бумага не берёт цвета темы: смысл стикера в том, что он всегда
        // жёлтый и его видно на любых обоях.
        val bg = if (isPaper) PAPER_BG else theme.surfaceContainer
        val ink = if (isPaper) PAPER_INK else theme.onSurface
        val faded = if (isPaper) PAPER_FADED else theme.onSurfaceVariant

        val views = RemoteViews(context.packageName, layout).apply {
            tint(R.id.bg, bg)

            setViewVisibility(R.id.paper_lines, if (isPaper) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.paper_clip, if (isPaper) View.VISIBLE else View.GONE)
            setViewVisibility(R.id.head, if (isPaper) View.GONE else View.VISIBLE)
            if (isPaper) {
                tint(R.id.paper_lines, PAPER_LINE)
                tint(R.id.paper_clip, PAPER_CLIP)
            } else {
                tint(R.id.head_chip, theme.primaryContainer)
                tint(R.id.head_icon, theme.onPrimaryContainer)
                setTextColor(R.id.head_title, faded)
            }

            val empty = text.isBlank()
            setTextViewText(
                R.id.note_text,
                if (empty) context.getString(R.string.tg_note_empty) else text,
            )
            setTextColor(R.id.note_text, if (empty) faded else ink)
            setTextViewTextSize(
                R.id.note_text,
                TypedValue.COMPLEX_UNIT_DIP,
                (if (layout == R.layout.tg_note_2x2) 13f else 14f) * scale,
            )

            // Подпись — кто писал последним. Пока не писал никто, строку прячем:
            // пустая полоска внизу выглядит как обрезанный текст.
            val hasAuthor = author.isNotBlank()
            setViewVisibility(R.id.foot, if (hasAuthor) View.VISIBLE else View.GONE)
            if (hasAuthor) {
                tint(
                    R.id.author_dot,
                    if (isPaper) PAPER_CLIP else theme.tertiaryContainer,
                )
                setTextColor(R.id.author_line, faded)
                setTextViewText(
                    R.id.author_line,
                    if (time.isBlank()) author else "$author · $time",
                )
            }

            tint(R.id.pencil_bg, if (isPaper) PAPER_PENCIL else theme.primary)
            tint(R.id.pencil_icon, if (isPaper) PAPER_BG else theme.onPrimary)

            val edit = editIntent(context, widgetId, group, text)
            setOnClickPendingIntent(R.id.widget_root, edit)
            setOnClickPendingIntent(R.id.pencil_bg, edit)
            setOnClickPendingIntent(R.id.pencil_icon, edit)
        }

        manager.updateAppWidget(widgetId, views)
    }

    /** Окно правки: открывается поверх рабочего стола, без анимации. */
    private fun editIntent(
        context: Context,
        widgetId: Int,
        group: String,
        text: String,
    ): PendingIntent {
        val intent = Intent(context, NoteEditorActivity::class.java).apply {
            putExtra(NoteEditorActivity.EXTRA_GROUP, group)
            putExtra(NoteEditorActivity.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
        return PendingIntent.getActivity(
            context,
            widgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        // Бумага: тёплый жёлтый и коричневые чернила — те же, что в макете.
        private const val PAPER_BG = 0xFFFFF3C4.toInt()
        private const val PAPER_INK = 0xFF4A3D13.toInt()
        private const val PAPER_FADED = 0xFF8A7A45.toInt()
        private const val PAPER_LINE = 0xFF4A3D13.toInt()
        private const val PAPER_CLIP = 0x33000000
        private const val PAPER_PENCIL = 0xFF4A3D13.toInt()

        /** Перерисовать все листики: текст поменялся у одного из двоих.
         *
         * Через штатный бродкаст обновления, а не вызовом render напрямую: так
         * не нужна рефлексия и путь ровно тот же, каким виджет обновляет
         * система.
         */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(
                NoteWidget2x2Provider::class.java,
                NoteWidget4x2Provider::class.java,
                NoteWidget4x4Provider::class.java,
            ).forEach { cls ->
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                if (ids.isEmpty()) return@forEach
                context.sendBroadcast(
                    Intent(context, cls).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                )
            }
        }
    }
}

class NoteWidget2x2Provider : NoteWidgetProvider() {
    override val forcedLayout = R.layout.tg_note_2x2
}

class NoteWidget4x2Provider : NoteWidgetProvider() {
    override val forcedLayout = R.layout.tg_note_4x2
}

class NoteWidget4x4Provider : NoteWidgetProvider() {
    override val forcedLayout = R.layout.tg_note_4x4
}
