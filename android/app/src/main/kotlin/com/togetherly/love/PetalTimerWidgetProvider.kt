package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.*
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.*

/**
 * Виджет «Лепестковый таймер» — живая копия PetalTimerDial из главного меню.
 * Рисует 6-секторный доnut-циферблат на Bitmap через Android Canvas.
 */
class PetalTimerWidgetProvider : HomeWidgetProvider() {

    // ── Цвета (совпадают с Flutter-темой) ────────────────────────────────────
    private val colorBg       = Color.parseColor("#1E1030")  // фон виджета
    private val colorPetalBg  = Color.parseColor("#2D1F48")  // трек лепестка
    private val colorPetalFg  = Color.parseColor("#EC4899")  // заполнение
    private val colorTextVal  = Color.WHITE
    private val colorTextLbl  = Color.argb(165, 255, 255, 255)

    // ─────────────────────────────────────────────────────────────────────────
    //  onUpdate
    // ─────────────────────────────────────────────────────────────────────────

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.petal_timer_widget).apply {

                val pi = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("loveapp://home")
                )
                setOnClickPendingIntent(R.id.widget_root, pi)

                // ── Данные из SharedPreferences ──
                val title     = widgetData.getString("timer_title", null).takeIf { !it.isNullOrEmpty() } ?: "Таймер"
                val emoji     = widgetData.getString("timer_emoji", null).takeIf { !it.isNullOrEmpty() } ?: "⏱"
                val countdown = widgetData.getString("timer_is_countdown", "0") == "1"
                val startMs   = widgetData.getString("timer_start_ms", "0")?.toLongOrNull() ?: 0L

                setTextViewText(R.id.petal_timer_title, "$emoji  $title")

                // ── Рисуем циферблат ──
                val bmpSize = 400
                val bmp = Bitmap.createBitmap(bmpSize, bmpSize, Bitmap.Config.ARGB_8888)
                drawDial(Canvas(bmp), bmpSize.toFloat(), startMs, countdown)
                setImageViewBitmap(R.id.petal_dial_image, bmp)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Вычисление лепестков
    // ─────────────────────────────────────────────────────────────────────────

    private data class Petal(
        val label: String,
        val value: Long,
        val maxValue: Long,
        val exact: Double,
    ) {
        val factor: Float get() =
            if (maxValue > 0) (exact / maxValue).toFloat().coerceIn(0f, 1f) else 0f
    }

    private fun computePetals(startMs: Long, countdown: Boolean): List<Petal> {
        val now    = System.currentTimeMillis()
        val diffMs = abs(if (countdown) startMs - now else now - startMs)
        val sec    = diffMs / 1000.0

        val yI = (sec / (365.25 * 86400)).toLong()
        val moI = (sec / (30.44 * 86400)).toLong() % 12
        val dI = (sec / 86400).toLong() % 30
        val hI = (sec / 3600).toLong() % 24
        val minI = (sec / 60).toLong() % 60
        val sI = sec.toLong() % 60

        return listOf(
            Petal("лет",  yI,   100, sec / (365.25 * 86400)),
            Petal("мес",  moI,  12,  (sec / (30.44 * 86400)) % 12.0),
            Petal("дн",   dI,   30,  (sec / 86400) % 30.0),
            Petal("ч",    hI,   24,  (sec / 3600) % 24.0),
            Petal("мин",  minI, 60,  (sec / 60) % 60.0),
            Petal("сек",  sI,   60,  sec % 60.0),
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Рисование циферблата
    // ─────────────────────────────────────────────────────────────────────────

    private fun drawDial(canvas: Canvas, size: Float, startMs: Long, countdown: Boolean) {
        val petals = computePetals(startMs, countdown)
        val scale  = size / 280f

        canvas.translate(size / 2f, size / 2f)

        val outerR     = size / 2f - 2f
        val innerR     = outerR * 0.15f
        val cr         = 4f * scale
        val gapWidth   = 6f * scale

        val rigidInner = innerR + cr
        val rigidOuter = outerR - cr
        val h          = gapWidth / 2f + cr

        val n          = petals.size.toFloat()
        val sweep      = 2f * PI.toFloat() / n
        val sweepHalf  = sweep / 2f

        var startAngle = -PI.toFloat() / 2f

        for ((idx, petal) in petals.withIndex()) {
            val segAngle = startAngle + sweepHalf

            canvas.save()
            canvas.rotate(Math.toDegrees(segAngle.toDouble()).toFloat())

            // ── Фоновый трек ──
            val bgPath = buildSector(rigidOuter, rigidInner, h, sweepHalf)
            canvas.drawPath(bgPath, fillPaint(colorPetalBg))
            canvas.drawPath(bgPath, strokePaint(colorPetalBg, cr))

            // ── Заполнение (значение) ──
            val factor = petal.factor
            if (factor > 0.01f) {
                val fgOuter = max(rigidInner + 0.1f, innerR + (outerR - innerR) * factor - cr)
                val fgPath  = buildSector(fgOuter, rigidInner, h, sweepHalf)
                canvas.drawPath(fgPath, fillPaint(colorPetalFg))
                canvas.drawPath(fgPath, strokePaint(colorPetalFg, cr))
            }

            // ── Текст ──
            val textR = (innerR + outerR) / 2f
            canvas.save()
            canvas.translate(textR, 0f)
            canvas.rotate(-Math.toDegrees(segAngle.toDouble()).toFloat())
            drawCenteredText(canvas, petal.value.toString(), 0f, -9f * scale, 18f * scale, Typeface.DEFAULT_BOLD, colorTextVal)
            drawCenteredText(canvas, petal.label, 0f, 11f * scale, 9f * scale, Typeface.DEFAULT, colorTextLbl)
            canvas.restore()

            canvas.restore()
            startAngle += sweep
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Построение контура лепестка (порт _buildParallelRigidSector из Flutter)
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildSector(outer: Float, inner: Float, h: Float, sweepHalf: Float): Path {
        val path = Path()
        if (outer <= h || outer <= inner) return path

        val topA = sweepHalf
        val botA = -sweepHalf

        val tOut     = sqrt(outer * outer - h * h)
        val pOutTopX = tOut * cos(topA) + h * sin(topA)
        val pOutTopY = tOut * sin(topA) - h * cos(topA)
        val pOutBotX = tOut * cos(botA) - h * sin(botA)
        val pOutBotY = tOut * sin(botA) + h * cos(botA)

        val pInTopX: Float
        val pInTopY: Float
        val pInBotX: Float
        val pInBotY: Float

        if (inner > h) {
            val tIn  = sqrt(inner * inner - h * h)
            pInTopX  = tIn * cos(topA) + h * sin(topA)
            pInTopY  = tIn * sin(topA) - h * cos(topA)
            pInBotX  = tIn * cos(botA) - h * sin(botA)
            pInBotY  = tIn * sin(botA) + h * cos(botA)
        } else {
            val xInt = h / sin(sweepHalf)
            pInTopX  = xInt; pInTopY = 0f
            pInBotX  = xInt; pInBotY = 0f
        }

        val aOutTop = atan2(pOutTopY, pOutTopX)
        val aOutBot = atan2(pOutBotY, pOutBotX)

        path.moveTo(pInBotX, pInBotY)
        path.lineTo(pOutBotX, pOutBotY)

        if (aOutTop > aOutBot) {
            val rect = RectF(-outer, -outer, outer, outer)
            path.arcTo(
                rect,
                Math.toDegrees(aOutBot.toDouble()).toFloat(),
                Math.toDegrees((aOutTop - aOutBot).toDouble()).toFloat(),
            )
        }

        path.lineTo(pInTopX, pInTopY)

        if (inner > h) {
            val aInTop = atan2(pInTopY, pInTopX)
            val aInBot = atan2(pInBotY, pInBotX)
            val rect   = RectF(-inner, -inner, inner, inner)
            path.arcTo(
                rect,
                Math.toDegrees(aInTop.toDouble()).toFloat(),
                Math.toDegrees((aInBot - aInTop).toDouble()).toFloat(),
            )
        } else {
            path.lineTo(pInBotX, pInBotY)
        }

        path.close()
        return path
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Paint helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun fillPaint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style      = Paint.Style.FILL
        strokeJoin = Paint.Join.ROUND
    }

    private fun strokePaint(color: Int, cr: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color  = color
        style       = Paint.Style.STROKE
        strokeWidth = cr * 2f
        strokeJoin  = Paint.Join.ROUND
    }

    private fun drawCenteredText(
        canvas: Canvas,
        text: String,
        x: Float,
        y: Float,
        textSizePx: Float,
        typeface: Typeface,
        color: Int,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color    = color
            this.textSize = textSizePx
            this.typeface = typeface
            textAlign     = Paint.Align.CENTER
        }
        // Центрируем по вертикали относительно y
        val fm     = paint.fontMetrics
        val offset = -(fm.ascent + fm.descent) / 2f
        canvas.drawText(text, x, y + offset, paint)
    }
}
