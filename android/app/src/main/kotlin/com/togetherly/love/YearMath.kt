package com.togetherly.love

import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Разметка совместного времени для «Кольца года» и «Календаря лет».
 *
 * Зеркало `YearProgress` из Dart (`lib/models/year_progress.dart`), и считать
 * это дважды приходится не от хорошей жизни: если бы виджет брал готовые числа
 * из `HomeWidgetPreferences`, счётчик застывал бы до следующего открытия
 * приложения — сутки меняются, а данные лежат прежние. Тот же приём уже
 * применяет «лепестковый таймер»: Flutter кладёт `start_ms`, дни считает
 * нативная сторона по системному времени.
 *
 * Границы лет и месяцев календарные: пара празднует годовщину в свою дату, а
 * не через фиксированные 365 суток.
 */
data class YearMath(
    val daysTotal: Int,
    val yearsCompleted: Int,
    val monthsCompleted: Int,
    val daysIntoYear: Int,
    val daysToNextAnniversary: Int,
    val nextAnniversaryDay: Int,
    val nextAnniversaryMonth: Int,
) {
    /** Доля текущего года, 0…1. Знаменатель 365 — как в хендофе и в Dart. */
    val ringProgress: Float get() = (daysIntoYear % 365) / 365f

    companion object {

        /** Расчёт от даты начала [startMs] на момент [nowMs]. */
        fun from(startMs: Long, nowMs: Long = System.currentTimeMillis()): YearMath {
            val from = midnight(startMs)
            val to = midnight(nowMs)

            val daysTotal = daysBetween(from, to)

            var years = to.get(Calendar.YEAR) - from.get(Calendar.YEAR)
            if (sameDateIn(from, to.get(Calendar.YEAR)).after(to)) years -= 1
            if (years < 0) years = 0

            val last = sameDateIn(from, from.get(Calendar.YEAR) + years)
            val next = sameDateIn(from, from.get(Calendar.YEAR) + years + 1)

            // Полные календарные месяцы. День короче исходного (31 января →
            // 28 февраля) месяц не засчитывает: точка загорится 1 марта.
            var months = (to.get(Calendar.YEAR) - from.get(Calendar.YEAR)) * 12 +
                (to.get(Calendar.MONTH) - from.get(Calendar.MONTH))
            if (to.get(Calendar.DAY_OF_MONTH) < from.get(Calendar.DAY_OF_MONTH)) {
                months -= 1
            }

            return YearMath(
                daysTotal = daysTotal.coerceAtLeast(0),
                yearsCompleted = years,
                monthsCompleted = months.coerceAtLeast(0),
                daysIntoYear = daysBetween(last, to).coerceAtLeast(0),
                daysToNextAnniversary = daysBetween(to, next).coerceAtLeast(0),
                nextAnniversaryDay = next.get(Calendar.DAY_OF_MONTH),
                nextAnniversaryMonth = next.get(Calendar.MONTH) + 1,
            )
        }

        /** День и месяц прописью: «30 сентября». */
        fun dayMonth(day: Int, month: Int): String {
            val months = listOf(
                "января", "февраля", "марта", "апреля", "мая", "июня",
                "июля", "августа", "сентября", "октября", "ноября", "декабря",
            )
            val name = months.getOrNull(month - 1) ?: return ""
            return "$day $name"
        }

        private fun midnight(ms: Long): Calendar = Calendar.getInstance().apply {
            timeInMillis = ms
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        /**
         * Та же дата в другом году. 29 февраля в невисокосном году Calendar
         * переносит на 1 марта сам — пара отмечает годовщину в первый
         * существующий день.
         */
        private fun sameDateIn(source: Calendar, year: Int): Calendar =
            (source.clone() as Calendar).apply { set(Calendar.YEAR, year) }

        /**
         * Целых суток между полуночами. Через миллисекунды с округлением:
         * перевод часов на летнее время делает сутки короче или длиннее, и
         * деление нацело давало бы то на день меньше, то на день больше.
         */
        private fun daysBetween(from: Calendar, to: Calendar): Int {
            val diff = to.timeInMillis - from.timeInMillis
            return Math.round(diff.toDouble() / TimeUnit.DAYS.toMillis(1)).toInt()
        }
    }
}
