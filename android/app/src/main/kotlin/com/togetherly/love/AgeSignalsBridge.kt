package com.togetherly.love

import android.app.Activity
import android.util.Log
import com.google.android.play.agesignals.AgeSignalsAccessRequest
import com.google.android.play.agesignals.AgeSignalsException
import com.google.android.play.agesignals.AgeSignalsManager
import com.google.android.play.agesignals.AgeSignalsManagerFactory
import com.google.android.play.agesignals.AgeSignalsRequest
import com.google.android.play.agesignals.ApplicableAgeFeaturesRequest
import com.google.android.play.agesignals.model.AgeSignalsStatus
import com.google.android.play.agesignals.model.ApplicableAgeFeature
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Возраст человека из Google Play (Play Age Signals), канал
 * `love_app/age_signals`, разбор ответа — `lib/services/age_signals.dart`.
 *
 * Закон Калифорнии AB 1043 с 01.01.2027 обязывает спрашивать возраст при
 * запуске, бразильский ECA Digital — учитывать его. Порядок по документации
 * Google (библиотека 0.0.6):
 * 1. `getApplicableAgeFeatures` — действует ли для человека обязательная
 *    передача возраста (`MANDATORY_SHARING`).
 * 2. Только если действует — `requestAgeSignalsAccess(activity)`. В остальном
 *    мире этот вызов показал бы окно Play «поделиться возрастом» всем, у кого
 *    стоит «спрашивать», а закон там ничего не требует.
 * 3. Доступ открыт (`SHARED`) — `checkAgeSignals`, границы группы.
 *
 * Ответ: `{mandatory, status, lower, upper}`, при сбое `{error: код}`.
 * Сбоем считается и сборка не из Play (`APP_NOT_OWNED`, RuStore и APK с
 * сайта): Dart тогда оставляет прошлый ответ.
 */
class AgeSignalsBridge(private val activity: () -> Activity?) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "love_app/age_signals"
        private const val TAG = "AgeSignals"
    }

    private var manager: AgeSignalsManager? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" -> check(result)
            else -> result.notImplemented()
        }
    }

    private fun check(result: MethodChannel.Result) {
        val host = activity()
        if (host == null) {
            result.success(mapOf("error" to "no_activity"))
            return
        }
        val signals = try {
            manager ?: AgeSignalsManagerFactory.create(host.applicationContext).also { manager = it }
        } catch (e: Exception) {
            Log.w(TAG, "менеджер не создался: $e")
            result.success(mapOf("error" to "no_manager"))
            return
        }

        signals.getApplicableAgeFeatures(ApplicableAgeFeaturesRequest.builder().build())
            .addOnSuccessListener { features ->
                if (!features.features().contains(ApplicableAgeFeature.MANDATORY_SHARING)) {
                    result.success(mapOf("mandatory" to false, "status" to "not_asked"))
                    return@addOnSuccessListener
                }
                requestAccess(signals, host, result)
            }
            .addOnFailureListener { error -> fail(result, error) }
    }

    private fun requestAccess(signals: AgeSignalsManager, host: Activity, result: MethodChannel.Result) {
        val request = AgeSignalsAccessRequest.builder().setActivity(host).build()
        signals.requestAgeSignalsAccess(request)
            .addOnSuccessListener { access ->
                when (access.ageSignalsStatus()) {
                    AgeSignalsStatus.SHARED -> readSignals(signals, result)
                    AgeSignalsStatus.VERIFICATION_REQUIRED ->
                        result.success(mapOf("mandatory" to true, "status" to "verification_required"))
                    else -> result.success(mapOf("mandatory" to true, "status" to "not_shared"))
                }
            }
            .addOnFailureListener { error -> fail(result, error) }
    }

    private fun readSignals(signals: AgeSignalsManager, result: MethodChannel.Result) {
        signals.checkAgeSignals(AgeSignalsRequest.builder().build())
            .addOnSuccessListener { answer ->
                result.success(
                    mapOf(
                        "mandatory" to true,
                        "status" to "shared",
                        "lower" to answer.ageLower(),
                        "upper" to answer.ageUpper(),
                    )
                )
            }
            .addOnFailureListener { error -> fail(result, error) }
    }

    private fun fail(result: MethodChannel.Result, error: Exception) {
        val code = (error as? AgeSignalsException)?.errorCode ?: "unknown"
        Log.w(TAG, "магазин не ответил: $code $error")
        result.success(mapOf("error" to code))
    }
}
