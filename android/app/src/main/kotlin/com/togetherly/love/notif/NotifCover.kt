package com.togetherly.love.notif

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.togetherly.love.MainActivity
import com.togetherly.love.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Показ уведомления «А. Обложка» (28.11.2026).
 *
 * Свёрнуто: плашка 44dp, подпись тона, заголовок Unbounded, строка текста.
 * Развёрнуто: плашка 96dp, текст целиком и кнопки в цвете тона. Шапку с
 * белым сердечком, именем и временем рисует система (DecoratedCustomViewStyle):
 * так уведомление остаётся своим в шторке любой оболочки.
 *
 * Зовётся из потока службы FCM или из пула канала Dart, не с главного:
 * картинки качаются здесь же, до показа.
 */
object NotifCover {
    private const val TAG = "NotifCover"
    const val CHANNEL_PARTNER = "partner_notifications"

    /**
     * Сколько ждать картинок (5 с — описание «А»): показать важнее. Картинки
     * каталога и аватары почти всегда уже на диске (`NotifArt`), ждёт только
     * новое.
     */
    const val IMAGES_BUDGET_MS = 5_000L

    /** Розовый круг под сердечком в шапке — как в макете и на иконке. */
    const val ACCENT = 0xFFFF7E8B.toInt()

    /**
     * Показать [cover] под меткой [tag] и номером [id] (у пуша — вид события и
     * 0, как у прежнего пуша FCM: своё уведомление Dart встаёт туда же).
     */
    /**
     * [ongoing] — постоянная плашка, смахнуть нельзя («Дни вместе»),
     * [silent] — без звука и всплытия.
     */
    fun show(
        ctx: Context, cover: Cover, raw: String, tag: String, id: Int, channel: String = CHANNEL_PARTNER,
        ongoing: Boolean = false, silent: Boolean = false,
    ) {
        ensureChannel(ctx, channel)
        if (cover.chat != null) {
            NotifChat.show(ctx, cover, raw, tag, id, channel)
            return
        }
        if (cover.kind == "mood_lock") {
            showMoodLock(ctx, cover, raw, tag, id, channel)
            return
        }
        val tone = Tones.of(cover.tone)
        val density = ctx.resources.displayMetrics.density
        val smallSide = (44 * density).toInt()
        val bigSide = (96 * density).toInt()

        // У уведомления приложения в свёрнутом иконка, в развёрнутом картинка события.
        val bigArt = cover.artBig ?: cover.art
        val wanted = buildMap<String, Art> {
            if (cover.art.url.isNotEmpty()) put("art", cover.art)
            if (cover.artBig != null && cover.artBig.url.isNotEmpty()) put("big", cover.artBig)
        }
        val got = NotifArt.fetchAll(ctx, wanted, IMAGES_BUDGET_MS)
        val smallTile = NotifArt.tile(ctx, cover.art, got["art"], tone, smallSide)
        val bigTile = NotifArt.tile(ctx, bigArt, if (cover.artBig != null) got["big"] else got["art"], tone, bigSide)

        val collapsed = RemoteViews(ctx.packageName, R.layout.notif_cover)
        val expanded = RemoteViews(ctx.packageName, R.layout.notif_cover_big)
        for ((views, tile) in listOf(collapsed to smallTile, expanded to bigTile)) {
            fillTexts(ctx, views, cover, tone, tile)
        }
        fillButtons(ctx, expanded, cover, raw, tone, tag, id)

        val builder = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ACCENT)
            // Заголовок и текст обычным образом — для экрана блокировки со
            // скрытым содержимым, часов, озвучки и оболочек без своих вид.
            .setContentTitle(cover.title.ifEmpty { cover.kicker })
            .setContentText(cover.body)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setContentIntent(open(ctx, cover.link))
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
            .setSilent(silent)
            .setOnlyAlertOnce(silent)
            .setPriority(if (silent) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
            .setCategory(
                when {
                    ongoing -> NotificationCompat.CATEGORY_STATUS
                    cover.fromApp -> NotificationCompat.CATEGORY_REMINDER
                    else -> NotificationCompat.CATEGORY_SOCIAL
                },
            )
        if (ongoing) {
            // Постоянная плашка («Дни вместе») — как была у плагина: без
            // времени показа и видна на экране блокировки.
            builder.setShowWhen(false).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        }
        post(ctx, tag, id, builder)
    }

