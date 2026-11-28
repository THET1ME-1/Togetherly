package com.togetherly.love.notif

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Досылка из шторки: ответ, набранный без сети, и отметка «прочитано». Ждёт
 * связи, повторяет с растущей паузой. Ответ несёт свой номер, поэтому повтор
 * после частичного успеха даёт «уже есть», а не второе сообщение.
 */
class NotifSendWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val group = inputData.getString(K_GROUP).orEmpty()
        if (group.isEmpty()) return Result.failure()
        val sent = when (inputData.getString(K_TYPE)) {
            "reply" -> NotifActions.sendMessage(
                applicationContext, group,
                inputData.getString(K_ID).orEmpty(), inputData.getString(K_TEXT).orEmpty(),
                inputData.getLong(K_TS, System.currentTimeMillis()), BUDGET_MS,
            )
            "read" -> NotifActions.markRead(applicationContext, group, inputData.getLong(K_TS, 0L), BUDGET_MS)
            else -> NotifActions.Sent.GIVE_UP
        }
        return when (sent) {
            NotifActions.Sent.OK -> Result.success()
            NotifActions.Sent.GIVE_UP -> Result.failure()
            // Сутки повторов хватает: дальше ответ устарел, а приложение
            // человек к этому времени точно откроет.
            NotifActions.Sent.RETRY -> if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val K_TYPE = "type"
        private const val K_GROUP = "group"
        private const val K_ID = "id"
        private const val K_TEXT = "text"
        private const val K_TS = "ts"
        private const val BUDGET_MS = 20_000L
        private const val MAX_ATTEMPTS = 12

        fun reply(ctx: Context, group: String, id: String, text: String, ts: Long) = enqueue(
            ctx, "notif_reply_$id",
            Data.Builder().putString(K_TYPE, "reply").putString(K_GROUP, group)
                .putString(K_ID, id).putString(K_TEXT, text).putLong(K_TS, ts).build(),
        )

        fun read(ctx: Context, group: String, ts: Long) = enqueue(
            ctx, "notif_read_$group",
            Data.Builder().putString(K_TYPE, "read").putString(K_GROUP, group).putLong(K_TS, ts).build(),
            ExistingWorkPolicy.REPLACE,
        )

        private fun enqueue(ctx: Context, name: String, data: Data, policy: ExistingWorkPolicy = ExistingWorkPolicy.KEEP) {
            val request = OneTimeWorkRequestBuilder<NotifSendWorker>()
                .setInputData(data)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(ctx).enqueueUniqueWork(name, policy, request)
        }
    }
}
