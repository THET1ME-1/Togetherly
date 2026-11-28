package com.togetherly.love.notif

/**
 * Цвета обложки по виду события — из макета «А»
 * (https://claude.ai/artifact/KZx6vHgr6LvacepEysXiGM).
 *
 * [tint] — плашка под картинкой и вторая кнопка, [label] — подпись сверху и
 * текст второй кнопки, [deep] — первая кнопка (текст на ней белый),
 * [labelNight] — подпись сверху на тёмной шторке: тёмный [label] там не
 * читается.
 */
data class Tone(val tint: Int, val label: Int, val deep: Int, val labelNight: Int)

object Tones {
    private fun c(hex: Long) = (0xFF000000 or hex).toInt()

    private val all = mapOf(
        "miss" to Tone(c(0xFFE1DC), c(0x8C2F27), c(0xB8433A), c(0xFFB4A9)),
        "mood" to Tone(c(0xFFEDE4), c(0x9A4458), c(0xB4506A), c(0xFFB1C3)),
        "chat" to Tone(c(0xE8E6FB), c(0x3F3794), c(0x4F46A8), c(0xC4BFFF)),
        "memory" to Tone(c(0xCFE3DB), c(0x245446), c(0x2E6B5A), c(0x9DD3BF)),
        "gift" to Tone(c(0xEFE6FA), c(0x5A3C90), c(0x6C4BA6), c(0xD2BCFF)),
        "evening" to Tone(c(0xE6E4F7), c(0x2D2A60), c(0x33306B), c(0xC3C0F5)),
        "chest" to Tone(c(0xFBEBD3), c(0x714812), c(0x8A5A1F), c(0xF2C27E)),
        "plus" to Tone(c(0xFBEBD3), c(0x714812), c(0x8A5A1F), c(0xF2C27E)),
        "date" to Tone(c(0xFFE6EC), c(0x8A3550), c(0xA8405F), c(0xFFB0C6)),
        "draw" to Tone(c(0xE2F0FB), c(0x24557A), c(0x2D6690), c(0xA6CDF0)),
        "snow" to Tone(c(0xE2F0FB), c(0x24557A), c(0x2D6690), c(0xA6CDF0)),
        "app" to Tone(c(0xF3E9EB), c(0x6B5B5C), c(0x8C2F27), c(0xD9C2C4)),
    )

    /** Тон по имени; незнакомый — нейтральный тон приложения. */
    fun of(name: String): Tone = all[name] ?: all.getValue("app")

    /** Есть ли такой тон: сторож, что сервер и телефон говорят одними именами. */
    fun known(name: String): Boolean = name in all

    /** Первая буква имени для кружка без аватара; пусто — сердце не рисуем, «?». */
    fun monogram(name: String): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "?"
        // Первый символ целиком, даже если это суррогатная пара (эмодзи, CJK).
        val cp = trimmed.codePointAt(0)
        return String(Character.toChars(cp)).uppercase()
    }
}
