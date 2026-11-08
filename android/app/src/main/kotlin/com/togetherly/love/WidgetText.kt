package com.togetherly.love

import android.content.Context

/**
 * Подписи виджетов на языке приложения.
 *
 * Нативная сторона живёт без Flutter и языка приложения не знает: подписи
 * были зашиты по-русски и оставались русскими у человека с английским
 * приложением (отзыв в App Store 19.08.2026). Приложение пишет строки в данные
 * виджетов ключами `wl_<ключ>` и код языка `wl_lang`
 * (`lib/services/widget_labels.dart`). Пока не записало — прежний русский
 * текст, он передаётся вторым аргументом.
 */
object WidgetText {

    private fun data(context: Context) =
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    /** Подпись [key] на языке приложения, без записи — [ru]. */
    fun get(context: Context, key: String, ru: String): String =
        data(context).getString("wl_$key", null)?.takeIf { it.isNotEmpty() } ?: ru

    /** Подпись с подстановками `{имя}`: `fmt(ctx, "matched", "совпало {n} из 7", "n" to "3")`. */
    fun fmt(context: Context, key: String, ru: String, vararg vars: Pair<String, Any>): String {
        var text = get(context, key, ru)
        for ((name, value) in vars) text = text.replace("{$name}", value.toString())
        return text
    }

    /** Список через запятую (месяцы, дни недели); без записи или не той длины — [ru]. */
    fun list(context: Context, key: String, ru: List<String>): List<String> {
        val parts = get(context, key, "").split(",").map { it.trim() }
        return if (parts.size == ru.size && parts.all { it.isNotEmpty() }) parts else ru
    }

    /**
     * Слово при числе [n]: `plural(ctx, "days", n, "день", "дня", "дней")`.
     * Формы приложение пишет тремя ключами `<key>_one/_few/_many`, а какую
     * взять, решают правила языка из `wl_lang`.
     */
    fun plural(context: Context, key: String, n: Int, one: String, few: String, many: String): String {
        val lang = data(context).getString("wl_lang", null).orEmpty()
        val form = pluralForm(lang, n)
        val ru = when (pluralForm("ru", n)) {
            "one" -> one
            "few" -> few
            else -> many
        }
        val stored = data(context).getString("wl_${key}_$form", null)?.takeIf { it.isNotEmpty() }
        return if (lang.isEmpty() || stored == null) ru else stored
    }

    /** Форма множественного числа: `one`, `few` или `many`. */
    fun pluralForm(lang: String, n: Int): String {
        val abs = kotlin.math.abs(n)
        return when (lang) {
            "", "ru", "uk" -> {
                val a = abs % 100
                val b = abs % 10
                when {
                    a in 11..19 -> "many"
                    b == 1 -> "one"
                    b in 2..4 -> "few"
                    else -> "many"
                }
            }
            "fr" -> if (abs <= 1) "one" else "many"
            "zh" -> "many"
            else -> if (abs == 1) "one" else "many"
        }
    }

    /** Та же строка с заглавной: подпись начинается с неё. */
    fun cap(s: String): String =
        if (s.isEmpty()) s else s.substring(0, 1).uppercase() + s.substring(1)
}
