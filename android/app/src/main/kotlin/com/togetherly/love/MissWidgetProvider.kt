package com.togetherly.love

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * Виджет «Скучаю» — парный, интерактивный.
 *
 * Три размера из хендофа: 2×2 (карточка на tertiary-container с пилюлей),
 * 4×2 (счётчики обоих + кнопка отправки) и 4×1 (полоска на primary).
 * Раскладку выбираем по фактическому размеру ячейки.
 *
 * Тап отправляет «скучаю»: `HomeWidgetBackgroundIntent` будит Dart-колбэк
 * (`loveapp://miss`) даже когда процесс приложения мёртв, а тот пишет в
 * PocketBase и обновляет данные виджета. Локально сразу переводим карточку в
 * состояние «отправлено», чтобы палец получил отклик без ожидания сети.
 */
open class MissWidgetProvider : HomeWidgetProvider() {

    /** Раскладка, закреплённая за провайдером; null — выбирать по размеру. */
    protected open val forcedLayout: Int? = null

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    /**
     * Тап по кнопке. Раньше он уходил сразу в Dart, и до ответа сети виджет не
     * менялся вообще — кнопка выглядела мёртвой. Теперь состояние пишется здесь
     * же, виджет перерисовывается мгновенно, и только потом будится Dart,
     * который отправляет «скучаю» на сервер.
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TAP) {
            super.onReceive(context, intent)
            return
        }

        val g = intent.getStringExtra(EXTRA_GROUP).orEmpty()
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val prefix = if (g.isEmpty()) "" else "miss_${g}_"

        // Второй тап за день ничего не меняет: по спецификации отправка одна,
        // состояние живёт до полуночи.
        if (prefs.getString("${prefix}sent_today", null) != "1") {
            val my = prefs.getString("${prefix}my_count", null)?.toIntOrNull() ?: 0
            val now = Calendar.getInstance()
            val hh = now.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
            val mm = now.get(Calendar.MINUTE).toString().padStart(2, '0')
            prefs.edit()
                .putString("${prefix}my_count", (my + 1).toString())
                .putString("${prefix}sent_today", "1")
                .putString("${prefix}last_time", "$hh:$mm")
                // Отметка «отправка ждёт сервера». Фоновый Dart снимет её сам,
                // а если движок не поднялся или сессия PocketBase протухла —
                // приложение дошлёт при следующем запуске. Без этой отметки
                // виджет говорил «отправлено», а до партнёра ничего не доходило.
                .putString("${prefix}pending_send", "1")
                .apply()

            // Перерисовываем все три размера: пользователь мог поставить
            // несколько экземпляров, и отстать не должен ни один.
            val manager = AppWidgetManager.getInstance(context)
            listOf(
                MissWidget2x2Provider::class.java,
                MissWidget4x2Provider::class.java,
                MissWidget4x1Provider::class.java,
            ).forEach { cls ->
                manager.getAppWidgetIds(ComponentName(context, cls)).forEach { id ->
                    render(context, manager, id, prefs)
                }
            }
        }

        // Счётчик уже увеличен здесь — Dart об этом узнаёт по local=1 и только
        // отправляет реакцию на сервер, не прибавляя второй раз.
        try {
            HomeWidgetBackgroundIntent
                .getBroadcast(context, Uri.parse("loveapp://miss?group=$g&local=1"))
                .send()
        } catch (e: Exception) {
            android.util.Log.w("MissWidget", "не удалось разбудить Dart: $e")
        }
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "miss", widgetId)
        val prefix = if (g.isEmpty()) "" else "miss_${g}_"

        val partnerName = data.getString("${prefix}partner_name", null).orEmpty()
        val partnerInitial = data.getString("${prefix}partner_initial", null)
            .orEmpty().ifEmpty { partnerName.take(1).uppercase().ifEmpty { "?" } }
        val myCount = data.getString("${prefix}my_count", null)?.toIntOrNull() ?: 0
        val partnerCount = data.getString("${prefix}partner_count", null)?.toIntOrNull() ?: 0
        val lastTime = data.getString("${prefix}last_time", null).orEmpty()
        val partnerAvatarPath = data.getString("${prefix}partner_avatar_path", null)
        // Строки и запись чисел приходят из приложения: раньше «Скучаю»,
        // «Отправлено» и «последний раз в …» лежали здесь по-русски, а число
        // печаталось как есть — «1000» рвалось на две строки.
        val myText = data.getString("${prefix}my_text", null).orEmpty()
            .ifEmpty { myCount.toString() }
        val partnerText = data.getString("${prefix}partner_text", null).orEmpty()
            .ifEmpty { partnerCount.toString() }
        val meLabel = data.getString("${prefix}me_label", null).orEmpty()
        val sendLabel = data.getString("${prefix}send_label", null).orEmpty()
        val whenLabel = data.getString("${prefix}when_label", null).orEmpty()
        val todayLabel = data.getString("${prefix}today_label", null).orEmpty()
        // Отправляли ли сегодня — состояние живёт до конца дня, как в хендофе.
        val sent = data.getString("${prefix}sent_today", null) == "1"

        val options = manager.getAppWidgetOptions(widgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)

        val layout = forcedLayout ?: when {
            minWidth >= 200 && minHeight < 110 -> R.layout.tg_miss_4x1
            minWidth >= 200 -> R.layout.tg_miss_4x2
            else -> R.layout.tg_miss_2x2
        }

        val stateIcon = if (sent) R.drawable.ic_tg_check else R.drawable.ic_tg_heart
        // Тап идёт в собственный onReceive, а не сразу в Dart: сначала мгновенно
        // меняем состояние виджета, потом уже сеть.
        val tapIntent = PendingIntent.getBroadcast(
            context,
            widgetId,
            Intent(context, javaClass).apply {
                action = ACTION_TAP
                putExtra(EXTRA_GROUP, g)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Та же вилка высот, что и у «Вместе»: на просторной ячейке кегли
        // растягиваются, на тесной остаются компактными.
        val baseDp = if (layout == R.layout.tg_miss_4x1) 56 else 115
        val scale = WidgetSizing.scale(minHeight, baseDp)
        // Цвета из активной темы приложения; пока не прислали — из хендофа.
        val theme = WidgetTheme.from(data)

        val views = RemoteViews(context.packageName, layout).apply {
            setImageViewResource(R.id.state_icon, stateIcon)

            val photo = WidgetImages.circularFromFile(partnerAvatarPath)

            /** Кегль числа: чем больше знаков, тем мельче (miss_widget_spec.dart). */
            fun countSize(text: String, base: Float): Float {
                val digits = text.length
                val size = when {
                    digits <= 2 -> base
                    digits == 3 -> base * 0.86f
                    digits == 4 -> base * 0.74f
                    else -> base * 0.62f
                }
                return if (size < 16f) 16f else size
            }

