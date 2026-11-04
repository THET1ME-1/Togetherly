package com.togetherly.love

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Пуш, пришедший при открытом приложении, — во Flutter, канал
 * `love_app/push_arrived` (TOG-36).
 *
 * Сервер шлёт пуш только тем, кого не видит на связи. Раз он пришёл, пока
 * приложение на экране, сокет Centrifugo умер молча, и открытый чат ждёт его
 * зря: приложение замечает такое только через 35 секунд, а уведомление уже
 * видно. Сюда уходит вид пуша (`chat`, `memory`, `mood`…), Dart сам решает,
 * что догнать (`PushArrivals`).
 */
object PushArrivedBridge {
    const val CHANNEL = "love_app/push_arrived"

    private var channel: MethodChannel? = null

    /**
     * Приложение на экране (между onStart и onStop у MainActivity). Тогда
     * обновлять виджеты будит не фоновая задача, а уже запущенный Dart: задача
     * WorkManager поднимает второй движок Flutter на главном потоке, и на
     * слабых телефонах открытое приложение ловит «не отвечает» (1.41, 04.11.2026).
     */
    @Volatile
    var onScreen = false

    /** Канал к работающему Dart есть: сигнал дойдёт до приложения. */
    val attached: Boolean get() = channel != null
    private val main = Handler(Looper.getMainLooper())

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
    }

    fun detach() {
        channel = null
    }

    /** Пуш вида [kind] пришёл, пока приложение на экране. */
    fun arrived(kind: String?) {
        if (kind.isNullOrEmpty()) return
        // Пуш приходит в потоке службы, а канал живёт в главном.
        main.post { channel?.invokeMethod("arrived", kind) }
    }
}
