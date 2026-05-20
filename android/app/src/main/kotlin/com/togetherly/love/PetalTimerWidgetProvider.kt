package com.togetherly.love

import android.app.AlarmManager
import java.util.Calendar
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.*
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.*

class PetalTimerWidgetProvider : HomeWidgetProvider() {

    // ─── Цветовые палитры по теме ───────────────────────────────────────────
    // Индексы: 0=pink, 1=purple, 2=blue, 3=orange, 4=green
    private val ROMANTIC_BG = arrayOf("#2D1F48", "#231E3A", "#1B2035", "#2A1E18", "#1A2A1F")
    private val ROMANTIC_FG = arrayOf("#FF7E8B", "#9B86BD", "#7898BF", "#CF7E5E", "#7EA876")
    private val NEUTRAL_BG  = "#2A2010"
    private val NEUTRAL_FG  = "#E8A020"

    private val colorTextVal = Color.WHITE
    private val colorTextLbl = Color.argb(165, 255, 255, 255)

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

                val countdown  = widgetData.getString("timer_is_countdown", "0") == "1"
                val startMs    = widgetData.getString("timer_start_ms", "0")?.toLongOrNull() ?: 0L
                val isRomantic = widgetData.getString("timer_is_romantic", "1") != "0"
                val themeIdx   = (widgetData.getString("petal_theme_index", "0")?.toIntOrNull() ?: 0)
                                     .coerceIn(0, ROMANTIC_BG.lastIndex)

                val bgHex = if (isRomantic) ROMANTIC_BG[themeIdx] else NEUTRAL_BG
                val fgHex = if (isRomantic) ROMANTIC_FG[themeIdx] else NEUTRAL_FG

