package com.togetherly.love

import android.content.SharedPreferences
import android.graphics.Color

/**
 * Палитра виджета, снятая с активной темы приложения.
 *
 * Цвета кладёт Flutter (`WidgetThemeSync`) строками вида `#RRGGBB`. Пока их
 * нет — например, виджет поставили до первого запуска — берутся значения из
 * хендофа, поэтому виджет никогда не окажется бесцветным.
 *
 * Полупрозрачных ролей здесь нет намеренно: RemoteViews не смешивает слои
 * поверх произвольной подложки, поэтому подписи и треки приходят уже
 * смешанными с фоном.
 */
data class WidgetTheme(
    val primary: Int,
    val primaryContainer: Int,
    val surface: Int,
    val surfaceContainer: Int,
    val tertiary: Int,
    val tertiaryContainer: Int,
    val secondaryContainer: Int,
    val onPrimary: Int,
    val onPrimarySoft: Int,
    val onPrimaryContainer: Int,
    val onContainerSoft: Int,
    val onSurface: Int,
    val onSurfaceVariant: Int,
    val onTertiary: Int,
    val onTertiaryContainer: Int,
    val outline: Int,
    val accentOnPrimary: Int,
    val trackOnContainer: Int,
    val trackOnSurface: Int,
    val blockOnPrimary: Int,
    val avatarMine: Int,
    val avatarPartner: Int,
) {
    companion object {
        private const val PREFIX = "wtheme_"

        /** Цвета из хендофа — запасной вариант, пока тема не доехала. */
        private val FALLBACK = mapOf(
            "primary" to "#6750A4",
            "primaryContainer" to "#EADDFF",
            "surface" to "#FEF7FF",
            "surfaceContainer" to "#F3EDF7",
            "tertiary" to "#7D5260",
            "tertiaryContainer" to "#FFD8E4",
            "secondaryContainer" to "#E8DEF8",
            "onPrimary" to "#FFFFFF",
            "onPrimarySoft" to "#E9DDFF",
            "onPrimaryContainer" to "#21005D",
            "onContainerSoft" to "#4F378B",
            "onSurface" to "#1D1B20",
            "onSurfaceVariant" to "#49454F",
            "onTertiary" to "#FFFFFF",
            "onTertiaryContainer" to "#31111D",
            "outline" to "#7A757F",
            "accentOnPrimary" to "#D0BCFF",
            "trackOnContainer" to "#D6C6F0",
            "trackOnSurface" to "#E8DEF8",
            "blockOnPrimary" to "#7965B0",
            "avatarMine" to "#D0BCFF",
            "avatarPartner" to "#FFD8E4",
        )

        private fun read(prefs: SharedPreferences, role: String): Int {
            val raw = prefs.getString("$PREFIX$role", null)
                ?.takeIf { it.isNotBlank() }
                ?: FALLBACK[role]
                ?: "#6750A4"
            return try {
                Color.parseColor(raw)
            } catch (e: IllegalArgumentException) {
                Color.parseColor(FALLBACK[role] ?: "#6750A4")
            }
        }

        fun from(prefs: SharedPreferences): WidgetTheme = WidgetTheme(
            primary = read(prefs, "primary"),
            primaryContainer = read(prefs, "primaryContainer"),
            surface = read(prefs, "surface"),
            surfaceContainer = read(prefs, "surfaceContainer"),
            tertiary = read(prefs, "tertiary"),
            tertiaryContainer = read(prefs, "tertiaryContainer"),
            secondaryContainer = read(prefs, "secondaryContainer"),
            onPrimary = read(prefs, "onPrimary"),
            onPrimarySoft = read(prefs, "onPrimarySoft"),
            onPrimaryContainer = read(prefs, "onPrimaryContainer"),
            onContainerSoft = read(prefs, "onContainerSoft"),
            onSurface = read(prefs, "onSurface"),
            onSurfaceVariant = read(prefs, "onSurfaceVariant"),
            onTertiary = read(prefs, "onTertiary"),
            onTertiaryContainer = read(prefs, "onTertiaryContainer"),
            outline = read(prefs, "outline"),
            accentOnPrimary = read(prefs, "accentOnPrimary"),
            trackOnContainer = read(prefs, "trackOnContainer"),
            trackOnSurface = read(prefs, "trackOnSurface"),
            blockOnPrimary = read(prefs, "blockOnPrimary"),
            avatarMine = read(prefs, "avatarMine"),
            avatarPartner = read(prefs, "avatarPartner"),
        )
    }
}
