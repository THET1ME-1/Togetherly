package com.togetherly.love

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Звука в файле нет или система не знает его формат. */
class SoundClipUnsupported(message: String) : Exception(message)

/**
 * Канал `love_app/sound_clip`: проба песни, волна для рамки выбора и вырезка
 * куска в m4a. Разбор идёт на своём потоке, ответ возвращается на главный.
 */
class SoundClipChannel : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("failed", "нет пути к файлу", null)
            return
        }
        when (call.method) {
            "probe" -> answer(result) { SoundClipCore.probe(path) }
            "waveform" -> answer(result) {
                SoundClipCore.waveform(path, call.argument<Number>("buckets")?.toInt() ?: 72)
            }
            "clip" -> answer(result) {
                SoundClipCore.clip(
                    path,
                    call.argument<Number>("startMs")?.toLong() ?: 0L,
                    call.argument<Number>("endMs")?.toLong() ?: 0L,
                    call.argument<Number>("fadeMs")?.toLong() ?: 0L,
                    call.argument<String>("outPath") ?: throw IOException("нет пути для куска"),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun answer(result: MethodChannel.Result, work: () -> Any) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (error: SoundClipUnsupported) {
                main.post { result.error("unsupported", error.message, null) }
            } catch (error: Throwable) {
                main.post { result.error("failed", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        const val CHANNEL = "love_app/sound_clip"
    }
}

/** Разбор и вырезка без привязки к каналу: так их проверяет тест на эмуляторе. */
object SoundClipCore {
    private const val TIMEOUT_US = 10_000L

    fun probe(path: String): Map<String, Any> {
        val extractor = openExtractor(path)
        try {
            val format = selectAudio(extractor)
            var durationMs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION) / 1000
            } else 0L
            var title = ""
            var artist = ""
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim() ?: ""
                artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.trim() ?: ""
                if (durationMs <= 0) {
                    durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: 0L
                }
            } catch (_: Exception) {
                // Тегов может не быть вовсе, это не ошибка
            } finally {
                try { retriever.release() } catch (_: Exception) {}
            }
            return mapOf("durationMs" to durationMs, "title" to title, "artist" to artist)
        } finally {
            extractor.release()
        }
    }

    /**
     * Волна всей песни: на каждый столбик сдвигаемся к его середине и разбираем
     * около 100 мс. Весь файл не разбирается, поэтому десятиминутный трек
     * готов за секунду.
     */
    fun waveform(path: String, buckets: Int): List<Double> {
        val count = buckets.coerceIn(8, 400)
        val decoder = Decoder(path)
        try {
            val durationUs = decoder.durationUs
            if (durationUs <= 0) throw SoundClipUnsupported("у файла нет длительности")
            val values = DoubleArray(count)
            for (index in 0 until count) {
                val atUs = durationUs * index / count + durationUs / (2L * count)
                decoder.seek(atUs)
                val wanted = max(1, decoder.sampleRate / 10)
                var sum = 0.0
                var taken = 0
                decoder.pump { _, chunk ->
                    val channels = max(1, decoder.channels)
                    var offset = 0
                    while (offset + channels <= chunk.size && taken < wanted) {
                        var mix = 0.0
                        for (channel in 0 until channels) mix += chunk[offset + channel]
                        mix /= channels * 32768.0
                        sum += mix * mix
                        taken++
                        offset += channels
                    }
                    taken < wanted
                }
                values[index] = if (taken > 0) sqrt(sum / taken) else 0.0
            }
            val peak = values.maxOrNull() ?: 0.0
            return values.map { if (peak > 0) it / peak else 0.0 }
        } finally {
            decoder.release()
        }
    }

    /**
     * Кусок [startMs]..[endMs] в m4a: PCM куска собирается в памяти (минута
     * стерео — около 10 МБ), края затухают за [fadeMs], затем AAC-LC в MP4.
     */
    fun clip(path: String, startMs: Long, endMs: Long, fadeMs: Long, outPath: String): Map<String, Any> {
        if (endMs <= startMs) throw IOException("пустой кусок")
        val out = File(outPath)
        out.parentFile?.mkdirs()
        val startUs = startMs * 1000
        val endUs = endMs * 1000

        // Разбор куска в PCM
        val decoder = Decoder(path)
        val pcm = ShortBuilder(1 shl 20)
        var rate = 0
        var outChannels = 0
        try {
            decoder.seek(startUs)
            decoder.pump { chunkUs, chunk ->
                val channels = max(1, decoder.channels)
                val sampleRate = decoder.sampleRate
                val frames = chunk.size / channels
                val chunkEndUs = chunkUs + frames * 1_000_000L / sampleRate
                if (chunkEndUs <= startUs) return@pump true
                if (rate == 0) {
                    rate = sampleRate
                    outChannels = min(channels, 2)
                }
                val first = if (chunkUs < startUs) {
                    ((startUs - chunkUs) * sampleRate / 1_000_000L).toInt().coerceIn(0, frames)
                } else 0
                val last = if (chunkEndUs > endUs) {
                    ((endUs - chunkUs) * sampleRate / 1_000_000L).toInt().coerceIn(0, frames)
                } else frames
                for (frame in first until last) {
                    val base = frame * channels
                    if (outChannels == 1) {
                        pcm.add(chunk[base])
                    } else if (channels == 2) {
                        pcm.add(chunk[base])
                        pcm.add(chunk[base + 1])
                    } else {
                        // Больше двух каналов сводим в стерео: чётные налево, нечётные направо
                        var left = 0
                        var right = 0
                        var leftCount = 0
                        var rightCount = 0
                        for (channel in 0 until channels) {
                            if (channel % 2 == 0) { left += chunk[base + channel]; leftCount++ }
                            else { right += chunk[base + channel]; rightCount++ }
                        }
                        pcm.add((left / max(1, leftCount)).toShort())
                        pcm.add((right / max(1, rightCount)).toShort())
                    }
                }
                chunkEndUs < endUs
            }
        } finally {
            decoder.release()
        }
        if (rate == 0 || pcm.size < outChannels) throw IOException("в куске нет звука")

        var samples = pcm.toArray()
        // AAC не берёт частоты выше 48 кГц: прореживаем вдвое
        while (rate > 48_000) {
            samples = halveRate(samples, outChannels)
            rate /= 2
        }
        val frames = samples.size / outChannels
        applyFade(samples, outChannels, rate, fadeMs)
        val peaks = peaksOf(samples, outChannels, 40)

        try {
            encodeAac(samples, outChannels, rate, outPath)
        } catch (error: Throwable) {
            out.delete()
            throw error
        }
        return mapOf(
            "path" to outPath,
            "durationMs" to frames * 1000L / rate,
            "peaks" to peaks,
        )
    }

    private fun openExtractor(path: String): MediaExtractor {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (error: Exception) {
            extractor.release()
            throw SoundClipUnsupported("файл не открывается: ${error.message}")
        }
        return extractor
    }

    /** Выбирает первую звуковую дорожку и отдаёт её формат. */
    private fun selectAudio(extractor: MediaExtractor): MediaFormat {
        for (track in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(track)
            if (format.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                extractor.selectTrack(track)
                return format
            }
        }
        throw SoundClipUnsupported("в файле нет звука")
    }

    private fun halveRate(samples: ShortArray, channels: Int): ShortArray {
        val frames = samples.size / channels / 2
        val out = ShortArray(frames * channels)
        for (frame in 0 until frames) {
            for (channel in 0 until channels) {
                val first = samples[(frame * 2) * channels + channel]
                val second = samples[(frame * 2 + 1) * channels + channel]
                out[frame * channels + channel] = ((first + second) / 2).toShort()
            }
        }
        return out
    }

    private fun applyFade(samples: ShortArray, channels: Int, rate: Int, fadeMs: Long) {
        val frames = samples.size / channels
        val fadeFrames = min((fadeMs * rate / 1000).toInt(), frames / 2)
        if (fadeFrames <= 0) return
        for (frame in 0 until fadeFrames) {
            val gain = frame.toDouble() / fadeFrames
            for (channel in 0 until channels) {
                val head = frame * channels + channel
                val tail = (frames - 1 - frame) * channels + channel
                samples[head] = (samples[head] * gain).toInt().toShort()
                samples[tail] = (samples[tail] * gain).toInt().toShort()
            }
        }
    }

    /** RMS моно-смеси по [count] равным частям куска, 0..1. */
    private fun peaksOf(samples: ShortArray, channels: Int, count: Int): List<Double> {
        val frames = samples.size / channels
        val out = ArrayList<Double>(count)
        for (index in 0 until count) {
            val from = (frames.toLong() * index / count).toInt()
            val to = max(from + 1, (frames.toLong() * (index + 1) / count).toInt()).coerceAtMost(frames)
            var sum = 0.0
            var taken = 0
            for (frame in from until to) {
                var mix = 0.0
                for (channel in 0 until channels) mix += samples[frame * channels + channel]
                mix /= channels * 32768.0
                sum += mix * mix
                taken++
            }
            out.add(if (taken > 0) sqrt(sum / taken) else 0.0)
        }
        return out
    }

    private fun encodeAac(samples: ShortArray, channels: Int, rate: Int, outPath: String) {
        val mime = MediaFormat.MIMETYPE_AUDIO_AAC
        val format = MediaFormat.createAudioFormat(mime, rate, channels).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, if (channels == 1) 64_000 else 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
        }
        val encoder = MediaCodec.createEncoderByType(mime)
        var opened: MediaMuxer? = null
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            val muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            opened = muxer
            val info = MediaCodec.BufferInfo()
            var track = -1
            var written = 0
            var inputDone = false
            var outputDone = false
            var idle = 0
            fun timeOf(sampleOffset: Int) = (sampleOffset / channels).toLong() * 1_000_000L / rate

            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = encoder.getInputBuffer(inIndex)!!
                        buffer.clear()
                        val room = buffer.capacity() / 2
                        val count = min(room - room % channels, samples.size - written)
                        if (count <= 0) {
                            encoder.queueInputBuffer(inIndex, 0, 0, timeOf(written), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            buffer.order(ByteOrder.nativeOrder()).asShortBuffer().put(samples, written, count)
                            encoder.queueInputBuffer(inIndex, 0, count * 2, timeOf(written), 0)
                            written += count
                        }
                    }
                }
                val outIndex = encoder.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(encoder.outputFormat)
                        muxer.start()
                    }
                    outIndex >= 0 -> {
                        idle = 0
                        val buffer = encoder.getOutputBuffer(outIndex)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && track >= 0) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            muxer.writeSampleData(track, buffer, info)
                        }
                        encoder.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    inputDone && ++idle > 500 -> throw IOException("кодер замолчал")
                }
            }
            muxer.stop()
        } finally {
            try { encoder.stop() } catch (_: Exception) {}
            encoder.release()
            try { opened?.release() } catch (_: Exception) {}
        }
    }

    /** Декодер одной звуковой дорожки: отдаёт PCM 16 бит кусками с временем начала. */
    private class Decoder(path: String) {
        private val extractor = SoundClipCore.openExtractor(path)
        private val codec: MediaCodec
        private val info = MediaCodec.BufferInfo()
        private var inputDone = false
        private var floatPcm = false
        var sampleRate: Int
        var channels: Int
        val durationUs: Long

        init {
            val format = try {
                SoundClipCore.selectAudio(extractor)
            } catch (error: Throwable) {
                extractor.release()
                throw error
            }
            sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            codec = try {
                MediaCodec.createDecoderByType(mime).also {
                    it.configure(format, null, null, 0)
                    it.start()
                }
            } catch (error: Exception) {
                extractor.release()
                throw SoundClipUnsupported("нет декодера для $mime")
            }
        }

        fun seek(atUs: Long) {
            extractor.seekTo(atUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            codec.flush()
            inputDone = false
        }

        /** Гонит декодер, пока [onChunk] не скажет «хватит» или файл не кончится. */
        fun pump(onChunk: (Long, ShortArray) -> Boolean) {
            var idle = 0
            while (true) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(SoundClipCore.TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, SoundClipCore.TIMEOUT_US)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = codec.outputFormat
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = format.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            format.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    outIndex >= 0 -> {
                        idle = 0
                        val end = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        var more = true
                        if (info.size > 0) {
                            val buffer = codec.getOutputBuffer(outIndex)!!
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            more = onChunk(info.presentationTimeUs, readPcm(buffer))
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if (end || !more) return
                    }
                    inputDone && ++idle > 500 -> return
                }
            }
        }

        private fun readPcm(buffer: ByteBuffer): ShortArray {
            val ordered = buffer.order(ByteOrder.nativeOrder())
            return if (floatPcm) {
                val floats = ordered.asFloatBuffer()
                ShortArray(floats.remaining()) {
                    (floats.get() * 32767f).toInt().coerceIn(-32768, 32767).toShort()
                }
            } else {
                val shorts = ordered.asShortBuffer()
                ShortArray(shorts.remaining()).also { shorts.get(it) }
            }
        }

        fun release() {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            extractor.release()
        }
    }

    /** Растущий массив сэмплов без упаковки каждого в объект. */
    private class ShortBuilder(capacity: Int) {
        private var data = ShortArray(capacity)
        var size = 0
            private set

        fun add(value: Short) {
            if (size == data.size) data = data.copyOf(data.size * 2)
            data[size++] = value
        }

        fun toArray(): ShortArray = data.copyOf(size)
    }
}
