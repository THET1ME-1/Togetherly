package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import java.util.Calendar

class PhotoDayRotationReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("PhotoDayRotation", "Received action: $action")

        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val manager = AppWidgetManager.getInstance(context)
        val component = android.content.ComponentName(context, PhotoDayWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(component)

        if (widgetIds.isEmpty()) return

        var needsUpdate = false
        val editor = prefs.edit()

        for (widgetId in widgetIds) {
            val pathsStr = prefs.getString("photo_day_widget_${widgetId}_paths", null)
            if (pathsStr.isNullOrEmpty()) continue

            val paths = try { JSONArray(pathsStr) } catch (e: Exception) { null }
            if (paths == null || paths.length() <= 1) continue

            val rotationType = prefs.getString("photo_day_widget_${widgetId}_rotation_type", "unlock")
            val rotationInterval = prefs.getInt("photo_day_widget_${widgetId}_rotation_interval", 60)
            val lastUpdate = prefs.getLong("photo_day_widget_${widgetId}_last_update", 0L)
            val now = System.currentTimeMillis()

            var shouldRotate = false

            if (action == Intent.ACTION_USER_PRESENT && rotationType == "unlock") {
                shouldRotate = true
            } else if (action == ACTION_ROTATE_TIMER && rotationType == "time") {
                // Check if enough time has passed
                if (now - lastUpdate >= rotationInterval * 60 * 1000L - 60000L) { // 1 min buffer
                    shouldRotate = true
                }
            } else if (action == Intent.ACTION_USER_PRESENT && rotationType == "time") {
                 // opportunistic update if interval passed
                 if (now - lastUpdate >= rotationInterval * 60 * 1000L) {
                     shouldRotate = true
                 }
            }

            if (shouldRotate) {
                var currentIndex = prefs.getInt("photo_day_widget_${widgetId}_current_index", 0)
                currentIndex = (currentIndex + 1) % paths.length()
                editor.putInt("photo_day_widget_${widgetId}_current_index", currentIndex)
                editor.putLong("photo_day_widget_${widgetId}_last_update", now)
                
                // Update the single path for HomeWidgetProvider
                val currentPath = paths.optString(currentIndex, "")
                editor.putString("photo_day_widget_${widgetId}_path", currentPath)
                needsUpdate = true
            }
        }

        if (needsUpdate) {
            editor.apply()
            val updateIntent = Intent(context, PhotoDayWidgetProvider::class.java).apply {
                this.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            }
            context.sendBroadcast(updateIntent)
        }
    }

    companion object {
        const val ACTION_ROTATE_TIMER = "com.togetherly.love.ACTION_ROTATE_TIMER"
    }
}
