package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Рисунок на столе»: общий холст пары и ничего больше.
 *
 * Картинку рисует приложение (`lib/services/canvas/canvas_widget_service.dart`)
 * тем же художником, что и плитки галереи, и кладёт файл на диск. Виджету
 * остаётся показать её: штрихи живут в Postgres, а у него нет ни сессии, ни
 * времени на запрос.
 *
 * Какой холст показывать, человек выбирает сам — при добавлении виджета
 * (`android:configure`) и потом через «Настроить» (`reconfigurable`, Android
 * 12+). Выбор лежит у экземпляра: `widget_canvas_<widgetId>`. Пусто — берём
 * тот холст, который трогали последним.
 */
open class CanvasWidgetProvider : HomeWidgetProvider() {

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
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val edit = data.edit()
        appWidgetIds.forEach { edit.remove(CanvasPickActivity.canvasKey(it)) }
        edit.apply()
        WidgetGroupHelper.clearBindings(context, "canvas", appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val group = WidgetGroupHelper.getOrBind(context, "canvas", widgetId)
        val prefix = if (group.isEmpty()) "canvas_solo_" else "canvas_${group}_"

        val chosen = data.getString(CanvasPickActivity.canvasKey(widgetId), null).orEmpty()
        val active = data.getString("${prefix}active", null).orEmpty()
        val canvasId = chosen.ifEmpty { active }
        val path = if (canvasId.isEmpty()) "" else
            data.getString("${prefix}${canvasId}_path", null).orEmpty()

        val theme = WidgetTheme.from(data)
        val layout = forcedLayout ?: R.layout.tg_canvas_2x2

        val views = RemoteViews(context.packageName, layout).apply {
            tint(R.id.bg, theme.surfaceContainer)

            val options = manager.getAppWidgetOptions(widgetId)
            val (cellW, cellH) = WidgetSizing.cellDp(context, options)
            val density = context.resources.displayMetrics.density
            val side = ((maxOf(cellW, cellH).takeIf { it > 0 } ?: 160) * density).toInt()
            val bitmap = WidgetImages.fitted(path, side.coerceAtMost(900))

            if (bitmap != null) {
                setImageViewBitmap(R.id.canvas, bitmap)
                setViewVisibility(R.id.canvas, View.VISIBLE)
                setViewVisibility(R.id.empty_label, View.GONE)
            } else {
                // Пустой виджет обязан называть себя, иначе человек решит, что
                // он не добавился.
                setViewVisibility(R.id.canvas, View.GONE)
                setViewVisibility(R.id.empty_label, View.VISIBLE)
                setTextViewText(R.id.empty_label, context.getString(R.string.tg_canvas_empty))
                setTextColor(R.id.empty_label, theme.onSurfaceVariant)
            }

            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    // Ссылка несёт номер холста: без него человек попадёт в
                    // список и будет искать свой рисунок глазами.
                    android.net.Uri.parse(
                        if (canvasId.isEmpty()) "loveapp://draw"
                        else "loveapp://draw?canvas=$canvasId"
                    ),
                ),
            )
        }

        manager.updateAppWidget(widgetId, views)
    }
}

class CanvasWidget2x2Provider : CanvasWidgetProvider() {
    override val forcedLayout = R.layout.tg_canvas_2x2
}

class CanvasWidget2x3Provider : CanvasWidgetProvider() {
    override val forcedLayout = R.layout.tg_canvas_2x3
}

class CanvasWidget4x4Provider : CanvasWidgetProvider() {
    override val forcedLayout = R.layout.tg_canvas_4x4
}
