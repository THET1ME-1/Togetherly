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

                // ── Моё настроение ──
                val myEmojiPath = widgetData.getString("mood_emoji_path", null)
                    .takeIf { !it.isNullOrEmpty() }
                val myLabel = widgetData.getString("mood_label", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "—"
                val myUserName = widgetData.getString("mood_user_name", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "Я"

                // Имя — всегда показываем
                setTextViewText(R.id.mood_user_name, myUserName)

                // Эмодзи
                val myBitmap = loadBitmap(myEmojiPath)
                if (myBitmap != null) {
                    setImageViewBitmap(R.id.mood_emoji_image, myBitmap)
                    setViewVisibility(R.id.mood_emoji_image, View.VISIBLE)
                    setViewVisibility(R.id.mood_placeholder, View.GONE)
                } else {
                    setViewVisibility(R.id.mood_emoji_image, View.GONE)
                    setViewVisibility(R.id.mood_placeholder, View.VISIBLE)
                }

                // Метка — всегда показываем (— если нет настроения)
                setTextViewText(R.id.mood_label, myLabel)

                // ── Настроение партнёра ──
                val partnerEmojiPath = widgetData.getString("partner_mood_emoji_path", null)
                    .takeIf { !it.isNullOrEmpty() }
                val partnerLabel = widgetData.getString("partner_mood_label", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "—"
                val partnerUserName = widgetData.getString("partner_mood_user_name", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "Партнёр"

                // Имя партнёра — всегда показываем
                setTextViewText(R.id.mood_partner_user_name, partnerUserName)

                // Эмодзи партнёра
                val partnerBitmap = loadBitmap(partnerEmojiPath)
                if (partnerBitmap != null) {
                    setImageViewBitmap(R.id.mood_partner_emoji_image, partnerBitmap)
                    setViewVisibility(R.id.mood_partner_emoji_image, View.VISIBLE)
                    setViewVisibility(R.id.mood_partner_placeholder, View.GONE)
                } else {
                    setViewVisibility(R.id.mood_partner_emoji_image, View.GONE)
                    setViewVisibility(R.id.mood_partner_placeholder, View.VISIBLE)
                }

                // Метка партнёра — всегда показываем
                setTextViewText(R.id.mood_partner_label, partnerLabel)
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


