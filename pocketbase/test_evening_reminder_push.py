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
    """Человек на сборке с напоминанием: `remind_at` она шлёт всегда."""
    base = {"fcm_token": "t", "apns_token": "", "notif_synced_at": "",
            "remind_mood_off": 0, "remind_task_off": 0, "remind_at": "21:00",
            "remind_custom": 0}
    base.update(kw)
    return base


def what(u, mood_last=None, mood_days=0, tasks=None, paired=True, task_day="2026-11-28"):
    return m.what_to_remind(u, mood_last=mood_last, mood_days=mood_days, tasks=tasks,
                            paired=paired, day_start=ПОЛНОЧЬ, task_day=task_day)


ВЧЕРА = СЕЙЧАС - timedelta(days=1)


class Что(unittest.TestCase):
    def test_привычка_и_ничего_не_сделано_оба(self):
        self.assertEqual(what(user(), mood_last=ВЧЕРА, mood_days=6,
                              tasks={"date": "2026-11-27", "done": ["a"]}), {"mood", "task"})

    def test_сегодня_всё_сделано_молчим(self):
        сегодня = ПОЛНОЧЬ + timedelta(hours=10)
        self.assertEqual(what(user(), mood_last=сегодня, mood_days=6,
                              tasks={"date": "2026-11-28", "done": ["a"]}), set())

    def test_старая_сборка_не_знает_напоминания_и_выключить_не_может(self):
        self.assertEqual(what(user(remind_at=""), mood_last=ВЧЕРА, mood_days=9,
                              tasks={"date": "2026-11-27", "done": ["a"]}), set())

    def test_редко_отмечает_не_будим(self):
        # Замер 27.11.2026: из 36 тысяч, отмечавших хоть раз за 14 дней, 27
        # тысяч к 21:00 не отметились — ежедневный пуш тем, кто заходит раз
        # в две недели, был бы спамом.
        self.assertEqual(what(user(), mood_last=ВЧЕРА, mood_days=m.HABIT_MOOD_DAYS - 1), set())
        self.assertEqual(what(user(), mood_last=ВЧЕРА, mood_days=m.HABIT_MOOD_DAYS), {"mood"})

    def test_задание_по_привычке_последние_три_дня(self):
        self.assertEqual(what(user(), tasks={"date": "2026-11-25", "done": ["a"]}), {"task"})
        self.assertEqual(what(user(), tasks={"date": "2026-11-24", "done": ["a"]}), set())

    def test_сам_настраивал_значит_хочет(self):
        self.assertEqual(what(user(remind_custom=1)), {"mood", "task"})

    def test_выключил_одно(self):
        t = {"date": "2026-11-27", "done": ["a"]}
        self.assertEqual(what(user(remind_mood_off=1), mood_last=ВЧЕРА, mood_days=6, tasks=t), {"task"})
        self.assertEqual(what(user(remind_task_off=1), mood_last=ВЧЕРА, mood_days=6, tasks=t), {"mood"})

    def test_без_пары_задания_нет(self):
        self.assertEqual(what(user(), mood_last=ВЧЕРА, mood_days=6, paired=False), {"mood"})

    def test_пустой_список_выполненного_не_считается(self):
        self.assertEqual(what(user(remind_custom=1), tasks={"date": "2026-11-28", "done": []}),
                         {"mood", "task"})

    def test_две_пары_сделал_в_одной_молчим(self):
        лучшее = m.best_tasks([{"date": "2026-11-27", "done": ["a"]},
                               {"date": "2026-11-28", "done": []},
                               {"date": "2026-11-28", "done": ["b"]}])
        self.assertEqual(лучшее, {"date": "2026-11-28", "done": ["b"]})
        self.assertEqual(what(user(), mood_last=ВЧЕРА, mood_days=6, tasks=лучшее), {"mood"})
        self.assertEqual(m.best_tasks([None, "мусор"]), {})

    def test_без_токена_и_со_всеми_выключенными_уведомлениями(self):
        self.assertEqual(what(user(fcm_token=""), mood_last=ВЧЕРА, mood_days=6), set())
        выключил = user(notif_synced_at="2026-11-01", **{f: 0 for f in m.NOTIF_FIELDS})
        self.assertEqual(what(выключил, mood_last=ВЧЕРА, mood_days=6), set())


class Окно(unittest.TestCase):
    def slot(self, utc, tz, at="21:00"):
        return m.reminder_slot(utc, ZoneInfo(tz) if isinstance(tz, str) else tz, at)

    def test_пятнадцать_минут_от_выбранного_времени(self):
        self.assertIsNotNone(self.slot(СЕЙЧАС, MSK))
        self.assertIsNotNone(self.slot(СЕЙЧАС + timedelta(minutes=14), MSK))
        self.assertIsNone(self.slot(СЕЙЧАС + timedelta(minutes=15), MSK))
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

    def test_сан_паулу_сделали_днём_молчим(self):
        utc = datetime(2026, 11, 29, 0, 0, tzinfo=UTC)
        day, start, task_day = self.slot(utc, "America/Sao_Paulo")
        днём = {"date": "2026-11-28", "done": ["a"]}  # 15:00 по местному = 18:00 UTC 28-го
        need = m.what_to_remind(user(), mood_last=None, mood_days=0, tasks=днём,
                                paired=True, day_start=start, task_day=task_day)
        self.assertEqual(need, set())

    def test_пояс_человека(self):
        self.assertEqual(m.zone_of("Europe/Kyiv", "+03:00", "").utcoffset(СЕЙЧАС), timedelta(hours=2))
        self.assertEqual(m.zone_of("", "+05:30", "").utcoffset(СЕЙЧАС), timedelta(hours=5, minutes=30))
        self.assertEqual(m.zone_of("", "", "+07:00").utcoffset(СЕЙЧАС), timedelta(hours=7))
        self.assertEqual(m.zone_of("мусор", "", "").utcoffset(СЕЙЧАС), timedelta(hours=3))

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


class Отправка(unittest.TestCase):
    def test_отметка_пишется_пачками_по_ходу(self):
        # Запусков в окне три: упади рассылка посередине или затянись дольше
        # пяти минут — следующий запуск не должен слать тем же людям заново.
        import sqlite3
        st = sqlite3.connect(":memory:")
        st.execute("CREATE TABLE sent (uid TEXT, day TEXT, at TEXT, PRIMARY KEY (uid, day))")
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


if __name__ == "__main__":
    unittest.main(verbosity=1)
