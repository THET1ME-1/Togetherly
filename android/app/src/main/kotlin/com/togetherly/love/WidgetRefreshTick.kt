package com.togetherly.love

import android.content.Context
import android.os.PowerManager
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Запасное обновление виджетов раз в 15 минут (TOG-90, 11.11.2026).
 *
 * Изменения партнёра приносит тихий пуш, эта задача нужна там, где пуши не
 * дошли. Раньше её ставил пакет workmanager, и каждый запуск поднимал движок
 * Flutter и слал семь запросов: 22,7 тысячи спящих телефонов за 21 минуту,
 * 44% запросов к серверу. Здесь задача нативная и сперва решает, пора ли:
 * виджетов нет — снимает себя; виджеты недавно обновлялись — молчит; экран
 * выключен — обновляет не чаще раза в час. Dart будит та же разовая задача,
 * что и у тихого пуша (WidgetRefreshWake).
 */
class WidgetRefreshTick(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        try {
            if (!WidgetsOnScreen.any(context)) {
                cancel(context)
                return Result.success()
            }
            // Приложение на экране обновляет виджеты само, второй движок не нужен
            if (PushArrivedBridge.onScreen && PushArrivedBridge.attached) return Result.success()
            val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            // Пары нет — обновлять нечего; поставят снова, когда пара появится
            if (data.getString("love_widget_group_id", "").isNullOrEmpty()) return Result.success()

            val refreshedAtMs = data.getString(KEY_REFRESHED_AT, null)?.toLongOrNull() ?: 0L
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val screenOn = power.isInteractive
            val now = System.currentTimeMillis()
            val wake = due(now, refreshedAtMs, screenOn)
            Log.i(TAG, "обновляли ${(now - refreshedAtMs) / 60000} мин назад, экран $screenOn, будим Dart: $wake")
            if (wake) WidgetRefreshWake.enqueue(context, WidgetRefreshWake.TASK_ALL, gatherSeconds = 0)
        } catch (e: Exception) {
            Log.w(TAG, "запасное обновление не решилось: ${e.message}")
        }
        return Result.success()
    }

    companion object {
        private const val TAG = "WidgetRefreshTick"
        const val UNIQUE_NAME = "togetherly_widget_tick"

        /** Отметка «виджеты обновлены», мс; пишет Dart после удачного прохода. */
        const val KEY_REFRESHED_AT = "widgets_refreshed_at_ms"

        /** Сколько обновление считается свежим при включённом экране. */
        const val FRESH_SCREEN_ON_MS = 14 * 60 * 1000L

        /** При выключенном: виджет никто не видит, изменения приносит пуш. */
        const val FRESH_SCREEN_OFF_MS = 60 * 60 * 1000L

        /** Пора ли будить Dart. Копия под тестами — widgetTickDue в Dart. */
        fun due(nowMs: Long, refreshedAtMs: Long, screenOn: Boolean): Boolean {
            val age = nowMs - refreshedAtMs
            // Когда обновляли, неизвестно или часы перевели назад — обновляем
            if (refreshedAtMs <= 0 || age < 0) return true
            return age >= if (screenOn) FRESH_SCREEN_ON_MS else FRESH_SCREEN_OFF_MS
        }

        /** Поставить задачу; уже стоящую не сбиваем, иначе срок уезжал бы. */
        fun schedule(context: Context) {
            try {
                val request = PeriodicWorkRequestBuilder<WidgetRefreshTick>(15, TimeUnit.MINUTES)
                    .setInitialDelay(15, TimeUnit.MINUTES)
                    .setConstraints(
                        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                    )
                    .build()
                WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                    UNIQUE_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
            } catch (e: Exception) {
                Log.w(TAG, "запасная задача не встала: ${e.message}")
            }
        }

        fun cancel(context: Context) {
            try {
                WorkManager.getInstance(context.applicationContext).cancelUniqueWork(UNIQUE_NAME)
            } catch (e: Exception) {
                Log.w(TAG, "запасная задача не снялась: ${e.message}")
            }
        }
    }
}
