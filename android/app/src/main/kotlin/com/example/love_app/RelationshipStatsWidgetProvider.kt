package com.example.love_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Виджет «Relationship Stats» — 2×2 сетка:
 * Days Together, Memories, Drawings, Miss Yous.
 */
class RelationshipStatsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.relationship_stats_widget).apply {

                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://home")
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // ── Data ──
                val days = widgetData.getString("stats_days_together", "0") ?: "0"
                val memories = widgetData.getString("stats_memories_count", "0") ?: "0"
                val drawings = widgetData.getString("stats_drawings_count", "0") ?: "0"
                val missYou = widgetData.getString("stats_miss_you_count", "0") ?: "0"

                // ── Labels ──
                val daysLabel = widgetData.getString("stats_days_label", "Days Together") ?: "Days Together"
                val memoriesLabel = widgetData.getString("stats_memories_label", "Memories") ?: "Memories"
                val drawingsLabel = widgetData.getString("stats_drawings_label", "Drawings") ?: "Drawings"
                val missYouLabel = widgetData.getString("stats_miss_you_label", "Miss Yous") ?: "Miss Yous"

                // ── Populate Views ──
                setTextViewText(R.id.stat_days_value, days)
                setTextViewText(R.id.stat_days_label, daysLabel)

                setTextViewText(R.id.stat_memories_value, memories)
                setTextViewText(R.id.stat_memories_label, memoriesLabel)

                setTextViewText(R.id.stat_drawings_value, drawings)
                setTextViewText(R.id.stat_drawings_label, drawingsLabel)

                setTextViewText(R.id.stat_miss_you_value, missYou)
                setTextViewText(R.id.stat_miss_you_label, missYouLabel)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
