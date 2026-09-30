package com.togetherly.love

import android.content.Context
import android.content.SharedPreferences

/**
 * Подсказка вместо пустой половины парного виджета.
 *
 * Раньше половина без фото была просто закрашена цветом, и человек не мог
 * понять, что случилось: фото не дошло, его никто не ставил или партнёр ещё
 * ничего не добавил. Жалобы «виджет пустой» — самая большая группа в
 * приёмной. Теперь каждый из трёх случаев подписан, а нажатие, как и раньше,
 * открывает «Виджеты» в приложении. Макет — вариант Б
 * (https://claude.ai/artifact/48RQNpqSdabA61pLew7qTS).
 */
enum class PairWidgetHint(
    val iconRes: Int,
    private val key: String,
    private val titleRes: Int,
    private val subRes: Int,
) {
    NONE(0, "", 0, 0),

    /** Путь к фото записан, а картинка не открылась: файла нет или он битый. */
    PHOTO_FAILED(
        R.drawable.ic_widget_hint_refresh, "fail",
        R.string.love_hint_fail_title, R.string.love_hint_fail_sub,
    ),

    /** Своя половина пуста: ни фото, ни настроения, ни статуса. */
    OWN_EMPTY(
        R.drawable.ic_widget_hint_add_photo, "own",
        R.string.love_hint_own_title, R.string.love_hint_own_sub,
    ),

    /** Половина партнёра пуста. */
    PARTNER_EMPTY(
        R.drawable.ic_widget_hint_heart, "partner",
        R.string.love_hint_partner_title, R.string.love_hint_partner_sub,
    );

    /**
     * Подписи на языке приложения: их пишет Flutter (`love_hint_<случай>_title`
     * и `_sub`), язык знает только он. Пока не записал — русские из ресурсов.
     */
    fun title(context: Context, data: SharedPreferences): String =
        data.getString("love_hint_${key}_title", null)
            ?.takeIf { it.isNotEmpty() } ?: context.getString(titleRes)

    fun sub(context: Context, data: SharedPreferences): String =
        data.getString("love_hint_${key}_sub", null)
            ?.takeIf { it.isNotEmpty() } ?: context.getString(subRes)

    companion object {
        /**
         * Что показать на половине.
         *
         * Не дошедшее фото важнее всего остального: человек его ставил и ждёт
         * увидеть, поэтому подсказка стоит даже поверх настроения.
         */
        fun decide(
            mine: Boolean,
            photoPath: String?,
            photoShown: Boolean,
            hasMood: Boolean,
            hasText: Boolean,
        ): PairWidgetHint = when {
            !photoPath.isNullOrEmpty() && !photoShown -> PHOTO_FAILED
            photoShown || hasMood || hasText -> NONE
            mine -> OWN_EMPTY
            else -> PARTNER_EMPTY
        }
    }
}
