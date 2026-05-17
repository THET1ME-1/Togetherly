package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.PI
import kotlin.math.sin

class MoodWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val TAG = "MoodWidgetProvider"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.mood_widget)

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://mood")
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                views.setViewVisibility(R.id.layout_2_users, View.VISIBLE)
                views.setViewVisibility(R.id.layout_3_users, View.GONE)
                views.setViewVisibility(R.id.layout_4_users, View.GONE)

                populateMoodPreview(views, widgetData)

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Error updating widget $widgetId", e)
            }
        }
    }

    private fun populateMoodPreview(
        views: RemoteViews,
        widgetData: SharedPreferences,
    ) {
        for (i in 0..1) {
            try {
                val name = widgetData.getString("user_${i}_name", "") ?: ""
                val label = widgetData.getString("user_${i}_label", "") ?: ""
                val score = widgetData.getInt("user_${i}_score", 0).coerceIn(0, 5)
                val colorHex = widgetData.getString("user_${i}_color", "") ?: ""

                val ratingText = if (score > 0) "Оценка $score из 5" else ""

                val nameId = if (i == 0) R.id.name_2_0 else R.id.name_2_1
                val heartId = if (i == 0) R.id.heart_2_0 else R.id.heart_2_1
                val ratingId = if (i == 0) R.id.rating_2_0 else R.id.rating_2_1
                val labelId = if (i == 0) R.id.label_2_0 else R.id.label_2_1

                val displayName = if (name.isNotEmpty()) name else if (i == 0) "Вы" else "Партнёр"

                val waterColor = parseColor(colorHex)
                val heartBitmap = createWaterHeartBitmap(70, score / 5.0, waterColor)

                views.setTextViewText(nameId, displayName)
                views.setImageViewBitmap(heartId, heartBitmap)
                views.setTextViewText(ratingId, ratingText)
                views.setTextColor(ratingId, if (ratingText.isNotEmpty()) waterColor else Color.parseColor("#9CA3AF"))
                views.setTextViewText(labelId, if (label.isNotEmpty()) label else "Пока нет данных")
                views.setTextColor(labelId, if (label.isNotEmpty()) waterColor else Color.parseColor("#9CA3AF"))
            } catch (e: Exception) {
                Log.e(TAG, "Error populating mood for user $i", e)
            }
        }
    }

    private fun parseColor(hex: String): Int {
        return try {
            when {
                hex.isEmpty() -> Color.parseColor("#D1D5DB")
                hex.startsWith("#") -> Color.parseColor(hex)
                hex.startsWith("0x") -> hex.toLong(16).toInt()
                else -> Color.parseColor("#$hex")
            }
        } catch (e: Exception) {
            Color.parseColor("#D1D5DB")
        }
    }

    private fun createWaterHeartBitmap(size: Int, fillLevel: Double, waterColor: Int): Bitmap {
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        val heartPath = createHeartPath(size.toFloat(), size.toFloat())

        val bgPaint = Paint().apply {
            color = waterColor
            alpha = 20
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        canvas.drawPath(heartPath, bgPaint)

        if (fillLevel > 0.005) {
            canvas.save()
            canvas.clipPath(heartPath)

            val waterTop = size * (1 - fillLevel).toFloat()
            val waveAmp = size * 0.03f

            val waterPath = Path()
            waterPath.moveTo(-1f, waterTop)

            val steps = 24
            for (i in 0..steps) {
                val x = size * i.toFloat() / steps
                val y = waterTop + sin(x / size * 2 * PI - PI * 0.5).toFloat() * waveAmp
                waterPath.lineTo(x, y)
            }
            waterPath.lineTo(size + 1f, size.toFloat())
            waterPath.lineTo(-1f, size.toFloat())
            waterPath.close()

            val waterPaint = Paint().apply {
                shader = LinearGradient(
                    0f, waterTop, 0f, size.toFloat(),
                    adjustAlpha(waterColor, 0.68f),
                    adjustAlpha(waterColor, 0.90f),
                    Shader.TileMode.CLAMP
                )
                style = Paint.Style.FILL
                isAntiAlias = true
            }
            canvas.drawPath(waterPath, waterPaint)

            if (fillLevel > 0.15) {
                val bubblePaint = Paint().apply {
                    color = Color.WHITE
                    alpha = 77
                    isAntiAlias = true
                }
                canvas.drawCircle(
                    size * 0.32f,
                    waterTop + size * 0.12f,
                    size * 0.06f,
                    bubblePaint
                )
            }

            canvas.restore()
        }

        val borderPaint = Paint().apply {
            color = adjustAlpha(waterColor, 0.5f)
            style = Paint.Style.STROKE
            strokeWidth = 2.0f
            strokeJoin = Paint.Join.ROUND
            isAntiAlias = true
        }
        canvas.drawPath(heartPath, borderPaint)

        return output
    }

    private fun createHeartPath(width: Float, height: Float): Path {
        return Path().apply {
            moveTo(width * 0.5f, height * 0.27f)
            cubicTo(width * 0.5f, height * 0.245f, width * 0.45f, height * 0.14f, width * 0.25f, height * 0.14f)
            cubicTo(0f, height * 0.14f, 0f, height * 0.46f, 0f, height * 0.46f)
            cubicTo(0f, height * 0.71f, width * 0.25f, height * 0.84f, width * 0.5f, height)
            cubicTo(width * 0.75f, height * 0.84f, width, height * 0.71f, width, height * 0.46f)
            cubicTo(width, height * 0.46f, width, height * 0.14f, width * 0.75f, height * 0.14f)
            cubicTo(width * 0.6f, height * 0.14f, width * 0.5f, height * 0.245f, width * 0.5f, height * 0.27f)
            close()
        }
    }

    private fun adjustAlpha(color: Int, factor: Float): Int {
        val alpha = (Color.alpha(color) * factor).toInt().coerceIn(0, 255)
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
    }
}
