package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Настроение» — горизонтальный виджет:
 * слева — моё настроение (имя + эмодзи + метка),
 * справа — настроение партнёра (имя + эмодзи + метка).
 */
class MoodWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.mood_widget).apply {

                // Клик по виджету открывает экран настроения
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://mood")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val userCount = widgetData.getInt("user_count", 2).coerceIn(2, 4)

                // Сначала скрываем все варианты
                setViewVisibility(R.id.layout_2_users, View.GONE)
                setViewVisibility(R.id.layout_3_users, View.GONE)
                setViewVisibility(R.id.layout_4_users, View.GONE)

                when (userCount) {
                    2 -> {
                        setViewVisibility(R.id.layout_2_users, View.VISIBLE)
                        populateSlots(this, widgetData, 2, intArrayOf(R.id.emoji_2_0, R.id.emoji_2_1), 
                                     intArrayOf(R.id.placeholder_2_0, R.id.placeholder_2_1),
                                     intArrayOf(R.id.avatar_2_0, R.id.avatar_2_1))
                    }
                    3 -> {
                        setViewVisibility(R.id.layout_3_users, View.VISIBLE)
                        populateSlots(this, widgetData, 3, intArrayOf(R.id.emoji_3_0, R.id.emoji_3_1, R.id.emoji_3_2),
                                     intArrayOf(R.id.placeholder_3_0, R.id.placeholder_3_1, R.id.placeholder_3_2),
                                     intArrayOf(R.id.avatar_3_0, R.id.avatar_3_1, R.id.avatar_3_2))
                    }
                    4 -> {
                        setViewVisibility(R.id.layout_4_users, View.VISIBLE)
                        populateSlots(this, widgetData, 4, intArrayOf(R.id.emoji_4_0, R.id.emoji_4_1, R.id.emoji_4_2, R.id.emoji_4_3),
                                     intArrayOf(R.id.placeholder_4_0, R.id.placeholder_4_1, R.id.placeholder_4_2, R.id.placeholder_4_3),
                                     intArrayOf(R.id.avatar_4_0, R.id.avatar_4_1, R.id.avatar_4_2, R.id.avatar_4_3))
                    }
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun populateSlots(
        views: RemoteViews,
        widgetData: SharedPreferences,
        count: Int,
        emojiIds: IntArray,
        placeholderIds: IntArray,
        avatarIds: IntArray
    ) {
        for (i in 0 until count) {
            val emojiPath = widgetData.getString("user_${i}_emoji_path", null)
            val avatarPath = widgetData.getString("user_${i}_avatar_path", null)

            // Emoji
            val emojiBitmap = loadScaledBitmap(emojiPath, 150)
            if (emojiBitmap != null) {
                views.setImageViewBitmap(emojiIds[i], emojiBitmap)
                views.setViewVisibility(emojiIds[i], View.VISIBLE)
                views.setViewVisibility(placeholderIds[i], View.GONE)
            } else {
                views.setViewVisibility(emojiIds[i], View.GONE)
                views.setViewVisibility(placeholderIds[i], View.VISIBLE)
            }

            // Avatar
            val avatarBitmapRaw = loadScaledBitmap(avatarPath, 120)
            if (avatarBitmapRaw != null) {
                views.setImageViewBitmap(avatarIds[i], getCircularBitmap(avatarBitmapRaw))
                views.setViewVisibility(avatarIds[i], View.VISIBLE)
            } else {
                views.setViewVisibility(avatarIds[i], View.GONE)
            }
        }
    }

    /**
     * Читает файл по [path] и декодирует его сразу в нужный размер
     * ([maxSizePx] × [maxSizePx] px), избегая OOM и TransactionTooLargeException
     * при передаче битмапа через RemoteViews/Binder (~1 МБ лимит).
     */
    private fun loadScaledBitmap(path: String?, maxSizePx: Int): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = java.io.File(path)
        if (!file.exists()) return null

        // Узнаём размеры без загрузки пикселей
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null

        // Вычисляем inSampleSize для вписывания в maxSizePx
        var sampleSize = 1
        var w = opts.outWidth
        var h = opts.outHeight
        while (w / 2 >= maxSizePx || h / 2 >= maxSizePx) {
            sampleSize *= 2
            w /= 2
            h /= 2
        }

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565  // ~4× меньше памяти, чем ARGB_8888
        }
        return try {
            BitmapFactory.decodeFile(path, decodeOpts)
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    /**
     * Обрезает битмап в круг и добавляет белую обводку (как у Widgetable).
     */
    private fun getCircularBitmap(bitmap: Bitmap): Bitmap {
        val size = Math.min(bitmap.width, bitmap.height)
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(output)
        val paint = android.graphics.Paint().apply {
            isAntiAlias = true
        }
        val rect = android.graphics.Rect(
            (bitmap.width - size) / 2,
            (bitmap.height - size) / 2,
            (bitmap.width + size) / 2,
            (bitmap.height + size) / 2
        )
        val rectF = android.graphics.RectF(0f, 0f, size.toFloat(), size.toFloat())
        val radius = size / 2f

        canvas.drawARGB(0, 0, 0, 0)
        canvas.drawRoundRect(rectF, radius, radius, paint)

        paint.xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rectF, paint)

        // Белая обводка (5% от размера)
        paint.xfermode = null
        paint.style = android.graphics.Paint.Style.STROKE
        paint.color = android.graphics.Color.WHITE
        paint.strokeWidth = size * 0.05f
        canvas.drawCircle(radius, radius, radius - paint.strokeWidth / 2f, paint)

        return output
    }
}


