package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * Стоит ли на рабочем столе хоть один наш виджет (TOG-90, 11.11.2026).
 *
 * Тихий пуш «обнови виджеты» поднимал движок Flutter у каждого, кто в паре,
 * даже когда обновлять нечего. Спрашиваем систему до постановки задачи: без
 * виджетов телефон не просыпается вовсе.
 */
object WidgetsOnScreen {
    private const val TAG = "WidgetsOnScreen"

    fun any(context: Context): Boolean {
        // Список своих провайдеров система отдаёт с Android 8
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            val manager = AppWidgetManager.getInstance(context)
            manager.getInstalledProvidersForPackage(context.packageName, null)
                .any { manager.getAppWidgetIds(it.provider).isNotEmpty() }
        } catch (e: Exception) {
            // Не узнали — обновляем как раньше: застывший виджет хуже лишнего пробуждения
            Log.w(TAG, "не узнали, есть ли виджеты: ${e.message}")
            true
        }
    }
}
