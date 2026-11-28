package com.togetherly.love.notif

import java.security.SecureRandom

/**
 * Правила переписки в шторке, без Android.
 *
 * Одно и то же сообщение доходит двумя путями: сокетом (уведомление ставит
 * Dart) и пушем FCM (сервер не видит человека на связи: присутствие пишется
 * раз в 5 минут). Оба ложатся в одно уведомление, и второй приход не должен
 * повторить строку.
 */
object ChatHistory {
    /** Сколько строк держать в шторке: дальше переписку читают в приложении. */
    const val KEEP = 8

    /**
     * Номера строк после прихода [id]; null — такое уже показано.
     * Пустой номер (старый пуш, свой ответ) — строка добавляется всегда.
     */
    fun append(existing: List<String>, id: String): List<String>? {
        if (id.isNotEmpty() && id in existing) return null
        return (existing + id).takeLast(KEEP)
    }
}

/** Номер записи как у PocketBase: 15 знаков `a-z0-9`. */
object PbId {
    private const val ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
    private val random = SecureRandom()

    fun next(): String {
        val sb = StringBuilder(15)
        repeat(15) { sb.append(ALPHABET[random.nextInt(ALPHABET.length)]) }
        return sb.toString()
    }

    fun valid(id: String): Boolean = id.length == 15 && id.all { it in ALPHABET }
}
