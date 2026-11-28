package com.togetherly.love.notif

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import androidx.core.content.FileProvider
import androidx.core.content.LocusIdCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.togetherly.love.MainActivity
import com.togetherly.love.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.io.File
import java.io.FileOutputStream

/**
 * Сообщение чата в шторке — переписка «как в Телеграме, но красивее»:
 * аватар партнёра в его рамке из приложения, история последних строк с
 * фото и своими ответами, «Ответить» с нежными быстрыми ответами, «Обнять»
 * одним нажатием, «Прочитано». Ярлык разговора кладёт пару в раздел
 * «Разговоры» Android 11+ с аватаром вместо значка приложения.
 */
object NotifChat {
    private const val TAG = "NotifChat"
    const val EXTRA_IDS = "tg_chat_ids"
    const val EXTRA_COVER = "tg_cover"
    const val REPLY_KEY = "tg_reply_text"
    private const val AUTHORITY_SUFFIX = ".notifimages"

    fun show(ctx: Context, cover: Cover, raw: String, tag: String, id: Int, channel: String) {
        val part = cover.chat ?: return
        val active = activeNotification(ctx, tag, id)
        val ids = active?.extras?.getStringArrayList(EXTRA_IDS) ?: arrayListOf()
        // То же сообщение уже показано другим путём (сокет и пуш) — не повторяем.
        val nextIds = ChatHistory.append(ids, part.messageId) ?: return

        val tone = Tones.of("chat")
        val side = (64 * ctx.resources.displayMetrics.density).toInt()
        val wanted = buildMap<String, Art> {
            if (part.avatar.isNotEmpty()) put("avatar", Art(url = part.avatar))
            if (part.frame.isNotEmpty()) put("frame", Art(url = part.frame))
            if (part.image.isNotEmpty()) put("image", Art(url = part.image, auth = true))
        }
        val got = NotifArt.fetchAll(ctx, wanted, NotifCover.IMAGES_BUDGET_MS)
        val face = NotifArt.avatar(ctx, got["avatar"], got["frame"], part.frameHole, part.fromName, tone, side)
        val partner = Person.Builder()
            .setName(part.fromName)
            .setKey(part.fromUid.ifEmpty { "partner" })
            .setIcon(IconCompat.createWithBitmap(face))
            .setImportant(true)
            .build()
        val shortcut = pushShortcut(ctx, part, partner, face)

        val style = active?.let { NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(it) }
            ?: NotificationCompat.MessagingStyle(me(part))
        val ts = if (part.ts > 0) part.ts else System.currentTimeMillis()
        val photo = got["image"]?.let { saveForShade(ctx, it, part.messageId.ifEmpty { "m$ts" }) }
        if (photo != null) {
            style.addMessage(
                NotificationCompat.MessagingStyle.Message(cover.body.ifEmpty { " " }, ts, partner)
                    .setData("image/jpeg", photo),
            )
        } else {
            style.addMessage(NotificationCompat.MessagingStyle.Message(cover.body, ts, partner))
        }
        trim(style)
        post(ctx, cover, raw, style, ArrayList(nextIds), shortcut, face, tag, id, channel, silent = false)
    }

    /**
     * Свой ответ или объятие в переписку — после нажатия в шторке. Повторный
     * показ ещё и снимает крутилку отправки с поля ответа. [note] — строка
     * под ответом («отправлю, когда появится связь»).
     */
    fun appendMine(ctx: Context, tag: String, id: Int, text: String, note: String = "") {
        val active = activeNotification(ctx, tag, id) ?: return
        val raw = active.extras?.getString(EXTRA_COVER) ?: return
        val cover = CoverParser.parse(raw) ?: return
        val part = cover.chat ?: return
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(active)
            ?: NotificationCompat.MessagingStyle(me(part))
        val now = System.currentTimeMillis()
        style.addMessage(NotificationCompat.MessagingStyle.Message(text, now, null as Person?))
        if (note.isNotEmpty()) style.addMessage(NotificationCompat.MessagingStyle.Message(note, now + 1, null as Person?))
        trim(style)
        val ids = active.extras?.getStringArrayList(EXTRA_IDS) ?: arrayListOf()
        val channel = if (Build.VERSION.SDK_INT >= 26) active.channelId ?: NotifCover.CHANNEL_PARTNER else NotifCover.CHANNEL_PARTNER
        post(ctx, cover, raw, style, ids, shortcutId(part), null, tag, id, channel, silent = true)
    }

    private fun me(part: ChatPart) = Person.Builder().setName(part.you).setKey("me").build()

    private fun trim(style: NotificationCompat.MessagingStyle) {
        val messages = style.messages
        while (messages.size > ChatHistory.KEEP) messages.removeAt(0)
    }

