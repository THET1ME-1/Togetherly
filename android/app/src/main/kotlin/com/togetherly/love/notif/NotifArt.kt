package com.togetherly.love.notif

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Log
import androidx.core.content.res.ResourcesCompat
import com.togetherly.love.R
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Картинки обложки «А»: скачать и нарисовать плашкой, как в макете —
 * скругление в четверть стороны, у картинки из каталога плашка цвета тона,
 * фото во всю плашку, у уведомлений приложения его иконка.
 *
 * Картинка не скачалась за отведённое время — уведомление всё равно
 * показывается, с иконкой приложения (Review Focus плана).
 */
object NotifArt {
    private const val TAG = "NotifArt"
    private val pool = Executors.newFixedThreadPool(4)

    /** Скачать и разжать картинки параллельно; что не успело к [budgetMs] — null. */
    fun fetchAll(ctx: Context, arts: Map<String, Art>, budgetMs: Long): Map<String, Bitmap?> {
        val deadline = System.currentTimeMillis() + budgetMs
        val futures = arts.mapValues { (_, art) ->
            pool.submit(Callable { fetch(ctx, art, budgetMs) })
        }
        return futures.mapValues { (_, f) ->
            val left = deadline - System.currentTimeMillis()
            try {
                if (left <= 0) null else f.get(left, TimeUnit.MILLISECONDS)
            } catch (e: Exception) {
                f.cancel(true)
                Log.i(TAG, "картинка не успела: ${e.javaClass.simpleName}")
                null
            }
        }
    }

    private fun fetch(ctx: Context, art: Art, budgetMs: Long): Bitmap? {
        if (art.url.isEmpty()) return null
        // Открытые картинки (каталог, аватары) по одному адресу не меняются:
        // новый файл — новое имя. Берём с диска, а скачанное кладём туда же —
        // уведомление по расписанию в 00:10 без сети встаёт с картинкой.
        val cached = if (art.auth) null else cacheFile(ctx, art.url)
        if (cached != null && cached.length() > 0) {
            try {
                val bytes = cached.readBytes()
                decode(bytes, 512)?.let {
                    cached.setLastModified(System.currentTimeMillis())
                    return it
                }
            } catch (e: Exception) {
                Log.i(TAG, "кэш картинки не прочитался: ${e.message}")
            }
        }
        val url = if (art.auth) {
            NotifNet.withFileToken(ctx, art.url, budgetMs / 2) ?: return null
        } else {
            art.url
        }
        val reply = NotifNet.call(ctx, "GET", url, auth = false, budgetMs = budgetMs, maxBytes = 6 * 1024 * 1024)
        if (!reply.ok || reply.body.isEmpty()) return null
        val bitmap = decode(reply.body, 512) ?: return null
        if (cached != null) store(cached, reply.body)
        return bitmap
    }

