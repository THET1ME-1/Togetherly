package com.togetherly.love

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * Разбудить Dart в фоне, чтобы он перерисовал виджеты (19.09.2026).
 *
 * Путь home_widget (`HomeWidgetBackgroundIntent`) на Android не годится:
 * обработчик интерактивности приложение тут не регистрирует (см. main.dart),
 * задача падает с «No callbackHandle saved», а плагин ставит задачи цепочкой
 * APPEND — после первого падения WorkManager проваливает все следующие, не
 * запуская. Так не работали ни тихий пуш `widgets`, ни перерисовка карты
 * «Где мы» под новую ячейку.
 *
 * Здесь разовая задача пакета workmanager: тот же диспетчер
 * (`widgetRefreshDispatcher`), что и у периодического обновления раз в 15
 * минут. Её исполнитель ждёт ответа Dart, поэтому система не замораживает
 * процесс посреди работы, как это бывает после короткой задачи home_widget.
 * APPEND_OR_REPLACE: пока одна задача идёт, следующая встаёт за ней, а
 * проваленная цепочка не тянет за собой новые.
 *
 * Каждый запуск задачи поднимает движок Flutter на главном потоке — дорого на
 * слабых телефонах (окно «не отвечает», 1.41, 04.11.2026). Поэтому пачка пушей
 * склеивается: задача ждёт [GATHER_SEC] секунд, и пока она ещё не началась,
 * новые не встают. Данные она берёт свежие с сервера в момент запуска.
 */
object WidgetRefreshWake {
    /** Все виджеты из PocketBase, как в периодическом обновлении. */
    const val TASK_ALL = "widgetRefresh"

    /** Только картинка «Где мы»: сменилась ячейка или картинки ещё нет. */
    const val TASK_MAP = "mapWidget"

    private const val TAG = "WidgetRefreshWake"

    /** Сколько ждать пушей-соседей, прежде чем будить Dart. */
    private const val GATHER_SEC = 6L

    /** До какого момента (мс) уже ждёт поставленная задача каждого вида. */
    private val waitingUntil = HashMap<String, Long>()

    fun enqueue(context: Context, task: String) {
        try {
            val wm = WorkManager.getInstance(context.applicationContext)
            val name = "togetherly_wake_$task"
            // Задача этого вида ещё не началась — она и заберёт это обновление:
            // данные она берёт с сервера в момент запуска. Процесс убили —
            // память пуста, и задача просто встанет ещё раз.
            val now = System.currentTimeMillis()
            synchronized(waitingUntil) {
                if (now < (waitingUntil[task] ?: 0L)) return
                waitingUntil[task] = now + GATHER_SEC * 1000
            }
            val request = OneTimeWorkRequestBuilder<BackgroundWorker>()
                .setInitialDelay(GATHER_SEC, TimeUnit.SECONDS)
                .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, task).build())
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .build()
            wm.enqueueUniqueWork(
                name,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
        } catch (e: Exception) {
            Log.w(TAG, "не разбудили Dart ($task): ${e.message}")
        }
    }
}
