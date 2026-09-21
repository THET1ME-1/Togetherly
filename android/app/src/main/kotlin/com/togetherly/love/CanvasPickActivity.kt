package com.togetherly.love

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Выбор холста для виджета.
 *
 * Открывается двумя путями: система зовёт её при добавлении виджета
 * (`android:configure`), а на Android 12+ человек открывает её сам долгим
 * нажатием по виджету и кнопкой «Настроить» (`widgetFeatures=reconfigurable`).
 *
 * Список холстов и картинки к ним готовит приложение — те же файлы, что
 * показывает сам виджет. Своей сети и своей базы у экрана нет: он читает
 * `HomeWidgetPreferences` и пишет туда выбор экземпляра.
 */
class CanvasPickActivity : Activity() {

    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        // Пока человек не выбрал, результат ОТМЕНА: система тогда не оставит
        // на столе виджет, от которого отказались.
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.tg_canvas_pick)

        val data = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val theme = WidgetTheme.from(data)
        val group = WidgetGroupHelper.getOrBind(this, "canvas", widgetId)
        val prefix = if (group.isEmpty()) "canvas_solo_" else "canvas_${group}_"

        window.decorView.setBackgroundColor(theme.surface)
        findViewById<TextView>(R.id.title).apply {
            text = getString(R.string.tg_canvas_pick_title)
            setTextColor(theme.onSurface)
        }
        val subtitle = findViewById<TextView>(R.id.subtitle).apply {
            setTextColor(theme.onSurfaceVariant)
        }

        val ids = data.getString("${prefix}list", null).orEmpty()
            .split(',')
            .filter { it.isNotBlank() }

        val list = findViewById<LinearLayout>(R.id.list)
        if (ids.isEmpty()) {
            subtitle.text = getString(R.string.tg_canvas_pick_empty)
            return
        }

        subtitle.text = getString(R.string.tg_canvas_pick_subtitle)
        val chosen = data.getString(canvasKey(widgetId), null).orEmpty()
        val active = data.getString("${prefix}active", null).orEmpty()

        ids.forEach { id ->
            val path = data.getString("$prefix${id}_path", null).orEmpty()
            val name = data.getString("$prefix${id}_name", null).orEmpty()
            list.addView(row(id, name, path, theme, selected = id == chosen.ifEmpty { active }))
        }
    }

    /** Плитка холста: картинка, имя и отклик на нажатие. */
    private fun row(
        id: String,
        name: String,
        path: String,
        theme: WidgetTheme,
        selected: Boolean,
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(10) }
            background = roundedBackground(
                if (selected) theme.primaryContainer else theme.surfaceContainer,
            )
            isClickable = true
            setOnClickListener { choose(id) }
        }

        row.addView(ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(70))
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = roundedBackground(Color.WHITE, radius = 12f)
            clipToOutline = true
            WidgetImages.fitted(path, dp(140))?.let { setImageBitmap(it) }
        })

        row.addView(TextView(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginStart = dp(14) }
            text = name.ifEmpty { getString(R.string.tg_canvas_unnamed) }
            setTextColor(if (selected) theme.onPrimaryContainer else theme.onSurface)
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 16f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        })

        return row
    }

    private fun choose(canvasId: String) {
        getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString(canvasKey(widgetId), canvasId)
            .apply()

        // Виджет перерисовываем сами: система после настройки присылает
        // обновление не всем хостам, и на MIUI плитка осталась бы пустой.
        val manager = AppWidgetManager.getInstance(this)
        for (cls in listOf(
            CanvasWidget2x2Provider::class.java,
            CanvasWidget2x3Provider::class.java,
            CanvasWidget4x4Provider::class.java,
        )) {
            val ids = manager.getAppWidgetIds(android.content.ComponentName(this, cls))
            if (ids.contains(widgetId)) {
                sendBroadcast(Intent(this, cls).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
                })
            }
        }

        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }

    private fun roundedBackground(color: Int, radius: Float = 20f) =
        android.graphics.drawable.GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius.toInt()).toFloat()
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        /** Выбор живёт у экземпляра виджета, а не у пары. */
        fun canvasKey(widgetId: Int) = "widget_canvas_$widgetId"
    }
}
