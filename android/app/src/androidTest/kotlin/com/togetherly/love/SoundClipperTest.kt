package com.togetherly.love

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Вырезка звука на настоящем Android: образцы — пять секунд тона 440 Гц с
 * плавающей громкостью в mp3, m4a и wav (assets теста).
 */
@RunWith(AndroidJUnit4::class)
class SoundClipperTest {
    private val target = InstrumentationRegistry.getInstrumentation().targetContext
    private val assets = InstrumentationRegistry.getInstrumentation().context.assets
    private val samples = listOf("tone.mp3", "tone.m4a", "tone.wav")

    private fun copy(name: String): String {
        val out = File(target.cacheDir, name)
        assets.open(name).use { input -> out.outputStream().use { input.copyTo(it) } }
        return out.path
    }

    private fun millis(value: Any?) = (value as Number).toLong()

    @Test
    fun probeReadsDurationAndTags() {
        for (name in samples) {
            val ms = millis(SoundClipCore.probe(copy(name))["durationMs"])
            assertTrue("$name: $ms мс", ms in 4850..5150)
        }
        val tagged = SoundClipCore.probe(copy("tone.mp3"))
        assertEquals("Проба", tagged["title"])
        assertEquals("Togetherly", tagged["artist"])
    }

    @Test
    fun waveformIsNormalized() {
        for (name in samples) {
            val bars = SoundClipCore.waveform(copy(name), 48)
            assertEquals(48, bars.size)
            assertTrue(name, bars.all { it in 0.0..1.0 })
            assertEquals(name, 1.0, bars.maxOrNull()!!, 1e-9)
            // Громкость образца плавает: волна не должна быть ровной
            assertTrue(name, bars.minOrNull()!! < 0.8)
        }
    }

    @Test
    fun clipCutsTwoSecondsWithFade() {
        for (name in samples) {
            val out = File(target.cacheDir, "cut_$name.m4a").path
            val result = SoundClipCore.clip(copy(name), 1000, 3000, 200, out)
            val ms = millis(result["durationMs"])
            assertTrue("$name: $ms мс", ms in 1880..2120)
            @Suppress("UNCHECKED_CAST")
            val peaks = result["peaks"] as List<Double>
            assertEquals(40, peaks.size)
            // Затухание: первый столбик тише середины
            assertTrue("$name: ${peaks.first()} против ${peaks[20]}", peaks.first() < peaks[20])
            val again = millis(SoundClipCore.probe(out)["durationMs"])
            assertTrue("$name повторно: $again мс", again in 1850..2150)
        }
    }

    @Test
    fun clipNearTheEndStopsAtTheEnd() {
        val out = File(target.cacheDir, "tail.m4a").path
        val result = SoundClipCore.clip(copy("tone.m4a"), 4000, 9000, 100, out)
        val ms = millis(result["durationMs"])
        assertTrue("хвост: $ms мс", ms in 850..1100)
    }

    @Test(expected = SoundClipUnsupported::class)
    fun textFileIsUnsupported() {
        val fake = File(target.cacheDir, "fake.mp3").apply { writeText("это не песня") }
        SoundClipCore.probe(fake.path)
    }
}
