package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Виджет «Где мы» (19.09.2026): карта на двоих, дуга между людьми и
 * расстояние прямо на ней. Три размера — 2×2, 4×2 и 4×4.
 *
 * Живую карту RemoteViews показать не может, поэтому картинку целиком рисует
 * приложение (`lib/services/map/pair_map_widget_service.dart`): подложку в
 * цветах темы или глобус, шарики с аватарками, подписи. Здесь её только
 * показывают. Путь лежит под ключом `map_<пара>_img_<s|m|l>`.
 *
 * Размер ячейки у лончеров разный вдвое, а картинка рисуется под пропорции:
 * провайдер записывает свою ячейку в `mapw_dims_<размер>` и, если она
 * поменялась, будит Dart перерисовать — иначе крайних людей срезало бы.
 * Нажатие открывает карту в приложении.
 */
open class PairMapWidgetProvider : HomeWidgetProvider() {

    /** Размер виджета: s, m или l — совпадает с `MapWidgetSize` в Dart. */
    protected open val sizeId: String = "m"

    /** Картинка до первой отрисовки — та же, что в списке виджетов лончера. */
    protected open val placeholder: Int = R.drawable.tg_preview_map_4x2

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        render(context, appWidgetManager, appWidgetId, data)
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetGroupHelper.clearBindings(context, "map", appWidgetIds)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val g = WidgetGroupHelper.getOrBind(context, "map", widgetId)
        val path = data.getString("map_${g}_img_$sizeId", null)
            ?: data.getString("map_${data.getString("map_latest_group", "")}_img_$sizeId", null)

        val views = RemoteViews(context.packageName, R.layout.tg_map).apply {
            setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("loveapp://map"),
                ),
            )
            val bitmap = decode(path)
            if (bitmap != null) {
                setImageViewBitmap(R.id.map_image, bitmap)
            } else {
                setImageViewResource(R.id.map_image, placeholder)
            }
        }
        manager.updateAppWidget(widgetId, views)

        val changed = rememberDims(data, manager.getAppWidgetOptions(widgetId))
        // Картинки ещё нет (виджет только что поставили) или ячейка другой
        // пропорции — просим Dart перерисовать под неё.
        if (changed || path == null || !File(path).exists()) wakeDart(context)
    }

    /**
     * Записывает ячейку в dp для Dart. Возвращает true, если она поменялась
     * заметно: на пару dp лончеры дёргают размер при каждом показе.
     */
    private fun rememberDims(data: SharedPreferences, options: Bundle?): Boolean {
        val w = WidgetSizing.widthDp(options)
        val h = WidgetSizing.heightDp(options)
        if (w <= 0 || h <= 0) return false
        val key = "mapw_dims_$sizeId"
        val prev = data.getString(key, null)?.split(",")?.mapNotNull { it.toIntOrNull() }
        if (prev != null && prev.size == 2 &&
            Math.abs(prev[0] - w) < 12 && Math.abs(prev[1] - h) < 12
        ) {
            return false
        }
        data.edit().putString(key, "$w,$h").apply()
        return true
    }

    private fun wakeDart(context: Context) {
        try {
            HomeWidgetBackgroundIntent
                .getBroadcast(context, Uri.parse("loveapp://mapwidget"))
                .send()
        } catch (e: Exception) {
            Log.w(TAG, "не разбудили Dart: ${e.message}")
        }
    }

    /**
     * Картинка в RGB_565: вдвое легче, а прозрачность ей не нужна — углы
     * скругляет подложка. Картинку Dart рисует в пределах бюджета памяти, но
     * на всякий случай ужимаем то, что вдруг пришло больше.
     */
    private fun decode(path: String?): Bitmap? {
        if (path.isNullOrEmpty() || !File(path).exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / sample * (bounds.outHeight / sample) * 2 > MAX_BYTES) sample *= 2
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
                inPreferredConfig = Bitmap.Config.RGB_565
                inSampleSize = sample
            })
        } catch (e: Exception) {
            Log.w(TAG, "картинка не прочиталась: ${e.message}")
            null
        }
    }

    companion object {
        private const val TAG = "PairMapWidget"

        /** Столько же, сколько `kMapWidgetImageBudget` в Dart. */
        private const val MAX_BYTES = 950_000
    }
}

class PairMapWidget2x2Provider : PairMapWidgetProvider() {
    override val sizeId = "s"
    override val placeholder = R.drawable.tg_preview_map_2x2
}

class PairMapWidget4x2Provider : PairMapWidgetProvider() {
    override val sizeId = "m"
    override val placeholder = R.drawable.tg_preview_map_4x2
}

class PairMapWidget4x4Provider : PairMapWidgetProvider() {
    override val sizeId = "l"
    override val placeholder = R.drawable.tg_preview_map_4x4
}
