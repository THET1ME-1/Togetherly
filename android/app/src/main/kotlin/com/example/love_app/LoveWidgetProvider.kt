package com.example.love_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class LoveWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = try {
                buildViews(context, widgetData)
            } catch (e: Exception) {
                Log.e("LoveWidgetProvider", "onUpdate error", e)
                return@forEach
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun buildViews(context: Context, widgetData: SharedPreferences): RemoteViews {
        return RemoteViews(context.packageName, R.layout.love_widget).apply {

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("loveapp://widgets")
            )
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // ═══════════ Моя сторона ═══════════
            val myName = widgetData.getString("my_name", null)
                .takeIf { !it.isNullOrEmpty() } ?: "Я"
            val myStatus = widgetData.getString("my_status", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val myMessage = widgetData.getString("my_message", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val myMusicTitle = widgetData.getString("my_music_title", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val myMusicArtist = widgetData.getString("my_music_artist", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""

            setTextViewText(R.id.my_name, myName)
            setTextViewText(R.id.my_status, myStatus)
            setTextViewText(R.id.my_message, myMessage)
            setTextViewText(
                R.id.my_music, when {
                    myMusicTitle.isNotEmpty() && myMusicArtist.isNotEmpty() ->
                        "\u266A $myMusicTitle \u2014 $myMusicArtist"
                    myMusicTitle.isNotEmpty() -> "\u266A $myMusicTitle"
                    else -> ""
                }
            )

            // ── Эмодзи настроения ──
            val myEmojiPath = widgetData.getString("my_mood_emoji_path", null)
                .takeIf { !it.isNullOrEmpty() }
            val myEmojiBitmap = loadScaledBitmap(myEmojiPath, 64)
            if (myEmojiBitmap != null) {
                setImageViewBitmap(R.id.my_mood_emoji, myEmojiBitmap)
                setViewVisibility(R.id.my_mood_emoji, View.VISIBLE)
                setViewVisibility(R.id.my_mood_text, View.GONE)
            } else {
                val myMoodLabel = widgetData.getString("my_mood", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                setViewVisibility(R.id.my_mood_emoji, View.GONE)
                setViewVisibility(R.id.my_mood_text, if (myMoodLabel.isNotEmpty()) View.VISIBLE else View.GONE)
                if (myMoodLabel.isNotEmpty()) setTextViewText(R.id.my_mood_text, myMoodLabel)
            }

            // ── Фото как фон ──
            val myPhotoPath = widgetData.getString("my_photo_path", null)
                .takeIf { !it.isNullOrEmpty() }
            val myBgBitmap = loadScaledBitmap(myPhotoPath, 280)
            if (myBgBitmap != null) {
                setImageViewBitmap(R.id.my_bg_photo, myBgBitmap)
                setViewVisibility(R.id.my_bg_photo, View.VISIBLE)
                setViewVisibility(R.id.my_overlay, View.VISIBLE)
                setTextColor(R.id.my_name, Color.WHITE)
                setTextColor(R.id.my_status, Color.WHITE)
                setTextColor(R.id.my_message, Color.argb(220, 255, 255, 255))
                setTextColor(R.id.my_music, Color.argb(180, 255, 255, 255))
            } else {
                setViewVisibility(R.id.my_bg_photo, View.GONE)
                setViewVisibility(R.id.my_overlay, View.GONE)
                setTextColor(R.id.my_name, Color.argb(204, 0, 0, 0))
                setTextColor(R.id.my_status, Color.argb(204, 0, 0, 0))
                setTextColor(R.id.my_message, Color.argb(153, 0, 0, 0))
                setTextColor(R.id.my_music, Color.argb(136, 0, 0, 0))
            }

            // ═══════════ Сторона партнёра ═══════════
            val partnerName = widgetData.getString("partner_name", null)
                .takeIf { !it.isNullOrEmpty() } ?: "Партнёр"
            val partnerStatus = widgetData.getString("partner_status", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val partnerMessage = widgetData.getString("partner_message", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val partnerMusicTitle = widgetData.getString("partner_music_title", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""
            val partnerMusicArtist = widgetData.getString("partner_music_artist", null)
                .takeIf { !it.isNullOrEmpty() } ?: ""

            setTextViewText(R.id.partner_name, partnerName)
            setTextViewText(R.id.partner_status, partnerStatus)
            setTextViewText(R.id.partner_message, partnerMessage)
            setTextViewText(
                R.id.partner_music, when {
                    partnerMusicTitle.isNotEmpty() && partnerMusicArtist.isNotEmpty() ->
                        "\u266A $partnerMusicTitle \u2014 $partnerMusicArtist"
                    partnerMusicTitle.isNotEmpty() -> "\u266A $partnerMusicTitle"
                    else -> ""
                }
            )

            // ── Эмодзи настроения партнёра ──
            val partnerEmojiPath = widgetData.getString("partner_mood_emoji_path", null)
                .takeIf { !it.isNullOrEmpty() }
            val partnerEmojiBitmap = loadScaledBitmap(partnerEmojiPath, 64)
            if (partnerEmojiBitmap != null) {
                setImageViewBitmap(R.id.partner_mood_emoji, partnerEmojiBitmap)
                setViewVisibility(R.id.partner_mood_emoji, View.VISIBLE)
                setViewVisibility(R.id.partner_mood_text, View.GONE)
            } else {
                val partnerMoodLabel = widgetData.getString("partner_mood", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                setViewVisibility(R.id.partner_mood_emoji, View.GONE)
                setViewVisibility(R.id.partner_mood_text, if (partnerMoodLabel.isNotEmpty()) View.VISIBLE else View.GONE)
                if (partnerMoodLabel.isNotEmpty()) setTextViewText(R.id.partner_mood_text, partnerMoodLabel)
            }

            // ── Фото партнёра как фон ──
            val partnerPhotoPath = widgetData.getString("partner_photo_path", null)
                .takeIf { !it.isNullOrEmpty() }
            val partnerBgBitmap = loadScaledBitmap(partnerPhotoPath, 280)
            if (partnerBgBitmap != null) {
                setImageViewBitmap(R.id.partner_bg_photo, partnerBgBitmap)
                setViewVisibility(R.id.partner_bg_photo, View.VISIBLE)
                setViewVisibility(R.id.partner_overlay, View.VISIBLE)
                setTextColor(R.id.partner_name, Color.WHITE)
                setTextColor(R.id.partner_status, Color.WHITE)
                setTextColor(R.id.partner_message, Color.argb(220, 255, 255, 255))
                setTextColor(R.id.partner_music, Color.argb(180, 255, 255, 255))
            } else {
                setViewVisibility(R.id.partner_bg_photo, View.GONE)
                setViewVisibility(R.id.partner_overlay, View.GONE)
                setTextColor(R.id.partner_name, Color.argb(204, 0, 0, 0))
                setTextColor(R.id.partner_status, Color.argb(204, 0, 0, 0))
                setTextColor(R.id.partner_message, Color.argb(153, 0, 0, 0))
                setTextColor(R.id.partner_music, Color.argb(136, 0, 0, 0))
            }
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
