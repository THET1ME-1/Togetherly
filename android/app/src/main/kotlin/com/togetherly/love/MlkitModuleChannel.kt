package com.togetherly.love

import android.content.Context
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.barcode.BarcodeScanning
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Модель распознавания QR больше не лежит в APK — её ставят сервисы Google по
 * запросу (см. `dev.steenbakker.mobile_scanner.useUnbundled` в
 * gradle.properties): минус 5,5 МБ из каждой сборки.
 *
 * Цена — первый раз модель надо скачать, и делать это молча нельзя: человек
 * наводит камеру на QR партнёра, а она секунд десять не видит ничего. Поэтому
 * установка идёт через `ModuleInstallClient` с настоящим прогрессом.
 *
 * Скачивает САМ Google Play Services, в своём процессе. Отсюда два свойства,
 * которых не было бы у загрузки внутри приложения: её не обрывает закрытие
 * экрана и не убивает выгрузка приложения из памяти — вернувшись, человек
 * увидит либо готовую модель, либо продолжение той же загрузки. Наше дело —
 * показать состояние и не заблокировать интерфейс: все вызовы асинхронные,
 * ответы приходят колбэками на главный поток.
 */
class MlkitModuleChannel(context: Context, messenger: BinaryMessenger) {

    private val appContext = context.applicationContext
    private val client = ModuleInstall.getClient(appContext)

    /** Тот же API, что просит mobile_scanner: сканер штрихкодов ML Kit. */
    private val barcodeApi = BarcodeScanning.getClient()

    private var events: EventChannel.EventSink? = null

    /** Не запускаем вторую установку поверх идущей — GMS её и так склеит. */
    private var installing = false

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> status(result)
                "install" -> install(result)
                // Тихая загрузка «когда-нибудь»: GMS выберет удобный момент
                // (Wi-Fi, зарядка). Зовём заранее — на экране подключения, ещё
                // до того, как человек нажмёт «сканировать».
                "warmUp" -> {
                    runCatching { client.deferredInstall(barcodeApi) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            }
        )
    }

    /** `ready` — можно сканировать, `needsInstall` — надо скачать, `unavailable`
     *  — сервисов Google на телефоне нет и не будет. */
    private fun status(result: MethodChannel.Result) {
        client.areModulesAvailable(barcodeApi)
            .addOnSuccessListener { response ->
                result.success(if (response.areModulesAvailable()) READY else NEEDS_INSTALL)
            }
            .addOnFailureListener {
                // Сюда попадают телефоны без GMS и урезанные прошивки. Ошибку
                // не бросаем: для Flutter это штатное состояние, а не сбой.
                result.success(UNAVAILABLE)
            }
    }

    private fun install(result: MethodChannel.Result) {
        if (installing) {
            result.success(true)
            return
        }
        val listener = InstallStatusListener { update -> send(update) }
        val request = ModuleInstallRequest.newBuilder()
            .addApi(barcodeApi)
            .setListener(listener)
            .build()

        installing = true
        client.installModules(request)
            .addOnSuccessListener { response ->
                if (response.areModulesAlreadyInstalled()) {
                    installing = false
                    events?.success(mapOf("state" to READY, "percent" to 100))
                }
                result.success(true)
            }
            .addOnFailureListener {
                installing = false
                events?.success(mapOf("state" to UNAVAILABLE, "percent" to 0))
                result.success(false)
            }
    }

    private fun send(update: ModuleInstallStatusUpdate) {
        val progress = update.progressInfo
        // Доля считается только когда GMS назвал общий размер: делить на ноль
        // и показывать «0%» весь путь хуже, чем не показывать процент вовсе.
        val total = progress?.totalBytesToDownload ?: 0L
        val done = progress?.bytesDownloaded ?: 0L
        val percent = if (total > 0L) (done * 100 / total).toInt() else -1

        val state = when (update.installState) {
            ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> READY
            ModuleInstallStatusUpdate.InstallState.STATE_FAILED,
            ModuleInstallStatusUpdate.InstallState.STATE_CANCELED -> UNAVAILABLE
            else -> INSTALLING
        }
        if (state != INSTALLING) installing = false

        events?.success(mapOf("state" to state, "percent" to percent))
    }

    companion object {
        const val CHANNEL = "love_app/mlkit_module"
        const val PROGRESS_CHANNEL = "love_app/mlkit_module/progress"

        private const val READY = "ready"
        private const val NEEDS_INSTALL = "needsInstall"
        private const val INSTALLING = "installing"
        private const val UNAVAILABLE = "unavailable"
    }
}
