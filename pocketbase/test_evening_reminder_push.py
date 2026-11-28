"""Вечернее напоминание (TOG-113): python3 pocketbase/test_evening_reminder_push.py"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(__file__))
import evening_reminder_push as m  # noqa: E402

UTC = timezone.utc
MSK = ZoneInfo("Europe/Moscow")
# 28.11.2026 21:00 по Москве.
СЕЙЧАС = datetime(2026, 11, 28, 18, 0, tzinfo=UTC)
ПОЛНОЧЬ = datetime(2026, 11, 27, 21, 0, tzinfo=UTC)  # начало суток по Москве


def user(**kw):
    """Человек на сборке с напоминанием (`remind_v`), блок ещё не открывал:
    оба пункта по умолчанию включены, время 21:00."""
    base = {"fcm_token": "t", "apns_token": "", "notif_synced_at": "",
            "remind_v": 1, "remind_mood": "", "remind_task": "", "remind_at": ""}
    base.update(kw)
    return base


def what(u, mood_last=None, tasks=None, paired=True, task_day="2026-11-28"):
    return m.what_to_remind(u, mood_last=mood_last, tasks=tasks,
                            paired=paired, day_start=ПОЛНОЧЬ, task_day=task_day)


ВЧЕРА = СЕЙЧАС - timedelta(days=1)


class Что(unittest.TestCase):
    def test_по_умолчанию_включено_ничего_не_сделано_оба(self):
        # Решение владельца 28.11.2026: «включишь по умолчанию».
        self.assertEqual(what(user(), mood_last=ВЧЕРА,
                              tasks={"date": "2026-11-27", "done": ["a"]}), {"mood", "task"})
        self.assertEqual(what(user()), {"mood", "task"})

    def test_сегодня_всё_сделано_молчим(self):
        сегодня = ПОЛНОЧЬ + timedelta(hours=10)
        self.assertEqual(what(user(), mood_last=сегодня,
                              tasks={"date": "2026-11-28", "done": ["a"]}), set())

    def test_старая_сборка_не_знает_напоминания_и_выключить_не_может(self):
        self.assertEqual(what(user(remind_v=0), mood_last=ВЧЕРА), set())
        self.assertEqual(what(user(remind_v=None, remind_mood="on")), set())

    def test_выключил_одно(self):
        self.assertEqual(what(user(remind_mood="off"), mood_last=ВЧЕРА), {"task"})
        self.assertEqual(what(user(remind_task="off"), mood_last=ВЧЕРА), {"mood"})
        self.assertEqual(what(user(remind_mood="off", remind_task="off")), set())

    def test_без_пары_задания_нет(self):
        self.assertEqual(what(user(), mood_last=ВЧЕРА, paired=False), {"mood"})

    def test_пустой_список_выполненного_не_считается(self):
        self.assertEqual(what(user(), mood_last=СЕЙЧАС, tasks={"date": "2026-11-28", "done": []}),
                         {"task"})

    def test_две_пары_сделал_в_одной_молчим(self):
        лучшее = m.best_tasks([{"date": "2026-11-27", "done": ["a"]},
                               {"date": "2026-11-28", "done": []},
                               {"date": "2026-11-28", "done": ["b"]}])
        self.assertEqual(лучшее, {"date": "2026-11-28", "done": ["b"]})
        self.assertEqual(what(user(), mood_last=ВЧЕРА, tasks=лучшее), {"mood"})
        self.assertEqual(m.best_tasks([None, "мусор"]), {})

    def test_без_токена_некуда(self):
        self.assertEqual(what(user(fcm_token="", remind_mood="on")), set())

    def test_все_уведомления_выключены_молчим_если_не_включил_сам(self):
        # Выключил все уведомления разом — включённое по умолчанию напоминание
        # его не будит. Включил вечернее напоминание сам — его слово сильнее.
        тихий = {"notif_synced_at": "2026-11-01", **{f: 0 for f in m.NOTIF_FIELDS}}
        self.assertEqual(what(user(**тихий), mood_last=ВЧЕРА), set())
        self.assertEqual(what(user(remind_mood="on", **тихий), mood_last=ВЧЕРА), {"mood"})


class Окно(unittest.TestCase):
    def slot(self, utc, tz, at="21:00"):
        return m.reminder_slot(utc, ZoneInfo(tz) if isinstance(tz, str) else tz, at)

    def test_час_от_выбранного_времени(self):
        # Окно — час: рассылка 21:00 по Москве идёт минуты, крон с `flock`
        # пропускает свои запуски, и время 21:05 иначе выпало бы из окна.
        self.assertEqual(m.WINDOW_MIN, 60)
        self.assertIsNotNone(self.slot(СЕЙЧАС, MSK))
        self.assertIsNotNone(self.slot(СЕЙЧАС + timedelta(minutes=59), MSK))
        self.assertIsNone(self.slot(СЕЙЧАС + timedelta(minutes=60), MSK))
        self.assertIsNone(self.slot(СЕЙЧАС - timedelta(minutes=1), MSK))
        self.assertIsNotNone(self.slot(СЕЙЧАС, MSK, "мусор"))  # кривое — как 21:00

    def test_москва(self):
        day, start, task_day = self.slot(СЕЙЧАС, MSK)
        self.assertEqual((day, start, task_day), ("2026-11-28", ПОЛНОЧЬ, "2026-11-28"))

    def test_у_полуночи_день_от_начала_окна(self):
        # Выбрал 23:55, запуск в 00:05 уже следующих суток: день — 28-е, и
        # отметка в 22:00 28-го считается сегодняшней.
        utc = datetime(2026, 11, 28, 21, 5, tzinfo=UTC)
        day, start, _ = self.slot(utc, MSK, "23:55")
        self.assertEqual(day, "2026-11-28")
        self.assertEqual(start, ПОЛНОЧЬ)
        self.assertIsNone(self.slot(datetime(2026, 11, 28, 20, 50, tzinfo=UTC), MSK, "23:55"))

    def test_день_заданий_по_utc_в_местный_полдень(self):
        # Задания в приложении меняются по UTC. В Сан-Паулу в 21:00 в UTC уже
        # завтра, и без этого правила задание «не сделано» было бы всегда.
        cases = [
            ("America/Sao_Paulo", datetime(2026, 11, 29, 0, 0, tzinfo=UTC)),
            ("America/Los_Angeles", datetime(2026, 11, 29, 5, 0, tzinfo=UTC)),
            ("Asia/Vladivostok", datetime(2026, 11, 28, 11, 0, tzinfo=UTC)),
            ("Europe/Moscow", СЕЙЧАС),
        ]
        for tz, utc in cases:
            day, _, task_day = self.slot(utc, tz)
            self.assertEqual((day, task_day), ("2026-11-28", "2026-11-28"), tz)

    def test_окленд_вчерашнее_задание_не_сегодняшнее(self):
        # UTC+13: местный полдень 28-го — это ещё 27-е по UTC, и правило
        # «UTC-дата в полдень» засчитало бы задание вчерашнего вечера.
        utc = datetime(2026, 11, 28, 8, 0, tzinfo=UTC)  # 21:00 28.11 по Окленду
        day, start, task_day = self.slot(utc, "Pacific/Auckland")
        self.assertEqual((day, task_day), ("2026-11-28", "2026-11-28"))
        вчера_вечером = {"date": "2026-11-27", "done": ["a"]}
        need = m.what_to_remind(user(remind_mood="off"), mood_last=None, tasks=вчера_вечером,
                                paired=True, day_start=start, task_day=task_day)
        self.assertEqual(need, {"task"})

    def test_сан_паулу_сделали_днём_молчим(self):
        utc = datetime(2026, 11, 29, 0, 0, tzinfo=UTC)
        day, start, task_day = self.slot(utc, "America/Sao_Paulo")
        днём = {"date": "2026-11-28", "done": ["a"]}  # 15:00 по местному = 18:00 UTC 28-го
        need = m.what_to_remind(user(remind_mood="off"), mood_last=None, tasks=днём,
                                paired=True, day_start=start, task_day=task_day)
        self.assertEqual(need, set())

    def test_пояс_человека(self):
        # Первый годный из кандидатов: пояс из настроек напоминания, имя и
        # смещение из виджета, смещение из настроения; ничего — Москва.
        self.assertEqual(m.zone_of("Asia/Almaty", "Europe/Kyiv").utcoffset(СЕЙЧАС), timedelta(hours=5))
        self.assertEqual(m.zone_of("", "Europe/Kyiv", "+03:00").utcoffset(СЕЙЧАС), timedelta(hours=2))
        self.assertEqual(m.zone_of("", "", "+05:30").utcoffset(СЕЙЧАС), timedelta(hours=5, minutes=30))
        self.assertEqual(m.zone_of(None, "", "", "+07:00").utcoffset(СЕЙЧАС), timedelta(hours=7))
        self.assertEqual(m.zone_of("мусор", "").utcoffset(СЕЙЧАС), timedelta(hours=3))

    def test_время_отметки_настроения_из_базы(self):
        self.assertEqual(m.parse_pb_time("2026-11-28 10:13:10.528821Z"),
                         datetime(2026, 11, 28, 10, 13, 10, 528821, tzinfo=UTC))
        self.assertIsNone(m.parse_pb_time(""))


class Тексты(unittest.TestCase):
    def test_виды_на_языке_человека(self):
        self.assertEqual(m.texts({"mood"}, "ru", True)[0], "Как прошёл день?")
        self.assertIn("партнёр", m.texts({"mood"}, "ru", True)[1])
        self.assertNotIn("партнёр", m.texts({"mood"}, "ru", False)[1])
        self.assertIn("задание", m.texts({"task"}, "ru", True)[1].lower())
        оба = m.texts({"mood", "task"}, "ru", True)[1].lower()
        self.assertIn("настроение", оба)
        self.assertIn("задание", оба)
        self.assertEqual(m.texts({"mood"}, "xx", True), m.texts({"mood"}, "ru", True))
        for lang in ("ru", "en", "de", "fr", "es", "it", "pt", "zh", "uk"):
            for need in ({"mood"}, {"task"}, {"mood", "task"}):
                for paired in (True, False):
                    title, body = m.texts(need, lang, paired)
                    self.assertTrue(title and body, f"{lang} {need} {paired}")


class Обложка(unittest.TestCase):
    """Уведомления «А» (28.11.2026): обложка — иконка приложения, Ту в гамаке
    в развёрнутом виде; Android — данными и только новой сборке."""

    def test_тела_запросов_к_релеям(self):
        u = {"id": "u1", "apns_token": "a", "fcm_token": "f", "lang": "ru", "notif_v": 1,
             "_paired": True}
        apns, fcm = m.relay_bodies(u, {"mood"}, look=lambda _id: (["still_r.png"], {}))
        self.assertEqual(apns["cover"]["kind"], "evening")
        self.assertEqual(apns["cover"]["art"], {"app": True})
        self.assertTrue(fcm["data_only"])
        self.assertEqual(fcm["cover"]["title"], "Как прошёл день?")

    def test_старая_сборка_android_без_данных(self):
        u = {"id": "u1", "apns_token": "", "fcm_token": "f", "lang": "ru", "notif_v": 0}
        _apns, fcm = m.relay_bodies(u, {"task"}, look=lambda _id: None)
        self.assertNotIn("data_only", fcm)
        self.assertNotIn("cover", fcm)


class Отправка(unittest.TestCase):
    def test_отметка_пишется_пачками_по_ходу(self):
        # Запусков в окне три: упади рассылка посередине или затянись дольше
        # пяти минут — следующий запуск не должен слать тем же людям заново.
        import sqlite3
        st = sqlite3.connect(":memory:")
        m.prepare_state(st)
        todo = [({"id": f"u{i}", "_day": "2026-11-28"}, {"mood"}) for i in range(5)]
        calls = []

        def send(item):
            calls.append(item[0]["id"])
            if item[0]["id"] == "u3":
                raise RuntimeError("релей упал")
            return True

        with self.assertRaises(RuntimeError):
            m.send_all(todo, st, СЕЙЧАС, send=send, workers=1, batch=2)
        got = {r[0] for r in st.execute("SELECT uid FROM sent")}
        self.assertEqual(got, {"u0", "u1"})

    def test_неудачи_не_повторяются_весь_час(self):
        # Окно — час, запусков в нём 12. Лежит релей — без счёта попыток каждый
        # запуск заново гнал бы всех, и пуш пришёл бы к концу окна.
        import sqlite3
        st = sqlite3.connect(":memory:")
        m.prepare_state(st)
        todo = [({"id": "u1", "_day": "2026-11-28"}, {"mood"})]
        for _ in range(m.MAX_TRIES):
            self.assertEqual(m.send_all(todo, st, СЕЙЧАС, send=lambda item: False, workers=1), 0)
        self.assertIn(("u1", "2026-11-28"), m.given_up(st, "2026-11-27"))
        self.assertNotIn(("u2", "2026-11-28"), m.given_up(st, "2026-11-27"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
