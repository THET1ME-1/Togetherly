package com.togetherly.love

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Зов в совместную ленту («Аня зовёт смотреть TikTok», `pb_hooks/reels_invite.pb.js`)
 * — из системы во Flutter, канал `love_app/reels_invite`.
 *
 * Пути два. Касание по пушу приходит интентом лаунчера с данными FCM в
 * дополнениях (`kind`, `feed`, `group`, `name`): на холодном старте Dart ещё
 * не слушает, поэтому зов кладётся в `pending`, и Dart забирает его сам; на
 * тёплом — уходит сразу методом `opened`. Пуш, пришедший при открытом
 * приложении, система не рисует — его отдаёт [arrived], а Dart спрашивает
 * человека листом.
 */
object ReelsInviteBridge {
    const val CHANNEL = "love_app/reels_invite"

    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "pending") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel = null
    }

    /** [warm] — приложение уже жило, Dart слушает канал. */
    fun fromIntent(intent: Intent?, warm: Boolean) {
        if (intent == null || intent.getStringExtra("kind") != "reels") return
        val data = mapOf(
            "kind" to "reels",
            "feed" to (intent.getStringExtra("feed") ?: ""),
            "group" to (intent.getStringExtra("group") ?: ""),
            "name" to (intent.getStringExtra("name") ?: ""),
        )
        // Пересоздание активности приносит тот же интент — второй раз не зовём.
        intent.removeExtra("kind")
        val ch = channel
        if (warm && ch != null) ch.invokeMethod("opened", data) else pending = data
    }

    /** Пуш пришёл, пока приложение на экране. */
    fun arrived(data: Map<String, String>) {
        main.post { channel?.invokeMethod("arrived", data) }
    }
}
