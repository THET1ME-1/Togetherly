package com.togetherly.love.notif

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Разбор обложки «А». Примеры — `test/fixtures/push_cover_cases.json`,
 * их собирает сервер (`make_push_cover_fixtures.py`).
 *
 * Запуск: `./gradlew :app:testDebugUnitTest --tests 'com.togetherly.love.notif.*'`
 */
class CoverTest {
    private val root: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null && !File(dir, "pubspec.yaml").exists()) dir = dir.parentFile
        requireNotNull(dir) { "не нашёл корень репозитория" }
    }

    private fun cases(): List<JSONObject> {
        val raw = File(root, "test/fixtures/push_cover_cases.json").readText()
        val arr = JSONObject(raw).getJSONArray("cases")
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    @Test
    fun каждый_пример_сервера_разбирается() {
        val all = cases()
        assertTrue(all.size >= 20)
        for (c in all) {
            val cover = CoverParser.parse(c.getJSONObject("cover").toString())
            assertNotNull(c.getString("kind"), cover)
            cover!!
            assertEquals(c.getString("kind"), cover.kind)
            assertTrue(cover.kind, cover.title.isNotEmpty() || cover.kicker.isNotEmpty())
            assertTrue(cover.link, cover.link.startsWith("loveapp://open/"))
            assertTrue(cover.kind, Tones.known(cover.tone))
            for (a in cover.actions) {
                assertTrue("${cover.kind}/${a.id}", a.native || a.link.startsWith("loveapp://open/"))
            }
        }
    }

    @Test
    fun уведомления_приложения_с_иконкой_и_большой_картинкой() {
        val evening = cases().first { it.getString("kind") == "evening" }
        val cover = CoverParser.parse(evening.getJSONObject("cover").toString())!!
        assertTrue(cover.art.app)
        assertTrue(cover.fromApp)
        assertTrue(cover.artBig!!.url.endsWith("/art_act_rest/still_rest.png"))
        assertEquals(listOf("loveapp://open/mood", "loveapp://open/task"), cover.actions.map { it.link })
    }

    @Test
    fun чат_несёт_всё_для_шторки() {
        val chat = cases().first { it.getString("kind") == "chat" && it.getString("lang") == "ru" }
        val cover = CoverParser.parse(chat.getJSONObject("cover").toString())!!
        val part = cover.chat!!
        assertEquals("m1", part.messageId)
        assertEquals(1795873555018L, part.ts)
        assertEquals(27.0, part.frameHole, 0.001)
        assertTrue(part.avatar.startsWith("https://togetherly.day/api/files/media/r1/"))
        assertTrue(part.image.contains("thumb=400x400"))
        assertEquals("Вы", part.you)
        assertEquals(3, part.quick.size)
        assertEquals(listOf("reply", "hug", "read"), cover.actions.map { it.id })
        assertTrue(cover.actions.all { it.native })
    }

    @Test
    fun чужие_ссылки_не_проходят() {
        val raw = """{"v":1,"kind":"miss","title":"x","link":"https://evil.example/",
            "art":{"url":"http://plain.example/a.png"},
            "actions":[{"id":"open","label":"О","link":"intent://x"},
                       {"id":"wipe","label":"Стереть"}]}"""
        val cover = CoverParser.parse(raw)!!
        assertEquals("loveapp://open/home", cover.link)
        assertTrue(cover.art.app)          // http — не грузим, ставим иконку
        assertEquals(listOf("open"), cover.actions.map { it.id })  // незнакомое действие выброшено
        assertEquals("loveapp://open/home", cover.actions[0].link)
    }

    @Test
    fun мусор_и_чужая_версия_это_null() {
        assertNull(CoverParser.parse(null))
        assertNull(CoverParser.parse(""))
        assertNull(CoverParser.parse("{не json"))
        assertNull(CoverParser.parse("""{"v":2,"kind":"miss"}"""))
        assertNull(CoverParser.parse("""{"v":1}"""))
    }

    @Test
    fun тоны_и_действия_как_на_сервере() {
        val server = File(root, "pocketbase/hotpath/push_cover.py").readText()
        val tones = Regex("\"tone\": \"([a-z_]+)\"").findAll(server).map { it.groupValues[1] }.toSet()
        assertTrue(tones.size >= 10)
        for (t in tones) assertTrue(t, Tones.known(t))
        val native = Regex("ДЕЙСТВИЯ_ТЕЛЕФОНА = \\(([^)]*)\\)").find(server)!!.groupValues[1]
            .split(",").map { it.trim().trim('"') }.filter { it.isNotEmpty() }.toSet()
        assertEquals(native, CoverParser.NATIVE_ACTIONS)
    }

    @Test
    fun история_без_повторов_и_с_пределом() {
        assertNull(ChatHistory.append(listOf("a", "b"), "b"))
        assertEquals(listOf("a", "b", "c"), ChatHistory.append(listOf("a", "b"), "c"))
        // Свой ответ без номера добавляется всегда.
        assertEquals(listOf("a", ""), ChatHistory.append(listOf("a"), ""))
        val long = (1..ChatHistory.KEEP).map { "m$it" }
        val after = ChatHistory.append(long, "new")!!
        assertEquals(ChatHistory.KEEP, after.size)
        assertEquals("new", after.last())
        assertFalse("m1" in after)
    }

    @Test
    fun номер_как_у_pocketbase() {
        val ids = (1..200).map { PbId.next() }.toSet()
        assertEquals(200, ids.size)
        assertTrue(ids.all { PbId.valid(it) })
        assertFalse(PbId.valid("ABC"))
    }

    @Test
    fun ежедневное_переносится_на_то_же_время() {
        val day = 24 * 3600 * 1000L
        val first = 1_795_000_000_000L
        // Срок прошёл неделю назад — ближайший будущий день, то же время суток.
        val now = first + 7 * day + 1000
        val next = NotifAlarm.nextDay(first, now)
        assertTrue(next > now)
        assertTrue(next - now <= day)
        // Ещё не наступил — не трогаем.
        assertEquals(first + day, NotifAlarm.nextDay(first + day, first))
    }

    @Test
    fun дни_вместе_берут_заголовок_своего_дня() {
        val day = 24 * 3600 * 1000L
        val first = 1_795_000_000_000L
        val e = NotifAlarm.Entry(
            id = 9101, whenMs = first, cover = "{}", title = "10", body = "", tag = "", channel = "c",
            exact = false, daily = true, titles = listOf("10 дней", "11 дней", "12 дней"),
        )
        assertEquals("10 дней", e.titleAt(first))
        assertEquals("12 дней", e.titleAt(first + 2 * day))
        // Список кончился — остаётся последний, до открытия приложения.
        assertEquals("12 дней", e.titleAt(first + 9 * day))
        // Перенос на завтра хранит начало списка.
        val again = NotifAlarm.Entry.of(e.copy(whenMs = first + day).toJson())
        assertEquals("11 дней", again.titleAt(again.whenMs))
    }

    @Test
    fun буква_без_аватара() {
        assertEquals("А", Tones.monogram(" алина"))
        assertEquals("?", Tones.monogram("  "))
        assertEquals("阿", Tones.monogram("阿琳娜"))
    }
}
