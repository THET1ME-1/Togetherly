package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import org.json.JSONArray

/**
 * Номера фото-виджетов для фонового Dart (19.09.2026).
 *
 * Список виджетов Dart спрашивает каналом `love_app/widgets`, а его
 * регистрирует только MainActivity. В фоновых движках (WorkManager, пуш
 * `refresh`, служба сокета) канала нет, и «Фото партнёра» обновлялся только
 * при открытом приложении. Поэтому виджеты сами кладут свои номера в
 * HomeWidgetPreferences, а Dart без канала читает их через home_widget.
 */
object WidgetIdRegistry {
    private const val PHOTO_DAY = "widget_ids_photo_day"
    private const val SELF_PHOTO = "widget_ids_self_photo"
    private const val PARTNER_PHOTO = "widget_ids_partner_photo"
    private const val PHOTO_GRID = "widget_ids_photo_grid"

    /** [removed] — номера, которые система прямо сейчас удаляет. */
    fun refresh(context: Context, removed: IntArray = IntArray(0)) {
        try {
            val manager = AppWidgetManager.getInstance(context)
            fun ids(cls: Class<*>) = manager
                .getAppWidgetIds(ComponentName(context, cls))
                .filter { it !in removed }
            val legacy = ids(PhotoDayWidgetProvider::class.java)
            val self = ids(SelfPhotoWidgetProvider::class.java)
            val partner = ids(PartnerPhotoWidgetProvider::class.java)
            val grid = ids(PhotoGridWidgetProvider::class.java)
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                .edit()
                .putString(PHOTO_DAY, JSONArray((legacy + self + partner).distinct()).toString())
                .putString(SELF_PHOTO, JSONArray(self).toString())
                .putString(PARTNER_PHOTO, JSONArray(partner).toString())
                .putString(PHOTO_GRID, JSONArray(grid).toString())
                .apply()
        } catch (e: Exception) {
            android.util.Log.w("WidgetIdRegistry", "refresh failed", e)
        }
    }
}
