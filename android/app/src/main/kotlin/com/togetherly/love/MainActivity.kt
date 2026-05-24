package com.togetherly.love

import android.os.Bundle
import androidx.core.view.WindowCompat
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/widgets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhotoDayWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val legacy = manager.getAppWidgetIds(
                        ComponentName(this, PhotoDayWidgetProvider::class.java)
                    ).toList()
                    val selfIds = manager.getAppWidgetIds(
                        ComponentName(this, SelfPhotoWidgetProvider::class.java)
                    ).toList()
                    val partnerIds = manager.getAppWidgetIds(
                        ComponentName(this, PartnerPhotoWidgetProvider::class.java)
                    ).toList()
                    result.success((legacy + selfIds + partnerIds).distinct())
                }

                "getSelfPhotoWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, SelfPhotoWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "getPartnerPhotoWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, PartnerPhotoWidgetProvider::class.java)
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
                    // Flutter computes the display index; use it so native receiver
                    // continues advancing from the correct position.
                    val currentIndex = call.argument<Int>("currentIndex") ?: 0

                    if (widgetId != null && paths != null) {
                        val prefs = getSharedPreferences("HomeWidgetPreferences", android.content.Context.MODE_PRIVATE)
                        prefs.edit()
                            .putString(
                                "photo_day_widget_${widgetId}_paths",
                                org.json.JSONArray(paths).toString()
                            )
                            .putInt("photo_day_widget_${widgetId}_current_index", currentIndex)
                            // Record the advance time so the native receiver knows when
                            // Flutter last rotated and doesn't double-advance.
                            .putLong("photo_day_widget_${widgetId}_last_update", System.currentTimeMillis())
                            .apply()

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