    private fun post(
        ctx: Context,
        cover: Cover,
        raw: String,
        style: NotificationCompat.MessagingStyle,
        ids: ArrayList<String>,
        shortcut: String,
        face: Bitmap?,
        tag: String,
        id: Int,
        channel: String,
        silent: Boolean,
    ) {
        style.setGroupConversation(false)
        val extras = Bundle().apply {
            putStringArrayList(EXTRA_IDS, ids)
            putString(EXTRA_COVER, raw)
        }
        val builder = NotificationCompat.Builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(NotifCover.ACCENT)
            .setStyle(style)
            .setShortcutId(shortcut)
            .setLocusId(LocusIdCompat(shortcut))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(NotifCover.open(ctx, cover.link))
            .setAutoCancel(true)
            .setOnlyAlertOnce(silent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .addExtras(extras)
        if (face != null) builder.setLargeIcon(face)
        for (action in cover.actions) {
            chatAction(ctx, cover, raw, action, tag, id)?.let { builder.addAction(it) }
        }
        NotifCover.post(ctx, tag, id, builder)
    }

    private fun chatAction(ctx: Context, cover: Cover, raw: String, action: CoverAction, tag: String, id: Int): NotificationCompat.Action? {
        val part = cover.chat ?: return null
        return when (action.id) {
            "reply" -> {
                val choices = Array<CharSequence>(part.quick.size) { part.quick[it] }
                val input = RemoteInput.Builder(REPLY_KEY)
                    .setLabel(action.label)
                    .setChoices(choices)
                    .build()
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notif_reply, action.label,
                    NotifActionReceiver.pending(ctx, "reply", tag, id, mutable = true, raw = raw),
                )
                    .addRemoteInput(input)
                    .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                    .setShowsUserInterface(false)
                    .setAllowGeneratedReplies(false)
                    .build()
            }
            "hug" -> NotificationCompat.Action.Builder(
                R.drawable.ic_tg_heart, action.label,
                NotifActionReceiver.pending(ctx, "hug", tag, id, mutable = false, raw = raw),
            ).setShowsUserInterface(false).build()
            "read" -> NotificationCompat.Action.Builder(
                R.drawable.ic_tg_check, action.label,
                NotifActionReceiver.pending(ctx, "read", tag, id, mutable = false, raw = raw),
            )
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
                .setShowsUserInterface(false)
                .build()
            else -> if (!action.native) {
                NotificationCompat.Action.Builder(0, action.label, NotifCover.open(ctx, action.link)).build()
            } else null
        }
    }

    private fun shortcutId(part: ChatPart) = "pair_chat_" + part.groupId.ifEmpty { "pair" }

    /**
     * Ярлык разговора: без него Android 11+ не кладёт переписку в раздел
     * «Разговоры» и не ставит аватар вместо значка. Обновляем, только когда
     * сменились имя или лицо (обновления ярлыков система считает).
     */
    private fun pushShortcut(ctx: Context, part: ChatPart, partner: Person, face: Bitmap): String {
        val sid = shortcutId(part)
        val signature = "${part.fromName}|${part.avatar}|${part.frame}"
        val prefs = ctx.getSharedPreferences("notif_chat", Context.MODE_PRIVATE)
        if (prefs.getString("sig_$sid", null) == signature) return sid
        try {
            val intent = Intent(ctx, MainActivity::class.java)
                .setAction(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION)
                .setData(Uri.parse("loveapp://open/chat"))
            val info = ShortcutInfoCompat.Builder(ctx, sid)
                .setShortLabel(part.fromName.ifEmpty { "Togetherly" })
                .setLongLived(true)
                .setPerson(partner)
                .setIcon(IconCompat.createWithBitmap(face))
                .setLocusId(LocusIdCompat(sid))
                .setIntent(intent)
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(ctx, info)
            prefs.edit().putString("sig_$sid", signature).apply()
        } catch (e: Exception) {
            // Предел обновлений ярлыков или оболочка без них: переписка
            // покажется и без раздела «Разговоры».
            Log.i(TAG, "ярлык не обновился: ${e.message}")
        }
        return sid
    }

    /** Уведомление этой метки и номера, если оно ещё в шторке. */
    private fun activeNotification(ctx: Context, tag: String, id: Int): Notification? = try {
        ctx.getSystemService(NotificationManager::class.java)?.activeNotifications
            ?.firstOrNull { it.tag == tag && it.id == id }?.notification
    } catch (_: Exception) {
        null
    }

    /** Фото для шторки: файл в кэше и доступ на чтение самой шторке. */
    private fun saveForShade(ctx: Context, bitmap: Bitmap, name: String): Uri? = try {
        val dir = File(ctx.cacheDir, "notif").apply { mkdirs() }
        // Старше двух дней — убираем: шторку столько не держат.
        val old = System.currentTimeMillis() - 2 * 24 * 3600 * 1000L
        dir.listFiles()?.filter { it.lastModified() < old }?.forEach { it.delete() }
        val safe = name.filter { it.isLetterOrDigit() }.take(40).ifEmpty { "photo" }
        val file = File(dir, "$safe.jpg")
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + AUTHORITY_SUFFIX, file)
        ctx.grantUriPermission("com.android.systemui", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        uri
    } catch (e: Exception) {
        Log.i(TAG, "фото в шторку не легло: ${e.message}")
        null
    }
}