    /** Имя файла кэша по адресу картинки; пустой адрес — null. */
    fun cacheName(url: String): String? {
        if (url.isEmpty()) return null
        val digest = java.security.MessageDigest.getInstance("SHA-1").digest(url.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private const val CACHE_DIR = "notif_art"
    private const val CACHE_KEEP_MS = 30L * 24 * 3600 * 1000

    private fun cacheFile(ctx: Context, url: String): java.io.File? {
        val name = cacheName(url) ?: return null
        return java.io.File(java.io.File(ctx.cacheDir, CACHE_DIR), name)
    }

    /** Записать через временный файл: оборванная запись не оставит битый кэш. */
    private fun store(file: java.io.File, bytes: ByteArray) {
        try {
            val dir = file.parentFile ?: return
            dir.mkdirs()
            // Месяц без показа — убираем: картинки сменились, а место не резиновое.
            val old = System.currentTimeMillis() - CACHE_KEEP_MS
            dir.listFiles()?.filter { it.lastModified() < old }?.forEach { it.delete() }
            val tmp = java.io.File(dir, file.name + ".tmp")
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(file)) tmp.delete()
        } catch (e: Exception) {
            Log.i(TAG, "кэш картинки не записался: ${e.message}")
        }
    }

    /** Разжать с уменьшением до [maxSide]: обложке больше не нужно. */
    fun decode(bytes: ByteArray, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxSide && bounds.outHeight / (sample * 2) >= maxSide) sample *= 2
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private fun rounded(size: Int): Path = Path().apply {
        val r = size * 0.25f
        addRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), r, r, Path.Direction.CW)
    }

    /**
     * Плашка обложки стороны [size]: [picture] из каталога — на плашке тона,
     * [photo] — во всю плашку, [symbol] — значок даты, иначе иконка приложения.
     */
    fun tile(ctx: Context, art: Art, bitmap: Bitmap?, tone: Tone, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.clipPath(rounded(size))
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        when {
            bitmap != null && art.auth -> drawCover(canvas, bitmap, size)
            bitmap != null -> {
                fill.color = tone.tint
                canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), fill)
                drawInside(canvas, bitmap, size, 0.86f)
            }
            art.symbol.isNotEmpty() && symbolFont(ctx) != null -> {
                fill.color = tone.tint
                canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), fill)
                drawSymbol(ctx, canvas, art.symbol, tone.deep, size)
            }
            else -> drawAppIcon(ctx, canvas, size)
        }
        return out
    }

    /** Фото — по центру с обрезкой краёв (как BoxFit.cover). */
    private fun drawCover(canvas: Canvas, src: Bitmap, size: Int) {
        val scale = maxOf(size.toFloat() / src.width, size.toFloat() / src.height)
        val m = Matrix().apply {
            setScale(scale, scale)
            postTranslate((size - src.width * scale) / 2f, (size - src.height * scale) / 2f)
        }
        canvas.drawBitmap(src, m, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }

    /** Картинка целиком внутри доли [k] стороны (как BoxFit.contain). */
    private fun drawInside(canvas: Canvas, src: Bitmap, size: Int, k: Float) {
        val box = size * k
        val scale = minOf(box / src.width, box / src.height)
        val m = Matrix().apply {
            setScale(scale, scale)
            postTranslate((size - src.width * scale) / 2f, (size - src.height * scale) / 2f)
        }
        canvas.drawBitmap(src, m, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }

    @Volatile private var symbols: Typeface? = null
    @Volatile private var symbolsTried = false

    /** Шрифт значков из ресурсов Flutter: тот же, что у выбора символа даты. */
    private fun symbolFont(ctx: Context): Typeface? {
        if (!symbolsTried) {
            symbolsTried = true
            symbols = try {
                Typeface.createFromAsset(ctx.assets, "flutter_assets/assets/fonts/MaterialSymbolsRounded.ttf")
            } catch (e: Exception) {
                Log.i(TAG, "шрифт значков не открылся: ${e.message}")
                null
            }
        }
        return symbols
    }

    /** Значок по имени: шрифт собирает его из букв лигатурой. */
    private fun drawSymbol(ctx: Context, canvas: Canvas, name: String, color: Int, size: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = symbolFont(ctx)
            this.color = color
            textSize = size * 0.58f
            textAlign = Paint.Align.CENTER
            fontFeatureSettings = "'liga' 1"
        }
        // Имя без лигатуры шире плашки: значит, такого значка нет — сердце.
        val text = if (p.measureText(name) > size * 0.9f) "favorite" else name
        val fm = p.fontMetrics
        canvas.drawText(text, size / 2f, size / 2f - (fm.ascent + fm.descent) / 2f, p)
    }

    /** Иконка, что сейчас стоит на рабочем столе (у человека могла быть цветная). */
    private fun launcherIcon(ctx: Context): Drawable? = try {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(ctx.packageName)
        pm.queryIntentActivities(intent, 0).firstOrNull()?.loadIcon(pm)
            ?: ResourcesCompat.getDrawable(ctx.resources, R.mipmap.launcher_icon, null)
    } catch (_: Exception) {
        ResourcesCompat.getDrawable(ctx.resources, R.mipmap.launcher_icon, null)
    }

    private fun drawAppIcon(ctx: Context, canvas: Canvas, size: Int) {
        val icon = launcherIcon(ctx) ?: return
        if (Build.VERSION.SDK_INT >= 26 && icon is AdaptiveIconDrawable) {
            // Слои адаптивной иконки — 108 единиц, видно 72 посередине: рисуем
            // их в полтора раза больше плашки, края уходят под скругление.
            val pad = (size * 0.25f).toInt()
            for (layer in listOfNotNull(icon.background, icon.foreground)) {
                layer.setBounds(-pad, -pad, size + pad, size + pad)
                layer.draw(canvas)
            }
        } else {
            icon.setBounds(0, 0, size, size)
            icon.draw(canvas)
        }
    }

    /**
     * Аватар партнёра для переписки: фото кружком, поверх рамка из
     * приложения. Рамка в 100/62 раза больше фото, фото ужато до
     * `hole / 31` (как `FramedAvatar`). Нет фото — кружок с буквой имени.
     */
    fun avatar(ctx: Context, photo: Bitmap?, frame: Bitmap?, hole: Double, name: String, tone: Tone, size: Int): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val photoSide = if (frame != null) size * 62f / 100f * (hole / 31.0).toFloat() else size.toFloat()
        val left = (size - photoSide) / 2f
        val circle = RectF(left, left, left + photoSide, left + photoSide)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if (photo != null) {
            val scale = maxOf(photoSide / photo.width, photoSide / photo.height)
            val shader = BitmapShader(photo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            shader.setLocalMatrix(Matrix().apply {
                setScale(scale, scale)
                postTranslate(left + (photoSide - photo.width * scale) / 2f, left + (photoSide - photo.height * scale) / 2f)
            })
            paint.shader = shader
            canvas.drawOval(circle, paint)
        } else {
            paint.color = tone.tint
            canvas.drawOval(circle, paint)
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = tone.label
                textAlign = Paint.Align.CENTER
                textSize = photoSide * 0.44f
                typeface = try {
                    ResourcesCompat.getFont(ctx, R.font.unbounded_semibold)
                } catch (_: Exception) {
                    Typeface.DEFAULT_BOLD
                }
            }
            val fm = text.fontMetrics
            canvas.drawText(Tones.monogram(name), size / 2f, size / 2f - (fm.ascent + fm.descent) / 2f, text)
        }
        if (frame != null) {
            val m = Matrix().apply { setScale(size.toFloat() / frame.width, size.toFloat() / frame.height) }
            canvas.drawBitmap(frame, m, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
        }
        return out
    }
}
