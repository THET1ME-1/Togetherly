package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/widgets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhotoDayWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, PhotoDayWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "getPhotoGridWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, PhotoGridWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "updatePhotoDayCarousel" -> {
                    val widgetId = call.argument<Int>("widgetId")
                    val paths = call.argument<List<String>>("paths")
                    
                    if (widgetId != null && paths != null) {
                        val prefs = getSharedPreferences("HomeWidgetPreferences", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putString(
                            "photo_day_widget_${widgetId}_paths",
                            org.json.JSONArray(paths).toString()
                        ).apply()
                        
                        // Force schedule alarm in case it wasn't running
                        PhotoDayWidgetProvider.scheduleRotationAlarm(this)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing widgetId or paths", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
