package com.togetherly.love

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Приём пушей FCM.
 *
 * До 13 августа 2026 уведомления на Android держал свой foreground-сервис: он
 * поднимал SSE-подписку в отдельном изоляте и жил, пока приложение свёрнуто.
 * Цена — строка «Togetherly на связи» в шторке у каждого и суточный лимит
 * Android 14 на сервисы типа dataSync: шесть часов, после которых система
 * останавливает сервис, и доставка молчит до утра. Теперь сокет держит сама
 * система, а сервис остаётся только там, где сервисов Google нет.
 *
 * Плагин `firebase_messaging` намеренно НЕ подключён: на iOS он перехватывает
 * делегата APNs через swizzling, а там уже работает свой путь с ручным токеном.
 * Поэтому FCM живёт нативно и только на Android.
 *
 * Баннер с уведомлением рисует система — в пуше едет `notification`. Сюда
 * попадает либо тихий пуш «проснись и обнови виджеты», либо обычный, когда
 * приложение на переднем плане (тогда показывать нечего: человек и так внутри).
 */
class FcmService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        // Токен в профиль пишет Dart: у него есть сессия PocketBase. Здесь
        // только отметка в журнале — на следующем запуске `FcmTokens.current`
        // отдаст этот же токен, и он доедет до сервера.
        Log.i(TAG, "новый токен FCM (длина ${token.length})")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.notification != null) return

        val kind = message.data["kind"] ?: return
        if (kind != "widgets") return

        // Данные виджетов у партнёра поменялись. Периодический WorkManager
        // подберёт это сам, но через четверть часа — а пуш даёт обновить
        // рабочий стол сразу. Путь home_widget тут мёртв (см. WidgetRefreshWake).
        WidgetRefreshWake.enqueue(applicationContext, WidgetRefreshWake.TASK_ALL)
    }

    companion object {
        private const val TAG = "FcmService"
    }
}
