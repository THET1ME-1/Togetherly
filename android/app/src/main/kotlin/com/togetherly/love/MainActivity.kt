package com.togetherly.love

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // «Поделиться → Togetherly»: текст со ссылкой на товар.
    //
    // Плагина здесь нет намеренно: receive_sharing_intent 1.9 собран под
    // старый Kotlin-DSL Gradle и валит сборку на `kotlin()` в своём
    // build.gradle. Приём ACTION_SEND — двадцать строк, дешевле держать своими.
    //
    // Текст запоминается до того, как Flutter поднимет канал: на холодном
    // старте `configureFlutterEngine` случается позже, чем приходит интент,
    // и без буфера ссылка терялась бы.
    private var pendingSharedText: String? = null
    private var sharedTextChannel: MethodChannel? = null

    // Dynamically-registered receiver for ACTION_USER_PRESENT.
    //
    // On Android 8.0+ implicit broadcasts declared in the manifest are NOT
    // delivered, so the manifest entry for PhotoDayRotationReceiver cannot
    // receive USER_PRESENT on any modern device.  Registering here at runtime
    // solves this: the receiver lives as long as the app process is alive,
    // which covers the common case (user just used the app, locks phone,
    // unlocks → photo changes immediately).  When the process is killed the
    // 15-min AlarmManager fallback takes over.
    //
    // We register on first onStart and unregister only in onDestroy so the
    // receiver stays active even while the activity is in the back-stack.
    private var userPresentReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        takeSharedText(intent)
        // Пересоздание активности (поворот, тема) приносит тот же интент, и пуш
        // открыл бы Wallet второй раз.
        if (savedInstanceState == null) openWalletFromPush(intent)
    }

    // Приложение уже живёт в фоне: система переиспользует активность и шлёт
    // новый интент сюда, а не в onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeSharedText(intent)
        openWalletFromPush(intent)
        pendingSharedText?.let { text ->
            sharedTextChannel?.invokeMethod("shared", text)
            pendingSharedText = null
        }
    }

    // Касание по пушу «Togetherly Wallet вышел» (рассылает
    // `pocketbase/wallet_release.py`). Данные FCM приходят в интент лаунчера
    // дополнениями: `kind`, `package`, `url`. Wallet стоит — открываем его,
    // нет — страницу в магазине.
    private fun openWalletFromPush(intent: Intent?) {
        if (intent == null || intent.getStringExtra("kind") != "wallet") return
        val pkg = intent.getStringExtra("package") ?: "com.togetherly.money"
        val url = intent.getStringExtra("url")
        intent.removeExtra("kind")
        if (launchPackage(pkg)) return
        if (url.isNullOrBlank()) return
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            Log.w("MainActivity", "магазин для Wallet не открылся: ${e.message}")
        }
    }

    // Запуск чужого приложения по имени пакета. false — его нет на телефоне
    // или у него нет экрана запуска.
    private fun launchPackage(pkg: String): Boolean {
        val launch = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun takeSharedText(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) return
        if (intent.type != "text/plain") return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        if (text.isNotBlank()) pendingSharedText = text
    }

    override fun onStart() {
        super.onStart()
        if (userPresentReceiver == null) {
            userPresentReceiver = PhotoDayRotationReceiver()
            val filter = IntentFilter(Intent.ACTION_USER_PRESENT)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(userPresentReceiver, filter, RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(userPresentReceiver, filter)
            }
        }
    }

    override fun onDestroy() {
        userPresentReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        userPresentReceiver = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sharedTextChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/shared_text"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Первый кадр Flutter забирает то, что пришло до его старта.
                    "consumePending" -> {
                        result.success(pendingSharedText)
                        pendingSharedText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Сохранение медиа воспоминаний в галерею с датой и местом записи
        // (GallerySaver.kt). Папка одна — Pictures/Togetherly.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GallerySaver.CHANNEL
        ).setMethodCallHandler(GallerySaver(applicationContext))

        // Запись номеров фото-виджетов для фонового Dart: виджеты, стоявшие
        // до обновления, ещё не успели записать себя сами.
        WidgetIdRegistry.refresh(applicationContext)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/widgets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPhotoDayWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val legacy = manager.getAppWidgetIds(
                        ComponentName(this, PhotoDayWidgetProvider::class.java)
                    ).toList()
                    val selfIds = manager.getAppWidgetIds(
                        ComponentName(this, SelfPhotoWidgetProvider::class.java)
                    ).toList()
                    val partnerIds = manager.getAppWidgetIds(
                        ComponentName(this, PartnerPhotoWidgetProvider::class.java)
                    ).toList()
                    result.success((legacy + selfIds + partnerIds).distinct())
                }

                "getSelfPhotoWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, SelfPhotoWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "getPartnerPhotoWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, PartnerPhotoWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "getPhotoGridWidgetIds" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    val component = ComponentName(this, PhotoGridWidgetProvider::class.java)
                    result.success(manager.getAppWidgetIds(component).toList())
                }

                "updatePhotoDayCarousel" -> {
                    val widgetId = call.argument<Int>("widgetId")
                    val paths = call.argument<List<String>>("paths")
                    // Flutter computes the display index; use it so native receiver
                    // continues advancing from the correct position.
                    val currentIndex = call.argument<Int>("currentIndex") ?: 0

                    if (widgetId != null && paths != null) {
                        val prefs = getSharedPreferences("HomeWidgetPreferences", android.content.Context.MODE_PRIVATE)
                        val storedIndex = prefs.getInt("photo_day_widget_${widgetId}_current_index", -1)
                        val editor = prefs.edit()
                            .putString(
                                "photo_day_widget_${widgetId}_paths",
                                org.json.JSONArray(paths).toString()
                            )
                            .putInt("photo_day_widget_${widgetId}_current_index", currentIndex)

                        // Only update last_update when Flutter actually advanced the index.
                        // For "unlock" mode Flutter always sends the unchanged storedIndex —
                        // writing last_update = now on every sync would prevent the 15-min
                        // alarm fallback from ever firing and the photo would never change.
                        if (currentIndex != storedIndex) {
                            editor.putLong("photo_day_widget_${widgetId}_last_update", System.currentTimeMillis())
                        }
                        editor.apply()

                        PhotoDayWidgetProvider.scheduleRotationAlarm(this)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing widgetId or paths", null)
                    }
                }

                // Стереть всё, что виджеты знают о прошлом человеке.
                //
                // Данные виджетов лежат в общем хранилище устройства
                // (HomeWidgetPreferences), а не внутри аккаунта, и привязки
                // «этот виджет — эта пара» тоже. У человека с двумя аккаунтами
                // виджет свежей пары показал фото из прежней: «почему на
                // аккаунте где Настя не присылала ни одного фото, стоит фотка
                // Вики из совсем другого аккаунта» (14.08.2026). После очистки
                // рассылаем обновление всем провайдерам, чтобы на столе не
                // осталось нарисованного кадра.
                "wipeWidgetData" -> {
                    getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                        .edit().clear().apply()
                    val awm = AppWidgetManager.getInstance(this)
                    awm.installedProviders
                        .filter { it.provider.packageName == packageName }
                        .forEach { info ->
                            val ids = awm.getAppWidgetIds(info.provider)
                            if (ids.isNotEmpty()) {
                                sendBroadcast(
                                    Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                                        component = info.provider
                                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                                    }
                                )
                            }
                        }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // ── Кастомизация launcher-иконки через activity-alias ──
        // (продолжение ниже; здесь же живёт опрос состояния)
        // Включает выбранный alias и гасит остальные. DONT_KILL_APP — чтобы по
        // возможности не убивать процесс при смене (поведение зависит от лаунчера).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app_icon"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val id = call.argument<String>("id")
                    if (id == null || !ICON_ALIASES.containsKey(id)) {
                        result.error("INVALID_ARGS", "Unknown icon id: $id", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val pm = packageManager
                        for ((aliasId, suffix) in ICON_ALIASES) {
                            val component = ComponentName(packageName, "$packageName$suffix")
                            val state = if (aliasId == id)
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            else
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                            pm.setComponentEnabledSetting(
                                component, state, PackageManager.DONT_KILL_APP
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SET_ICON_FAILED", e.message, null)
                    }
                }

                // Какие alias система считает включёнными ПРЯМО СЕЙЧАС.
                //
                // Нужно, чтобы поймать два ярлыка на рабочем столе: выбранную
                // иконку приложение включает явно, и это переживает обновление,
                // а новый `.IconDefault` приезжает включённым из манифеста —
                // включённых становится два («обновил, стало два», 16.08.2026).
                // Состояние DEFAULT означает «как в манифесте», поэтому его
                // разбираем по нашей же карте: включён там только дефолтный.
                "enabledIcons" -> {
                    try {
                        val pm = packageManager
                        val on = mutableListOf<String>()
                        for ((aliasId, suffix) in ICON_ALIASES) {
                            val component = ComponentName(packageName, "$packageName$suffix")
                            val state = pm.getComponentEnabledSetting(component)
                            val enabled = when (state) {
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                                else -> aliasId == DEFAULT_ICON_ID
                            }
                            if (enabled) on.add(aliasId)
                        }
                        result.success(on)
                    } catch (e: Exception) {
                        result.error("ENABLED_ICONS_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // ── Целость установки ──
        // Приложение из Play приезжает базовым APK плюс докачиваемыми частями
        // под экран и архитектуру. Утилиты переноса на новый телефон, клоны в
        // «двойном пространстве» и APK, вытащенный из чужого телефона, копируют
        // только базовую часть. В таком состоянии библиотека Play Core рисует
        // собственное английское окно «Something went wrong» и закрывает
        // приложение — человек остаётся ни с чем и пишет в поддержку.
        //
        // Спросить об этом Play Core нельзя: он отвечает тем самым окном.
        // Поэтому проверяем сами, ровно по тем же двум признакам, что и он —
        // просит ли манифест докачиваемые части и лежат ли они на устройстве.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/install"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasMissingSplits" -> result.success(hasMissingSplits())
                // Кнопка Togetherly Wallet на главной (`WalletTeaser.open`).
                "launchPackage" -> result.success(
                    launchPackage(call.argument<String>("package") ?: "com.togetherly.money")
                )
                else -> result.notImplemented()
            }
        }

        // ── Пуши FCM ──
        // Токен в профиль пишет Dart (у него сессия PocketBase), а спрашивает
        // его отсюда. Плагин firebase_messaging не подключаем намеренно: на iOS
        // он перехватывает делегата APNs, где уже работает свой путь.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "love_app/fcm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Есть ли на телефоне сервисы Google. Где их нет (кастомные
                // прошивки), пушей не будет вовсе и остаётся foreground-сервис.
                "hasServices" -> {
                    val code = GoogleApiAvailability.getInstance()
                        .isGooglePlayServicesAvailable(this)
                    result.success(code == ConnectionResult.SUCCESS)
                }

                "getToken" -> {
                    try {
                        FirebaseMessaging.getInstance().token
                            .addOnCompleteListener { task ->
                                if (task.isSuccessful) {
                                    result.success(task.result)
                                } else {
                                    // Молчим об ошибке: телефон без сервисов
                                    // Google сюда и приходит, а пуши там не
                                    // работают в принципе.
                                    result.success(null)
                                }
                            }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        // Alias, включённый в манифесте. Всё, что в состоянии DEFAULT,
        // считается включённым только для него.
        private const val DEFAULT_ICON_ID = "default"

        // id (тема) -> суффикс android:name alias в манифесте.
        private val ICON_ALIASES = linkedMapOf(
            "default" to ".IconDefault",
            "pink" to ".IconPink",
            "purple" to ".IconPurple",
            "blue" to ".IconBlue",
            "green" to ".IconGreen",
            "midnight" to ".IconMidnight",
            "orange" to ".IconOrange",
            "lavender" to ".IconLavender",
            "cherry" to ".IconCherry",
            "mint" to ".IconMint",
            "sunset" to ".IconSunset",
            "monochrome" to ".IconMonochrome",
            "forest" to ".IconForest",
            "ocean" to ".IconOcean",
        )
    }

    /// Ставилось ли приложение как набор частей, которых теперь нет.
    ///
    /// `com.android.vending.splits.required` в манифест кладёт Play при сборке
    /// бандла, поэтому у одиночного APK флага нет и проверка молчит — там
    /// докачивать нечего по определению.
    private fun hasMissingSplits(): Boolean {
        return try {
            val appInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )
            val requiresSplits =
                appInfo.metaData?.getBoolean("com.android.vending.splits.required", false)
                    ?: false
            if (!requiresSplits) return false
            val info = packageManager.getPackageInfo(packageName, 0)
            info.splitNames.isNullOrEmpty()
        } catch (e: Exception) {
            // Не смогли выяснить — молчим. Ложная тревога здесь хуже пропуска:
            // она уводит человека переустанавливать исправное приложение.
            false
        }
    }
}
