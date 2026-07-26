package com.togetherly.love

import android.app.Activity
import android.content.Context
import android.graphics.PorterDuff
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import java.util.Calendar

/**
 * Окно правки заметки поверх рабочего стола.
 *
 * В самом виджете печатать нельзя: `EditText` в RemoteViews не поддерживается.
 * Поэтому тап по листику открывает эту активность — прозрачный фон, без
 * анимации, клавиатура сразу, курсор в конце текста. Визуально человек
 * продолжает писать на том же листике, приложение при этом не открывается.
 *
 * Сохранение идёт в два шага: сперва текст ложится в общие настройки и виджет
 * перерисовывается (отклик мгновенный, без ожидания сети), потом будится Dart
 * и отправляет заметку партнёру.
 */
class NoteEditorActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_note_editor)

        // Клавиатура появляется сама: окно открылось ради ввода, лишний тап тут
        // ни к чему.
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        )

        val group = intent.getStringExtra(EXTRA_GROUP).orEmpty()
        val initial = intent.getStringExtra(EXTRA_TEXT).orEmpty()

        val prefs = getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val theme = WidgetTheme.from(prefs)

        val card = findViewById<View>(R.id.card)
        val input = findViewById<EditText>(R.id.note_input)
        val title = findViewById<TextView>(R.id.head_title)
        val chip = findViewById<ImageView>(R.id.head_chip)
        val icon = findViewById<ImageView>(R.id.head_icon)
        val cancel = findViewById<Button>(R.id.cancel)
        val save = findViewById<Button>(R.id.save)

        // Цвета активной темы приложения — те же, что у виджета.
        card.paint(theme.surfaceContainer)
        chip.setColorFilter(theme.primaryContainer, PorterDuff.Mode.SRC_IN)
        icon.setColorFilter(theme.onPrimaryContainer, PorterDuff.Mode.SRC_IN)
        title.setTextColor(theme.onSurface)
        input.paint(theme.surface)
        input.setTextColor(theme.onSurface)
        input.setHintTextColor(theme.onSurfaceVariant)
        cancel.paint(theme.surfaceContainer)
        cancel.setTextColor(theme.onSurfaceVariant)
        save.paint(theme.primary)
        save.setTextColor(theme.onPrimary)

        input.setText(initial)
        input.setSelection(input.text.length)
        input.requestFocus()

        cancel.setOnClickListener { finish() }
        save.setOnClickListener { store(prefs, group, input.text.toString().trim()) }

        // Тап мимо карточки — закрыть, как у любого окна поверх.
        findViewById<View>(R.id.scrim).setOnClickListener { finish() }
        card.setOnClickListener { /* клик по самой карточке не закрывает */ }
    }

    /** Пишет заметку локально, обновляет листики и будит Dart для отправки. */
    private fun store(
        prefs: android.content.SharedPreferences,
        group: String,
        text: String,
    ) {
        val prefix = if (group.isEmpty()) "" else "note_${group}_"
        val now = Calendar.getInstance()
        val hh = now.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val mm = now.get(Calendar.MINUTE).toString().padStart(2, '0')
        val myName = prefs.getString("${prefix}my_name", null)
            ?: prefs.getString("note_my_name", null).orEmpty()

        prefs.edit()
            .putString("${prefix}text", text)
            .putString("${prefix}author", myName)
            .putString("${prefix}time", "$hh:$mm")
            // Отметка «ждёт сервера»: если фоновый Dart не поднялся или сессия
            // протухла, приложение дошлёт заметку при следующем запуске.
            .putString("${prefix}pending_send", "1")
            .apply()

        NoteWidgetProvider.refreshAll(this)

        try {
            val encoded = Uri.encode(text)
            HomeWidgetBackgroundIntent
                .getBroadcast(this, Uri.parse("loveapp://note?group=$group&text=$encoded"))
                .send()
        } catch (e: Exception) {
            android.util.Log.w("NoteEditor", "не удалось разбудить Dart: $e")
        }

        finish()
    }

    /** Перекрашивает фон-фигуру, не теряя её скругления. */
    private fun View.paint(color: Int) {
        val bg = background
        if (bg is GradientDrawable) {
            bg.mutate()
            (bg as GradientDrawable).setColor(color)
        } else {
            bg?.mutate()
            bg?.setColorFilter(color, PorterDuff.Mode.SRC_IN)
        }
    }

    companion object {
        const val EXTRA_GROUP = "group"
        const val EXTRA_TEXT = "text"
    }
}
