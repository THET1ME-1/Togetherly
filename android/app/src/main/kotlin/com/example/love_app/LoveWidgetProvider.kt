package com.example.love_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