            fun bindPartnerFace() {
                setTextViewText(R.id.avatar, partnerInitial)
                if (photo != null) {
                    setImageViewBitmap(R.id.avatar_photo, photo)
                    setViewVisibility(R.id.avatar_photo, View.VISIBLE)
                    setViewVisibility(R.id.avatar, View.INVISIBLE)
                } else {
                    setViewVisibility(R.id.avatar_photo, View.GONE)
                    setViewVisibility(R.id.avatar, View.VISIBLE)
                }
            }

            when (layout) {
                R.layout.tg_miss_2x2 -> {
                    tint(R.id.bg, theme.surface)
                    tint(R.id.avatar_bg, theme.avatarPartner)
                    tint(R.id.send_bg, theme.primary)
                    tint(R.id.state_icon, theme.onPrimary)
                    setTextColor(R.id.avatar, theme.onTertiaryContainer)
                    setTextColor(R.id.partner_label, theme.onSurfaceVariant)
                    setTextColor(R.id.my_count, theme.onSurface)
                    setTextColor(R.id.partner_count, theme.outline)
                    setTextColor(R.id.last_time, theme.outline)
                    setTextColor(R.id.send_label, theme.onPrimary)

                    bindPartnerFace()
                    setTextViewText(R.id.partner_label, partnerName)
                    setTextViewText(R.id.my_count, myText)
                    setTextViewText(R.id.partner_count, "/ $partnerText")
                    setTextViewTextSize(
                        R.id.my_count,
                        TypedValue.COMPLEX_UNIT_DIP,
                        countSize(myText, 30f * scale),
                    )
                    setTextViewText(R.id.last_time, whenLabel.ifEmpty { todayLabel })
                    setTextViewText(R.id.send_label, sendLabel)

                    setOnClickPendingIntent(R.id.send_button, tapIntent)
                    setOnClickPendingIntent(
                        R.id.widget_root,
                        HomeWidgetLaunchIntentCompat.home(context),
                    )
                }

                R.layout.tg_miss_4x2 -> {
                    tint(R.id.bg, theme.surface)
                    tint(R.id.my_tile_bg, theme.primaryContainer)
                    tint(R.id.partner_tile_bg, theme.tertiaryContainer)
                    tint(R.id.my_avatar_bg, theme.avatarMine)
                    tint(R.id.avatar_bg, theme.avatarPartner)
                    tint(R.id.send_bg, theme.primary)
                    tint(R.id.state_icon, theme.onPrimary)
                    setTextColor(R.id.my_avatar, theme.onPrimaryContainer)
                    setTextColor(R.id.avatar, theme.onTertiaryContainer)
                    setTextColor(R.id.my_label, theme.onPrimaryContainer)
                    setTextColor(R.id.partner_label, theme.onTertiaryContainer)
                    setTextColor(R.id.my_count, theme.onPrimaryContainer)
                    setTextColor(R.id.partner_count, theme.onTertiaryContainer)
                    setTextColor(R.id.last_time, theme.outline)
                    setTextColor(R.id.send_label, theme.onPrimary)

                    bindPartnerFace()
                    setTextViewText(R.id.my_avatar, meLabel.take(1).uppercase())
                    setTextViewText(R.id.my_label, meLabel)
                    setTextViewText(R.id.partner_label, partnerName)
                    setTextViewText(R.id.my_count, myText)
                    setTextViewText(R.id.partner_count, partnerText)
                    // Кегли считаются по ДЛИННЕЙШЕМУ из двух: плитки одинаковой
                    // ширины, и числа в них должны быть одного роста.
                    val longest = if (myText.length >= partnerText.length) myText else partnerText
                    val size = countSize(longest, 30f * scale)
                    setTextViewTextSize(R.id.my_count, TypedValue.COMPLEX_UNIT_DIP, size)
                    setTextViewTextSize(R.id.partner_count, TypedValue.COMPLEX_UNIT_DIP, size)
                    setTextViewText(R.id.last_time, whenLabel)
                    setViewVisibility(
                        R.id.last_time,
                        if (whenLabel.isEmpty()) View.GONE else View.VISIBLE,
                    )
                    setTextViewText(R.id.send_label, sendLabel)

                    setOnClickPendingIntent(R.id.send_button, tapIntent)
                    setOnClickPendingIntent(
                        R.id.widget_root,
                        HomeWidgetLaunchIntentCompat.home(context),
                    )
                }

                else -> {
                    tint(R.id.bg, theme.primary)
                    tint(R.id.avatar_bg, theme.avatarPartner)
                    tint(R.id.send_bg, theme.onPrimary)
                    tint(R.id.state_icon, theme.primary)
                    setTextColor(R.id.avatar, theme.onTertiaryContainer)
                    setTextColor(R.id.title, theme.onPrimary)
                    setTextColor(R.id.subtitle, theme.onPrimarySoft)

                    bindPartnerFace()
                    setTextViewText(R.id.title, sendLabel)
                    setTextViewText(
                        R.id.subtitle,
                        listOf("$myText · $partnerText", whenLabel.ifEmpty { todayLabel })
                            .filter { it.isNotBlank() }
                            .joinToString(" · "),
                    )

                    setOnClickPendingIntent(R.id.send_button, tapIntent)
                    setOnClickPendingIntent(
                        R.id.widget_root,
                        HomeWidgetLaunchIntentCompat.home(context),
                    )
                }
            }
        }

        manager.updateAppWidget(widgetId, views)
    }

    /** «Мише», «Ане» — дательный падеж для коротких русских имён. */
    private fun dativeName(name: String): String {
        val n = name.trim()
        if (n.isEmpty()) return "Партнёру"
        return when {
            n.endsWith("а", true) || n.endsWith("я", true) -> n.dropLast(1) + "е"
            n.endsWith("й", true) -> n.dropLast(1) + "ю"
            else -> n + "у"
        }
    }

    companion object {
        /** Тап по кнопке «Скучаю». Ловится в onReceive этого же провайдера. */
        const val ACTION_TAP = "com.togetherly.love.action.MISS_TAP"
        const val EXTRA_GROUP = "group"
    }
}

/** «Скучаю» 2×2 — отдельная позиция в списке виджетов. */
class MissWidget2x2Provider : MissWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_miss_2x2
}

/** «Скучаю» 4×2. */
class MissWidget4x2Provider : MissWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_miss_4x2
}

/** «Скучаю» полоской 4×1. */
class MissWidget4x1Provider : MissWidgetProvider() {
    override val forcedLayout: Int = R.layout.tg_miss_4x1
}

/** Открытие приложения из виджета — вынесено, чтобы не плодить дубли. */
object HomeWidgetLaunchIntentCompat {
    fun home(context: Context) = es.antonborri.home_widget.HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("loveapp://home"),
    )
}