                val bmpSize = 400
                val bmp = Bitmap.createBitmap(bmpSize, bmpSize, Bitmap.Config.ARGB_8888)
                drawDial(Canvas(bmp), bmpSize.toFloat(), startMs, countdown,
                         Color.parseColor(bgHex), Color.parseColor(fgHex))
                setImageViewBitmap(R.id.petal_dial_image, bmp)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
        scheduleNextTick(context)
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleNextTick(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelTick(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) {
            val awm  = AppWidgetManager.getInstance(context)
            val ids  = awm.getAppWidgetIds(ComponentName(context, PetalTimerWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                onUpdate(context, awm, ids, prefs)
            } else {
                cancelTick(context)
            }
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

    private fun zeroPetals() = listOf(
        Petal("лет",  0, 100, 0.0),
        Petal("мес",  0, 12,  0.0),
        Petal("дн",   0, 30,  0.0),
        Petal("ч",    0, 24,  0.0),
        Petal("мин",  0, 60,  0.0),
        Petal("сек",  0, 60,  0.0),
    )

    private fun computePetals(startMs: Long, countdown: Boolean): List<Petal> {
        if (startMs == 0L) return zeroPetals()

        val nowMs  = System.currentTimeMillis()
        val fromMs = if (countdown) nowMs   else startMs
        val toMs   = if (countdown) startMs else nowMs
        if (toMs <= fromMs) return zeroPetals()

        val from = Calendar.getInstance().apply { timeInMillis = fromMs }
        val to   = Calendar.getInstance().apply { timeInMillis = toMs }

        var years  = to.get(Calendar.YEAR)         - from.get(Calendar.YEAR)
        var months = to.get(Calendar.MONTH)        - from.get(Calendar.MONTH)
        var days   = to.get(Calendar.DAY_OF_MONTH) - from.get(Calendar.DAY_OF_MONTH)

        if (days < 0) {
            months--
            val tmp = (to.clone() as Calendar).apply { add(Calendar.MONTH, -1) }
            days += tmp.getActualMaximum(Calendar.DAY_OF_MONTH)
        }
        if (months < 0) {
            years--
            months += 12
        }

        val diffMs = toMs - fromMs
        val hI   = (diffMs / 3_600_000L) % 24
        val minI = (diffMs / 60_000L)    % 60
        val sI   = (diffMs / 1_000L)     % 60

        return listOf(
            Petal("лет",  years.toLong(),  100, years  + months / 12.0),
            Petal("мес",  months.toLong(), 12,  months + days   / 30.0),
            Petal("дн",   days.toLong(),   30,  days   + hI     / 24.0),
            Petal("ч",    hI,              24,  hI     + minI   / 60.0),
            Petal("мин",  minI,            60,  minI   + sI     / 60.0),
            Petal("сек",  sI,              60,  sI.toDouble()),
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Рисование циферблата (прозрачный фон)
    // ─────────────────────────────────────────────────────────────────────────

    private fun drawDial(canvas: Canvas, size: Float, startMs: Long, countdown: Boolean,
                         colorPetalBg: Int, colorPetalFg: Int) {
        val petals = computePetals(startMs, countdown)
        val scale  = size / 280f

        canvas.translate(size / 2f, size / 2f)

        val outerR   = size / 2f - 2f
        val innerR   = outerR * 0.15f
        val cr       = 4f * scale
        val gapWidth = 6f * scale

        val rigidInner = innerR + cr
        val rigidOuter = outerR - cr
        val h          = gapWidth / 2f + cr

        val n         = petals.size.toFloat()
        val sweep     = 2f * PI.toFloat() / n
        val sweepHalf = sweep / 2f

        var startAngle = -PI.toFloat() / 2f

        for ((_, petal) in petals.withIndex()) {
            val segAngle = startAngle + sweepHalf

            canvas.save()
            canvas.rotate(Math.toDegrees(segAngle.toDouble()).toFloat())

            val bgPath = buildSector(rigidOuter, rigidInner, h, sweepHalf)
            canvas.drawPath(bgPath, fillPaint(colorPetalBg))
            canvas.drawPath(bgPath, strokePaint(colorPetalBg, cr))

            val factor = petal.factor
            if (factor > 0.01f) {
                val fgOuter = max(rigidInner + 0.1f, innerR + (outerR - innerR) * factor - cr)
                val fgPath  = buildSector(fgOuter, rigidInner, h, sweepHalf)
                canvas.drawPath(fgPath, fillPaint(colorPetalFg))
                canvas.drawPath(fgPath, strokePaint(colorPetalFg, cr))
            }

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
    //  Построение контура лепестка
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
            val tIn = sqrt(inner * inner - h * h)
            pInTopX = tIn * cos(topA) + h * sin(topA)
            pInTopY = tIn * sin(topA) - h * cos(topA)
            pInBotX = tIn * cos(botA) - h * sin(botA)
            pInBotY = tIn * sin(botA) + h * cos(botA)
        } else {
            val xInt = h / sin(sweepHalf)
            pInTopX = xInt; pInTopY = 0f
            pInBotX = xInt; pInBotY = 0f
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
        val fm     = paint.fontMetrics
        val offset = -(fm.ascent + fm.descent) / 2f
        canvas.drawText(text, x, y + offset, paint)
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  AlarmManager — живые обновления каждую секунду
    // ─────────────────────────────────────────────────────────────────────────

    companion object {
        const val ACTION_TICK = "com.togetherly.love.PETAL_TIMER_TICK"
        private const val TICK_MS = 1000L

        private fun tickIntent(context: Context): PendingIntent {
            val intent = Intent(context, PetalTimerWidgetProvider::class.java).apply {
                action = ACTION_TICK
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else
                PendingIntent.FLAG_UPDATE_CURRENT
            return PendingIntent.getBroadcast(context, 42, intent, flags)
        }

        fun scheduleNextTick(context: Context) {
            val am      = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi      = tickIntent(context)
            val trigger = System.currentTimeMillis() + TICK_MS
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                    if (am.canScheduleExactAlarms())
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC, trigger, pi)
                    else
                        am.set(AlarmManager.RTC, trigger, pi)
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC, trigger, pi)
                else ->
                    am.setExact(AlarmManager.RTC, trigger, pi)
            }
        }

        fun cancelTick(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(tickIntent(context))
        }
    }
}
