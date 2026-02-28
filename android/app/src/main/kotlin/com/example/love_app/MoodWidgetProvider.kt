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
 * Виджет «Настроение» — крупный виджет с картинкой
 * эмодзи текущего настроения и подписью.
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

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://mood")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ── Данные ──
                val emojiPath = widgetData.getString("mood_emoji_path", null)
                    .takeIf { !it.isNullOrEmpty() }
                val label = widgetData.getString("mood_label", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val userName = widgetData.getString("mood_user_name", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                // ── Картинка эмодзи ──
                val bitmap = loadBitmap(emojiPath)
                if (bitmap != null) {
                    setImageViewBitmap(R.id.mood_emoji_image, bitmap)
                    setViewVisibility(R.id.mood_emoji_image, View.VISIBLE)
                    setViewVisibility(R.id.mood_placeholder, View.GONE)
                } else {
                    setViewVisibility(R.id.mood_emoji_image, View.GONE)
                    setViewVisibility(R.id.mood_placeholder, View.VISIBLE)
                }

                // ── Текст ──
                setTextViewText(R.id.mood_label, label)
                setViewVisibility(
                    R.id.mood_label,
                    if (label.isNotEmpty()) View.VISIBLE else View.GONE
                )
                setTextViewText(R.id.mood_user_name, userName)
                setViewVisibility(
                    R.id.mood_user_name,
                    if (userName.isNotEmpty()) View.VISIBLE else View.GONE
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun loadBitmap(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        val file = java.io.File(path)
        if (!file.exists()) return null
        return try {
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
            )
        } catch (e: OutOfMemoryError) {
            null
        }
    }
}
