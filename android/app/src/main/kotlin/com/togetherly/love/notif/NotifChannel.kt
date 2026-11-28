package com.togetherly.love.notif

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Свои уведомления приложения тем же видом «А», канал `love_app/notif`.
 *
 * Сообщение партнёра доходит и сокетом, пока приложение живо в фоне: тогда
 * уведомление ставит Dart (`PbPushService`), и оно обязано выглядеть так
 * же, как пришедшее пушем. Dart собирает обложку той же формы
 * (`lib/models/push_cover.dart`) и отдаёт сюда.
 *
 * `show {cover, title, body, tag, id, channel}` → true, если показано.
 */
object NotifChannel {
    const val CHANNEL = "love_app/notif"
    private const val TAG = "NotifChannel"

    // Картинки качаются до показа — не на главном потоке. Один поток: два
    // уведомления одной метки должны лечь по порядку прихода.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger, context: Context) {
        val ctx = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val raw = call.argument<String>("cover").orEmpty()
                    val title = call.argument<String>("title").orEmpty()
                    val body = call.argument<String>("body").orEmpty()
                    val tag = call.argument<String>("tag").orEmpty().ifEmpty { "app" }
                    val id = call.argument<Int>("id") ?: 0
                    val channel = call.argument<String>("channel").orEmpty().ifEmpty { NotifCover.CHANNEL_PARTNER }
                    worker.execute {
                        val shown = showOrPlain(ctx, raw, title, body, tag, id, channel)
                        main.post { result.success(shown) }
                    }
                }
                // Версия отрисовки: Dart шлёт `notifV` серверу только с ней.
                "version" -> result.success(1)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Обложка — видом «А»; не разобралась или рисование упало — обычным
     * уведомлением: пуш данными система сама не покажет.
     */
    fun showOrPlain(ctx: Context, raw: String, title: String, body: String, tag: String, id: Int, channel: String): Boolean {
        val cover = CoverParser.parse(raw)
        return try {
            if (cover != null) NotifCover.show(ctx, cover, raw, tag, id, channel)
            else NotifCover.plain(ctx, title, body, tag, id)
            true
        } catch (e: Exception) {
            Log.w(TAG, "обложка не нарисовалась: ${e.message}")
            try {
                NotifCover.plain(ctx, cover?.title?.ifEmpty { title } ?: title, cover?.body ?: body, tag, id, cover?.link ?: "loveapp://open/home")
                true
            } catch (e2: Exception) {
                Log.w(TAG, "и обычное не показалось: ${e2.message}")
                false
            }
        }
    }
}
