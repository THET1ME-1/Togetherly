package com.example.love_app

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
 * Виджет «Фото дня» — случайное фото из Memory Lane.
 * При нажатии открывается лента воспоминаний.
 */
class PhotoDayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.photo_day_widget).apply {

                val memoryId = widgetData.getString("photo_day_memory_id", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                // Deep link: открываем Memory Lane (если есть ID — к конкретной записи)
                val uri = if (memoryId.isNotEmpty())
                    "loveapp://memory_lane?id=$memoryId"
                else
                    "loveapp://memory_lane"

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(uri)
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ── Фото ──
                val photoPath = widgetData.getString("photo_day_path", null)
                    .takeIf { !it.isNullOrEmpty() }

                val bitmap = loadScaledBitmap(photoPath, 400)
                if (bitmap != null) {
                    setImageViewBitmap(R.id.photo_image, bitmap)
                    setViewVisibility(R.id.photo_image, View.VISIBLE)
                    setViewVisibility(R.id.photo_placeholder, View.GONE)
                } else {
                    setViewVisibility(R.id.photo_image, View.GONE)
                    setViewVisibility(R.id.photo_placeholder, View.VISIBLE)
                }

                // Подпись автора скрыта
                setViewVisibility(R.id.photo_author, View.GONE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun loadScaledBitmap(path: String?, maxSizePx: Int): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = java.io.File(path)
        if (!file.exists()) return null

        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null

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
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return try {
            BitmapFactory.decodeFile(path, decodeOpts)
        } catch (e: OutOfMemoryError) {
            null
        }
    }
}
