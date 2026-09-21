package com.togetherly.love

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/**
 * Рисование прямо с рабочего стола.
 *
 * Рисовать внутри виджета Android не даёт: `RemoteViews` инфлейтит только
 * классы белого списка, своей вью там быть не может. Обход тот же, что у
 * «Заметки на двоих» — прозрачное окно поверх стола в облике самого виджета.
 * Человек видит свой холст и продолжает рисунок, не заходя в приложение.
 *
 * Новые штрихи уходят двумя путями сразу: картинка виджета переписывается
 * здесь же (отклик мгновенный), а сами точки — фоновому Dart
 * (`loveapp://canvas-stroke`), который пишет их в базу и показывает партнёру.
 */
class CanvasDrawOverlayActivity : Activity() {

    private lateinit var sheet: DrawSheet
    private var canvasId = ""
    private var group = ""
    private var imagePath = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_canvas_draw)

        canvasId = intent.getStringExtra(EXTRA_CANVAS).orEmpty()
        group = intent.getStringExtra(EXTRA_GROUP).orEmpty()
        imagePath = intent.getStringExtra(EXTRA_IMAGE).orEmpty()

        val data = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val theme = WidgetTheme.from(data)

        findViewById<View>(R.id.card).setBackgroundColor(theme.surface)
        findViewById<ImageView>(R.id.sheet_image).apply {
            WidgetImages.fitted(imagePath, 1200)?.let { setImageBitmap(it) }
        }

        sheet = findViewById(R.id.sheet_draw)
        sheet.color = theme.primary

        findViewById<TextView>(R.id.done).apply {
            text = getString(R.string.tg_canvas_draw_done)
            setTextColor(theme.onPrimary)
            background = pill(theme.primary)
            setOnClickListener { finishWithStrokes() }
        }

        findViewById<TextView>(R.id.undo).apply {
            text = getString(R.string.tg_canvas_draw_undo)
            setTextColor(theme.onSurface)
            background = pill(theme.surfaceContainer)
            setOnClickListener { sheet.undo() }
        }

        // Палитра: цвета темы пары плюс чёрный и белый — большего на столе не
        // нужно, полный набор кистей живёт в приложении.
        val colors = listOf(
            theme.primary, theme.tertiary, theme.onSurface,
            Color.WHITE, Color.parseColor("#4C8BF5"), Color.parseColor("#3FA65B"),
        )
        val row = findViewById<LinearLayout>(R.id.colors)
        colors.forEach { c ->
            row.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(28), dp(28))
                    .apply { marginEnd = dp(10) }
                background = circle(c)
                setOnClickListener { sheet.color = c }
            })
        }
    }

    /** Складывает нарисованное в картинку виджета и будит фоновый Dart. */
    private fun finishWithStrokes() {
        val strokes = sheet.strokes
        if (strokes.isEmpty()) {
            finish()
            return
        }

        val payload = JSONArray()
        strokes.forEach { s ->
            val points = JSONArray()
            s.points.forEach { p ->
                points.put(JSONObject().apply {
                    // Точки в долях листа: так их хранит и приложение, иначе
                    // рисунок съехал бы у партнёра с другим экраном.
                    put("x", p.x / sheet.width.toFloat())
                    put("y", p.y / sheet.height.toFloat())
                })
            }
            payload.put(JSONObject().apply {
                put("points", points)
                put("colorValue", s.color.toLong() and 0xFFFFFFFFL)
                put("strokeWidth", s.width / resources.displayMetrics.density)
                put("isEraser", false)
            })
        }

        getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("canvas_pending_strokes", payload.toString())
            .putString("canvas_pending_canvas", canvasId)
            .putString("canvas_pending_group", group)
            .apply()

        bakeIntoWidgetImage()
        refreshWidgets()

        // Отправку в базу делает фоновый Dart: у окна нет ни сессии, ни
        // репозитория, а ждать сеть, держа человека на экране, незачем.
        HomeWidgetBackgroundIntent.getBroadcast(
            this,
            android.net.Uri.parse("loveapp://canvas-stroke?canvas=$canvasId&group=$group"),
        ).send()

        finish()
    }

    /**
     * Дорисовывает новые линии прямо в картинку виджета.
     *
     * Так рисунок появляется на столе сразу, не дожидаясь базы и перерисовки
     * приложением. Настоящий рендер придёт следом и перепишет файл.
     */
    private fun bakeIntoWidgetImage() {
        if (imagePath.isEmpty()) return
        val file = File(imagePath)
        if (!file.exists()) return
        try {
            val src = android.graphics.BitmapFactory.decodeFile(imagePath) ?: return
            val out = src.copy(Bitmap.Config.ARGB_8888, true)
            src.recycle()
            val canvas = Canvas(out)
            val kx = out.width / sheet.width.toFloat()
            val ky = out.height / sheet.height.toFloat()
            sheet.strokes.forEach { s ->
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = s.color
                    style = Paint.Style.STROKE
                    strokeWidth = s.width * kx
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                }
                val path = Path()
                s.points.forEachIndexed { i, p ->
                    val x = p.x * kx
                    val y = p.y * ky
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                canvas.drawPath(path, paint)
            }
            FileOutputStream(file).use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
            out.recycle()
        } catch (e: Exception) {
            android.util.Log.e("CanvasDraw", "картинка не переписалась", e)
        }
    }

    private fun refreshWidgets() {
        val manager = android.appwidget.AppWidgetManager.getInstance(this)
        listOf(
            CanvasWidget2x2Provider::class.java,
            CanvasWidget2x3Provider::class.java,
            CanvasWidget4x4Provider::class.java,
        ).forEach { cls ->
            val ids = manager.getAppWidgetIds(android.content.ComponentName(this, cls))
            if (ids.isEmpty()) return@forEach
            sendBroadcast(Intent(this, cls).apply {
                action = android.appwidget.AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            })
        }
    }

    private fun pill(color: Int) = android.graphics.drawable.GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(22).toFloat()
    }

    private fun circle(color: Int) = android.graphics.drawable.GradientDrawable().apply {
        shape = android.graphics.drawable.GradientDrawable.OVAL
        setColor(color)
        setStroke(dp(1), Color.argb(40, 0, 0, 0))
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_CANVAS = "canvas"
        const val EXTRA_GROUP = "group"
        const val EXTRA_IMAGE = "image"
    }
}

/** Лист, на котором рисуют пальцем поверх картинки холста. */
class DrawSheet(context: Context, attrs: android.util.AttributeSet?) : View(context, attrs) {

    class Stroke(val color: Int, val width: Float) {
        val points = mutableListOf<android.graphics.PointF>()
        val path = Path()
    }

    val strokes = mutableListOf<Stroke>()
    var color: Int = Color.BLACK
    var strokeWidth: Float = 6f * resources.displayMetrics.density

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        strokes.forEach { s ->
            paint.color = s.color
            paint.strokeWidth = s.width
            canvas.drawPath(s.path, paint)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val s = Stroke(color, strokeWidth)
                s.path.moveTo(event.x, event.y)
                s.points.add(android.graphics.PointF(event.x, event.y))
                strokes.add(s)
            }

            MotionEvent.ACTION_MOVE -> {
                strokes.lastOrNull()?.let { s ->
                    s.path.lineTo(event.x, event.y)
                    s.points.add(android.graphics.PointF(event.x, event.y))
                }
            }
        }
        invalidate()
        return true
    }

    fun undo() {
        strokes.removeLastOrNull()
        invalidate()
    }
}
