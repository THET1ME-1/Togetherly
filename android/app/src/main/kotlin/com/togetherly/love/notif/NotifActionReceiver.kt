package com.togetherly.love.notif

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.RemoteInput

/**
 * Нажатие кнопки уведомления, которую телефон выполняет сам, не открывая
 * приложение: ответ текстом, «обнять», «прочитано», снежок в ответ.
 *
 * Сеть — в своём потоке под [goAsync]: приёмнику дают около десяти секунд,
 * поэтому у каждого действия срок 8 с. Ответ, не ушедший за это время,
 * досылает [NotifSendWorker], как только появится связь.
 */
class NotifActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val raw = intent.getStringExtra(EXTRA_RAW) ?: return
        val cover = CoverParser.parse(raw) ?: return
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return
        val tag = intent.getStringExtra(EXTRA_TAG) ?: cover.kind
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val reply = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(NotifChat.REPLY_KEY)?.toString()?.trim().orEmpty()
        val app = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                NotifActions.run(app, cover, raw, action, reply, tag, id)
            } catch (e: Exception) {
                Log.w(TAG, "действие $action сорвалось: ${e.message}")
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "NotifAction"
        private const val EXTRA_RAW = "tg_raw"
        private const val EXTRA_ACTION = "tg_action"
        private const val EXTRA_TAG = "tg_tag"
        private const val EXTRA_ID = "tg_id"

        /**
         * Намерение кнопки [action]. Ответу нужно изменяемое: в него система
         * кладёт набранный текст. Номер запроса свой у каждой кнопки, иначе
         * кнопки одного уведомления затирали бы друг друга.
         */
        fun pending(ctx: Context, action: String, tag: String, id: Int, mutable: Boolean, raw: String): PendingIntent {
            val intent = Intent(ctx, NotifActionReceiver::class.java)
                .setAction("com.togetherly.love.NOTIF_ACTION.$action")
                .setPackage(ctx.packageName)
                .putExtra(EXTRA_RAW, raw)
                .putExtra(EXTRA_ACTION, action)
                .putExtra(EXTRA_TAG, tag)
                .putExtra(EXTRA_ID, id)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            flags = flags or if (mutable && Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
            return PendingIntent.getBroadcast(ctx, "$tag|$id|$action".hashCode(), intent, flags)
        }
    }
}
