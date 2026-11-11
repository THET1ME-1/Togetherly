package com.togetherly.love

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.TextPaint
import android.text.TextUtils
import android.widget.RemoteViews
import androidx.core.content.res.ResourcesCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Виджет «Чем заняты»: две комнатки, в каждой Ту показывает, чем человек
 * сейчас занят. Слева я, справа партнёр.
 *
 * Картинка рисуется целиком здесь, на холсте, под настоящий размер виджета:
 * стена в горошек, мягкий пол, кадр занятия, внизу плашка «аватарка + время»
 * и рядом плашка с названием занятия, на стыке половин сердце. Раскладкой из
 * View этого не собрать: пол обрезается скруглённым углом половины, а у
 * RemoteViews такой обрезки нет.
 *
 * Данные кладёт `DoingService` (Dart): `doing_<пара>_my_*` и `partner_*`,
 * справочник кадров `doing_art_<id>` и подписей `doing_name_<id>`. Виджет
 * неподвижен: двигаться рабочий стол не даёт. Занятие старше трёх часов
 * гаснет здесь же, без приложения: Ту возвращается в покой.
 */
class DoingWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
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
        WidgetGroupHelper.clearBindings(context, "doing", appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    private fun render(context: Context, manager: AppWidgetManager, widgetId: Int, data: SharedPreferences) {
        val group = WidgetGroupHelper.getOrBind(context, "doing", widgetId)
        val theme = WidgetTheme.from(data)
        val now = System.currentTimeMillis()
        val dark = data.getString("wtheme_dark", null) == "1"

        val my = Half.read(data, group, "my", theme.primaryContainer, theme.avatarMine, now)
        val partner = Half.read(data, group, "partner", theme.tertiaryContainer, theme.avatarPartner, now)

        // Размер холста — настоящий размер виджета, но не больше 960 точек по
        // ширине: картинка едет через Binder, а он держит немного. Пару берёт
        // cellDp: в книжной ориентации высота — MAX_HEIGHT. С MIN_HEIGHT холст
        // выходил ниже виджета, и fitXY вытягивал его (на эмуляторе 11.11.2026
        // аватарки стали овалами, буквы узкими).
        val options = manager.getAppWidgetOptions(widgetId)
        val density = context.resources.displayMetrics.density
        val (cellWidth, cellHeight) = WidgetSizing.cellDp(context, options)
        val widthDp = cellWidth.takeIf { it > 0 } ?: 338
        val heightDp = cellHeight.takeIf { it > 0 } ?: 158
        val scale = minOf(density, 960f / widthDp)
        val width = (widthDp * scale).toInt().coerceAtLeast(200)
        val height = (heightDp * scale).toInt().coerceAtLeast(90)

        val picture = try {
            Painter(context, width, height, dark).draw(my, partner)
        } catch (e: Throwable) {
            null
        }

        val views = RemoteViews(context.packageName, R.layout.tg_doing_4x2).apply {
            if (picture != null) setImageViewBitmap(R.id.doing_image, picture)
            // Своя половина открывает выбор занятия, половина партнёра — приложение.
            setOnClickPendingIntent(
                R.id.doing_tap_me,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("loveapp://doing")),
            )
            setOnClickPendingIntent(
                R.id.doing_tap_partner,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("loveapp://home")),
            )
        }
        manager.updateAppWidget(widgetId, views)
    }

    /** Одна половина: что показывать прямо сейчас. */
    private class Half(
        val wall: Int,
        val floor: Int,
        val artPath: String,
        val label: String,
        val time: String,
        val avatarPath: String,
        val avatarColor: Int,
    ) {
        companion object {
            fun read(
                data: SharedPreferences,
                group: String,
                side: String,
                themeWall: Int,
                avatarColor: Int,
                now: Long,
            ): Half {
                val prefix = "doing_${group}_${side}"
                val id = data.getString("${prefix}_id", null).orEmpty()
                val text = data.getString("${prefix}_text", null).orEmpty()
                val at = data.getString("${prefix}_at", null)?.toLongOrNull() ?: 0L
                val avatar = data.getString("${prefix}_avatar", null).orEmpty()
                val wall = parseColor(data.getString("${prefix}_wall", null)) ?: themeWall

                // Занятие старше трёх часов гаснет: Ту в покое, плашек нет.
                val alive = id.isNotEmpty() && now - at < FADES_MS
                val label = when {
                    !alive -> ""
                    id == "own" -> text
                    else -> data.getString("doing_name_$id", null).orEmpty()
                }
                val art = (if (alive && id != "own") data.getString("doing_art_$id", null) else null)
                    ?.takeIf { it.isNotEmpty() }
                    ?: data.getString("doing_art_idle", null).orEmpty()
                val time = if (alive && at > 0) SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(at)) else ""
                return Half(wall, roomFloor(wall), art, label, time, avatar, avatarColor)
            }
        }
    }

    /** Рисует весь виджет. Единица `u` — сотая доля ширины, как в макете. */
    private class Painter(val context: Context, val width: Int, val height: Int, dark: Boolean) {
        private val u = width / 100f
        private val paper = if (dark) 0xFFFFF1F3.toInt() else 0xFFFFFDFC.toInt()
        private val pen = 0xFF4B2A31.toInt()
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 0.35f * u
            color = Color.argb(31, Color.red(pen), Color.green(pen), Color.blue(pen))
        }
        private val bold: Typeface = try {
            ResourcesCompat.getFont(context, R.font.onest_bold) ?: Typeface.DEFAULT_BOLD
        } catch (e: Exception) {
            Typeface.DEFAULT_BOLD
        }

        fun draw(my: Half, partner: Half): Bitmap {
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val gap = 1.1f * u
            val half = (width - gap) / 2f
            val outer = 7.7f * u
            val inner = 2.6f * u

            // Подложка под стыком: бумажная полоска между комнатками.
            fill.color = paper
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), outer, outer, fill)

            room(canvas, my, 0f, half, floatArrayOf(outer, outer, inner, inner, inner, inner, outer, outer), mine = true)
            room(canvas, partner, half + gap, half, floatArrayOf(inner, inner, outer, outer, outer, outer, inner, inner), mine = false)
            heart(canvas)
            return bitmap
        }

        private fun room(canvas: Canvas, side: Half, left: Float, w: Float, radii: FloatArray, mine: Boolean) {
            val h = height.toFloat()
            canvas.save()
            canvas.clipPath(Path().apply { addRoundRect(RectF(left, 0f, left + w, h), radii, Path.Direction.CW) })

            // Стена, горошек и пол.
            canvas.drawColor(side.wall)
            fill.color = side.floor
            val step = 6.2f * u
            var y = 2f * u + step / 2
            while (y < h) {
                var x = left + 1.4f * u + step / 2
                while (x < left + w) {
                    canvas.drawCircle(x, y, 0.85f * u, fill)
                    x += step
                }
                y += step
            }
            canvas.drawOval(RectF(left - 0.14f * w, h - 11.5f * u, left + w * 1.14f, h + 10.5f * u), fill)

            // Нижняя строка: плашка «аватарка + время» во внешнем углу, рядом занятие.
            val rowHeight = 8f * u
            val rowBottom = h - 2.2f * u
            val rowTop = rowBottom - rowHeight

            // Кадр занятия стоит над нижней строкой и чуть заходит на неё, как
            // в макете. На низком виджете (338×158) он упирается в верх, на
            // высоком (Pixel даёт 4×2 около 360×224) растёт до 44u и садится
            // на пол, а не висит под потолком с пустотой снизу.
            val sceneSide = minOf(44f * u, rowTop + 0.9f * u).coerceAtLeast(10f)
            val sceneTop = maxOf(0.4f * u, rowTop + 1.3f * u - sceneSide)
            WidgetImages.fitted(side.artPath, sceneSide.toInt())?.let { art ->
                val x = left + (w - sceneSide) / 2f
                canvas.drawBitmap(art, null, RectF(x, sceneTop, x + sceneSide, sceneTop + sceneSide), Paint(Paint.FILTER_BITMAP_FLAG))
            }

            val text = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = bold; color = pen; textSize = 3f * u }
            val pad = 0.7f * u
            val avatarSide = rowHeight - 2 * pad
            val timeWidth = if (side.time.isEmpty()) 0f else text.measureText(side.time) + u + 2f * u - pad
            val whoWidth = pad + avatarSide + pad + timeWidth
            val edge = 1.6f * u
            val whoLeft = if (mine) left + edge else left + w - edge - whoWidth
            chip(canvas, whoLeft, rowTop, whoWidth, rowHeight)

            val avatarLeft = if (mine) whoLeft + pad else whoLeft + whoWidth - pad - avatarSide
            avatar(canvas, side, avatarLeft, rowTop + pad, avatarSide)
            if (side.time.isNotEmpty()) {
                val timeLeft = if (mine) avatarLeft + avatarSide + u else whoLeft + 2f * u
                canvas.drawText(side.time, timeLeft, baseline(rowTop, rowHeight, text), text)
            }

            if (side.label.isNotEmpty()) {
                text.textSize = 3.05f * u
                val between = 0.9f * u
                val room = w - 2 * edge - whoWidth - between
                val inside = 2.1f * u
                val shown = TextUtils.ellipsize(side.label, text, room - 2 * inside, TextUtils.TruncateAt.END).toString()
                val actWidth = text.measureText(shown) + 2 * inside
                val actLeft = if (mine) whoLeft + whoWidth + between else whoLeft - between - actWidth
                chip(canvas, actLeft, rowTop, actWidth, rowHeight)
                canvas.drawText(shown, actLeft + inside, baseline(rowTop, rowHeight, text), text)
            }
            canvas.restore()
        }

        private fun baseline(top: Float, h: Float, paint: Paint): Float =
            top + h / 2f - (paint.descent() + paint.ascent()) / 2f

        /** Бумажная плашка с тонким контуром: без него на белой стене её не видно. */
        private fun chip(canvas: Canvas, left: Float, top: Float, w: Float, h: Float) {
            val rect = RectF(left, top, left + w, top + h)
            fill.color = paper
            canvas.drawRoundRect(rect, h / 2f, h / 2f, fill)
            canvas.drawRoundRect(rect, h / 2f, h / 2f, ring)
        }

        private fun avatar(canvas: Canvas, side: Half, left: Float, top: Float, d: Float) {
            val photo = WidgetImages.circularFromFile(side.avatarPath, d.toInt().coerceAtLeast(24))
            if (photo != null) {
                canvas.drawBitmap(photo, null, RectF(left, top, left + d, top + d), Paint(Paint.FILTER_BITMAP_FLAG))
                return
            }
            // Фото в профиле нет: кружок с силуэтом.
            fill.color = side.avatarColor
            canvas.drawCircle(left + d / 2f, top + d / 2f, d / 2f, fill)
            canvas.save()
            canvas.clipPath(Path().apply { addCircle(left + d / 2f, top + d / 2f, d / 2f, Path.Direction.CW) })
            fill.color = paper
            canvas.drawCircle(left + d / 2f, top + d * 0.39f, d * 0.18f, fill)
            canvas.drawOval(RectF(left + d * 0.14f, top + d * 0.65f, left + d * 0.86f, top + d * 1.35f), fill)
            canvas.restore()
        }

        /** Сердце на стыке половин: бумажный кружок и сердечко. */
        private fun heart(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val r = 4.8f * u
            fill.color = paper
            canvas.drawCircle(cx, cy, r, fill)
            canvas.drawCircle(cx, cy, r, ring)

            // Контур сердца на сетке 24×24, как значок в макете.
            val s = 5.2f * u / 24f
            val ox = cx - 12f * s
            val oy = cy - 12.6f * s
            val path = Path().apply {
                moveTo(ox + 12f * s, oy + 21f * s)
                cubicTo(ox + 12f * s, oy + 21f * s, ox + 4.5f * s, oy + 16.4f * s, ox + 2.6f * s, oy + 11.7f * s)
                cubicTo(ox + 1.2f * s, oy + 8.3f * s, ox + 3.4f * s, oy + 4.8f * s, ox + 6.9f * s, oy + 4.6f * s)
                cubicTo(ox + 8.9f * s, oy + 4.5f * s, ox + 10.5f * s, oy + 5.6f * s, ox + 12f * s, oy + 7.4f * s)
                cubicTo(ox + 13.5f * s, oy + 5.6f * s, ox + 15.1f * s, oy + 4.5f * s, ox + 17.1f * s, oy + 4.6f * s)
                cubicTo(ox + 20.6f * s, oy + 4.8f * s, ox + 22.8f * s, oy + 8.3f * s, ox + 21.4f * s, oy + 11.7f * s)
                cubicTo(ox + 19.5f * s, oy + 16.4f * s, ox + 12f * s, oy + 21f * s, ox + 12f * s, oy + 21f * s)
                close()
            }
            fill.color = 0xFFE8556F.toInt()
            canvas.drawPath(path, fill)
        }
    }

    companion object {
        /** Три часа до покоя. То же число в `kDoingFades` (Dart) и в Swift. */
        private const val FADES_MS = 10_800_000L

        private fun parseColor(hex: String?): Int? {
            if (hex.isNullOrEmpty()) return null
            return try {
                Color.parseColor(hex)
            } catch (e: IllegalArgumentException) {
                null
            }
        }

        /**
         * Цвет пола и горошка по цвету стены — то же правило, что `roomFloor`
         * в `lib/models/doing.dart`: у белой стены чуть темнее, у светлой
         * светлее, у тёмной светлее на малую долю.
         */
        fun roomFloor(wall: Int): Int {
            fun linear(channel: Int): Double {
                val v = channel / 255.0
                return if (v <= 0.03928) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4)
            }
            val brightness = 0.2126 * linear(Color.red(wall)) + 0.7152 * linear(Color.green(wall)) + 0.0722 * linear(Color.blue(wall))
            return when {
                brightness > 0.88 -> mix(wall, 0xFF8F7F86.toInt(), 0.14)
                brightness > 0.4 -> mix(wall, 0xFFFFFFFF.toInt(), 0.55)
                else -> mix(wall, 0xFFFFFFFF.toInt(), 0.16)
            }
        }

        private fun mix(from: Int, to: Int, share: Double): Int {
            fun channel(a: Int, b: Int): Int = Math.round(a + (b - a) * share).toInt()
            return Color.rgb(
                channel(Color.red(from), Color.red(to)),
                channel(Color.green(from), Color.green(to)),
                channel(Color.blue(from), Color.blue(to)),
            )
        }
    }
}