    /**
     * Настроение на экране блокировки: постоянная тихая плашка, видна без
     * разблокировки; развёрнуто — ряд котиков «Моти», каждый отмечает
     * настроение прямо со шторки (`NotifActions`, действие `mood:<номер>`).
     */
    private fun showMoodLock(ctx: Context, cover: Cover, raw: String, tag: String, id: Int, channel: String) {
        val tone = Tones.of(cover.tone)
        val density = ctx.resources.displayMetrics.density
        val wanted = buildMap<String, Art> {
            if (cover.art.url.isNotEmpty()) put("art", cover.art)
            cover.moods.forEachIndexed { i, m -> put("m$i", Art(url = m.url)) }
        }
        val got = NotifArt.fetchAll(ctx, wanted, IMAGES_BUDGET_MS)
        val collapsed = RemoteViews(ctx.packageName, R.layout.notif_cover)
        val expanded = RemoteViews(ctx.packageName, R.layout.notif_mood_lock_big)
        fillTexts(ctx, collapsed, cover, tone, NotifArt.tile(ctx, cover.art, got["art"], tone, (44 * density).toInt()))
        fillTexts(ctx, expanded, cover, tone, NotifArt.tile(ctx, cover.art, got["art"], tone, (56 * density).toInt()))
        val slots = listOf(R.id.notif_mood1, R.id.notif_mood2, R.id.notif_mood3, R.id.notif_mood4, R.id.notif_mood5)
        val side = (48 * density).toInt()
        slots.forEachIndexed { i, slot ->
            val choice = cover.moods.getOrNull(i)
            val bitmap = got["m$i"]
            if (choice == null || bitmap == null) {
                expanded.setViewVisibility(slot, android.view.View.GONE)
                return@forEachIndexed
            }
            // Котик уменьшенным: пять картинок в одном уведомлении.
            val k = side.toFloat() / maxOf(bitmap.width, bitmap.height)
            val small = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * k).toInt()), maxOf(1, (bitmap.height * k).toInt()), true)
            expanded.setImageViewBitmap(slot, small)
            expanded.setContentDescription(slot, choice.label)
            expanded.setOnClickPendingIntent(slot, NotifActionReceiver.pending(ctx, "mood:${choice.id}", tag, id, mutable = false, raw = raw))
        }
        if (cover.moods.isEmpty()) expanded.setViewVisibility(R.id.notif_moods, android.view.View.GONE)
        val builder = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ACCENT)
            .setContentTitle(cover.title.ifEmpty { cover.kicker })
            .setContentText(cover.body)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setContentIntent(open(ctx, cover.link))
            .setOngoing(true)
            .setAutoCancel(false)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // Видна без разблокировки: ради этого плашку и включают.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
        post(ctx, tag, id, builder)
    }

    /** Канал уведомления, что сейчас в шторке, — чтобы перерисовать туда же. */
    fun activeChannel(ctx: Context, tag: String, id: Int): String? {
        if (Build.VERSION.SDK_INT < 26) return null
        return try {
            ctx.getSystemService(NotificationManager::class.java)?.activeNotifications
                ?.firstOrNull { (it.tag ?: "") == tag && it.id == id }?.notification?.channelId
        } catch (_: Exception) {
            null
        }
    }

    private fun fillTexts(ctx: Context, views: RemoteViews, cover: Cover, tone: Tone, tile: Bitmap) {
        views.setImageViewBitmap(R.id.notif_cover, tile)
        views.setTextViewText(R.id.notif_kicker, cover.kicker)
        views.setTextViewText(R.id.notif_title, cover.title.ifEmpty { cover.kicker })
        views.setTextViewText(R.id.notif_body, cover.body)
        views.setViewVisibility(R.id.notif_body, if (cover.body.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE)
        // Подпись тона тёмная, на тёмной шторке нужен светлый вариант. С
        // Android 12 цвет выбирает сама система при показе.
        if (Build.VERSION.SDK_INT >= 31) {
            views.setColorInt(R.id.notif_kicker, "setTextColor", tone.label, tone.labelNight)
        } else {
            views.setTextColor(R.id.notif_kicker, if (night(ctx)) tone.labelNight else tone.label)
        }
    }

    private fun night(ctx: Context): Boolean =
        ctx.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    /** Кнопки поровну на ширину: первая насыщенная, вторая плашкой тона. */
    private fun fillButtons(ctx: Context, views: RemoteViews, cover: Cover, raw: String, tone: Tone, tag: String, id: Int) {
        val actions = cover.actions.take(2)
        if (actions.isEmpty()) {
            views.setViewVisibility(R.id.notif_buttons, android.view.View.GONE)
            return
        }
        val slots = listOf(
            Triple(R.id.notif_btn1, R.id.notif_btn1_bg, R.id.notif_btn1_text),
            Triple(R.id.notif_btn2, R.id.notif_btn2_bg, R.id.notif_btn2_text),
        )
        slots.forEachIndexed { i, (frame, bg, text) ->
            val action = actions.getOrNull(i)
            if (action == null) {
                views.setViewVisibility(frame, android.view.View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(frame, android.view.View.VISIBLE)
            views.setTextViewText(text, action.label)
            views.setInt(bg, "setColorFilter", if (i == 0) tone.deep else tone.tint)
            views.setTextColor(text, if (i == 0) 0xFFFFFFFF.toInt() else tone.label)
            views.setOnClickPendingIntent(frame, actionIntent(ctx, cover, raw, action, tag, id))
        }
    }

    /** Нажатие кнопки: экран — через приложение, своё действие — приёмнику. */
    private fun actionIntent(ctx: Context, cover: Cover, raw: String, action: CoverAction, tag: String, id: Int): PendingIntent =
        if (!action.native) open(ctx, action.link)
        else NotifActionReceiver.pending(ctx, action.id, tag, id, mutable = false, raw = raw)

    /**
     * Открыть экран приложения по ссылке `loveapp://open/<экран>` — тем же
     * путём, что нажатие на виджет: Dart ловит её `HomeWidget.widgetClicked`,
     * и на холодном старте тоже.
     */
    fun open(ctx: Context, link: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(ctx, MainActivity::class.java, Uri.parse(CoverParser.safeLink(link)))

    /** Канал заводит Dart (`PbPushService.init`); пуш мог прийти раньше. */
    fun ensureChannel(ctx: Context, channel: String) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(channel) != null) return
        if (channel != CHANNEL_PARTNER) return // чужие каналы заводит их служба
        nm.createNotificationChannel(
            NotificationChannel(channel, ctx.getString(R.string.notif_channel_partner), NotificationManager.IMPORTANCE_HIGH),
        )
    }

    /** Показать, если человек разрешил уведомления (Android 13+ спрашивает). */
    fun post(ctx: Context, tag: String, id: Int, builder: NotificationCompat.Builder) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.i(TAG, "уведомления выключены — молчим")
            return
        }
        try {
            // Пустая метка — без метки: так ставит плагин уведомлений, и его
            // отмена по номеру снимает и наше (уведомления по расписанию).
            NotificationManagerCompat.from(ctx).notify(tag.ifEmpty { null }, id, builder.build())
        } catch (e: SecurityException) {
            Log.w(TAG, "не показано: ${e.message}")
        }
    }

    /**
     * Запасной показ: обложка не разобралась или рисование упало. Пуш данными
     * система сама не покажет, поэтому без этого человек не узнал бы ничего.
     */
    fun plain(
        ctx: Context, title: String, body: String, tag: String, id: Int, link: String = "loveapp://open/home",
        channel: String = CHANNEL_PARTNER, ongoing: Boolean = false, silent: Boolean = false,
    ) {
        // Свой канал уведомления (тихий у «Дней вместе»); его нет — канал партнёра.
        val ch = if (channel == CHANNEL_PARTNER || channelExists(ctx, channel)) channel else CHANNEL_PARTNER
        ensureChannel(ctx, ch)
        val builder = NotificationCompat.Builder(ctx, ch)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ACCENT)
            .setContentTitle(title.ifEmpty { "Togetherly" })
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open(ctx, link))
            .setAutoCancel(!ongoing)
            .setOngoing(ongoing)
            .setSilent(silent)
            .setOnlyAlertOnce(silent)
            .setPriority(if (silent) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
        if (ongoing) builder.setShowWhen(false).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        post(ctx, tag, id, builder)
    }

    private fun channelExists(ctx: Context, channel: String): Boolean {
        if (Build.VERSION.SDK_INT < 26) return true
        return ctx.getSystemService(NotificationManager::class.java)?.getNotificationChannel(channel) != null
    }

    /** Убрать уведомление после выполненного действия из шторки. */
    fun cancel(ctx: Context, tag: String, id: Int) {
        NotificationManagerCompat.from(ctx).cancel(tag.ifEmpty { null }, id)
    }
}
