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

class LoveWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.love_widget).apply {

                // ── Click → открыть приложение на вкладке Widgets ──
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://widgets")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ═══════════ Моя сторона ═══════════
                val myName = widgetData.getString("my_name", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "Я"
                val myMood = widgetData.getString("my_mood", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val myStatus = widgetData.getString("my_status", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val myMessage = widgetData.getString("my_message", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val myMusicTitle = widgetData.getString("my_music_title", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val myMusicArtist = widgetData.getString("my_music_artist", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                setTextViewText(R.id.my_name, myName)
                setTextViewText(R.id.my_mood, if (myMood.isNotEmpty()) myMood else "·····")
                setTextViewText(R.id.my_status, myStatus)
                setTextViewText(R.id.my_message, myMessage)

                val myMusicText = when {
                    myMusicTitle.isNotEmpty() && myMusicArtist.isNotEmpty() ->
                        "🎵 $myMusicTitle — $myMusicArtist"
                    myMusicTitle.isNotEmpty() -> "🎵 $myMusicTitle"
                    else -> ""
                }
                setTextViewText(R.id.my_music, myMusicText)

                // ═══════════ Моё фото ═══════════
                val myPhotoPath = widgetData.getString("my_photo_path", null)
                    .takeIf { !it.isNullOrEmpty() }
                val myBitmap = loadScaledBitmap(myPhotoPath, 200)
                if (myBitmap != null) {
                    setImageViewBitmap(R.id.my_photo, myBitmap)
                    setViewVisibility(R.id.my_photo, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.my_photo, View.GONE)
                }

                // ═══════════ Сторона партнёра ═══════════
                val partnerName = widgetData.getString("partner_name", null)
                    .takeIf { !it.isNullOrEmpty() } ?: "Партнёр"
                val partnerMood = widgetData.getString("partner_mood", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val partnerStatus = widgetData.getString("partner_status", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val partnerMessage = widgetData.getString("partner_message", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val partnerMusicTitle = widgetData.getString("partner_music_title", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""
                val partnerMusicArtist = widgetData.getString("partner_music_artist", null)
                    .takeIf { !it.isNullOrEmpty() } ?: ""

                setTextViewText(R.id.partner_name, partnerName)
                setTextViewText(R.id.partner_mood, if (partnerMood.isNotEmpty()) partnerMood else "·····")
                setTextViewText(R.id.partner_status, partnerStatus)
                setTextViewText(R.id.partner_message, partnerMessage)

                val partnerMusicText = when {
                    partnerMusicTitle.isNotEmpty() && partnerMusicArtist.isNotEmpty() ->
                        "🎵 $partnerMusicTitle — $partnerMusicArtist"
                    partnerMusicTitle.isNotEmpty() -> "🎵 $partnerMusicTitle"
                    else -> ""
                }
                setTextViewText(R.id.partner_music, partnerMusicText)

                // ═══════════ Фото партнёра ═══════════
                val partnerPhotoPath = widgetData.getString("partner_photo_path", null)
                    .takeIf { !it.isNullOrEmpty() }
                val partnerBitmap = loadScaledBitmap(partnerPhotoPath, 200)
                if (partnerBitmap != null) {
                    setImageViewBitmap(R.id.partner_photo, partnerBitmap)
                    setViewVisibility(R.id.partner_photo, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.partner_photo, View.GONE)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
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
}
