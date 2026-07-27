package com.togetherly.love

/**
 * Русские склонения для подписей виджетов.
 *
 * Нативная сторона живёт без Flutter, поэтому до `locale_service` ей не
 * дотянуться, а число в подписи меняется каждый день. Прежние виджеты держали
 * по своей копии `daysWord` внутри провайдера; «Кольцу года» и «Календарю
 * лет» нужны ещё месяцы и порядковый номер года, поэтому склонения собраны
 * здесь.
 */
object WidgetWords {

    /** день / дня / дней */
    fun days(n: Int): String = plural(n, "день", "дня", "дней")

    /** месяц / месяца / месяцев */
    fun months(n: Int): String = plural(n, "месяц", "месяца", "месяцев")

    /** год / года / лет — родительный падеж после числа: «до 6 лет» */
    fun yearsGenitive(n: Int): String = plural(n, "года", "лет", "лет")

    /** год / года / лет — именительный: «6 лет вместе» */
    fun years(n: Int): String = plural(n, "год", "года", "лет")

    /**
     * Порядковый номер года прописью: «ШЕСТОЙ ГОД ВМЕСТЕ» из хендофа.
     * Дальше десятого пара доходит редко, и там подпись становится числовой.
     */
    fun yearOrdinal(n: Int): String {
        val words = listOf(
            "ПЕРВЫЙ", "ВТОРОЙ", "ТРЕТИЙ", "ЧЕТВЁРТЫЙ", "ПЯТЫЙ",
            "ШЕСТОЙ", "СЕДЬМОЙ", "ВОСЬМОЙ", "ДЕВЯТЫЙ", "ДЕСЯТЫЙ",
        )
        val word = words.getOrNull(n - 1) ?: "$n-Й"
        return "$word ГОД ВМЕСТЕ"
    }

    /** Та же строка с заглавной: подпись начинается с неё, а не продолжает фразу. */
    fun cap(s: String): String =
        if (s.isEmpty()) s else s.substring(0, 1).uppercase() + s.substring(1)

    private fun plural(n: Int, one: String, few: String, many: String): String {
        val a = n % 100
        val b = n % 10
        return when {
            a in 11..19 -> many
            b == 1 -> one
            b in 2..4 -> few
            else -> many
        }
    }
}
