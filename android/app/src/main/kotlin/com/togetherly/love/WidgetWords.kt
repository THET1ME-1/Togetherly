package com.togetherly.love

import android.content.Context

/**
 * Слова при числе для подписей виджетов на языке приложения ([WidgetText]).
 *
 * Прежние виджеты держали по своей копии `daysWord` внутри провайдера;
 * «Кольцу года» и «Календарю лет» нужны ещё месяцы и порядковый номер года,
 * поэтому склонения собраны здесь. Русские формы — запасные, пока приложение
 * не записало подписи.
 */
object WidgetWords {

    /** день / дня / дней */
    fun days(context: Context, n: Int): String =
        WidgetText.plural(context, "days", n, "день", "дня", "дней")

    /** месяц / месяца / месяцев */
    fun months(context: Context, n: Int): String =
        WidgetText.plural(context, "months", n, "месяц", "месяца", "месяцев")

    /** воспоминание / воспоминания / воспоминаний */
    fun memories(context: Context, n: Int): String =
        WidgetText.plural(context, "memories", n, "воспоминание", "воспоминания", "воспоминаний")

    /** года / лет — после «до»: «до 6 лет» */
    fun yearsGenitive(context: Context, n: Int): String =
        WidgetText.plural(context, "yearsgen", n, "года", "лет", "лет")

    /** год / года / лет — «6 лет вместе» */
    fun years(context: Context, n: Int): String =
        WidgetText.plural(context, "years", n, "год", "года", "лет")

    /** час / часа / часов */
    fun hours(context: Context, n: Int): String =
        WidgetText.plural(context, "hours", n, "час", "часа", "часов")

    /** минута / минуты / минут */
    fun minutes(context: Context, n: Int): String =
        WidgetText.plural(context, "minutes", n, "минута", "минуты", "минут")

    /**
     * Порядковый номер года прописью: «ШЕСТОЙ ГОД ВМЕСТЕ» из хендофа.
     * Дальше десятого пара доходит редко, и там подпись становится числовой.
     */
    fun yearOrdinal(context: Context, n: Int): String {
        val words = WidgetText.list(
            context, "year_ordinals",
            listOf(
                "ПЕРВЫЙ", "ВТОРОЙ", "ТРЕТИЙ", "ЧЕТВЁРТЫЙ", "ПЯТЫЙ",
                "ШЕСТОЙ", "СЕДЬМОЙ", "ВОСЬМОЙ", "ДЕВЯТЫЙ", "ДЕСЯТЫЙ",
            ),
        )
        val word = words.getOrNull(n - 1) ?: WidgetText.fmt(context, "year_nth", "{n}-Й", "n" to n)
        return WidgetText.fmt(context, "year_together", "{w} ГОД ВМЕСТЕ", "w" to word)
    }

    /** Та же строка с заглавной: подпись начинается с неё, а не продолжает фразу. */
    fun cap(s: String): String = WidgetText.cap(s)
}
