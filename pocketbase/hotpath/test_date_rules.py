# -*- coding: utf-8 -*-
"""Даты пары: повтор, напоминания, тексты — python3 pocketbase/hotpath/test_date_rules.py

Примеры повтора — общий с приложением файл `test/fixtures/date_recurrence_cases.json`
(собирает `make_date_fixtures.py` из dateutil).
"""
import json
import os
import sys
import unittest
from datetime import date, datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))
import date_rules as dr  # noqa: E402

ПРИМЕРЫ = os.path.join(os.path.dirname(__file__), "..", "..", "test", "fixtures",
                       "date_recurrence_cases.json")
КИЕВ = dr.пояс("Europe/Kyiv")
МОСКВА = dr.пояс("Europe/Moscow")
НЬЮ_ЙОРК = dr.пояс("America/New_York")


def utc(*части) -> datetime:
    return datetime(*части, tzinfo=timezone.utc)


class Повтор(unittest.TestCase):
    def test_все_примеры_совпадают(self):
        with open(ПРИМЕРЫ, encoding="utf-8") as f:
            случаи = json.load(f)
        self.assertGreaterEqual(len(случаи), 40)
        for с in случаи:
            дни = dr.повторы(с["start"], с["rrule"], с["exdates"],
                             date.fromisoformat(с["from"]), date.fromisoformat(с["to"]))
            self.assertEqual([d.isoformat() for d in дни], с["dates"], с["name"])

    def test_незнакомое_правило_как_без_повтора(self):
        for текст in ("FREQ=HOURLY", "мусор", "FREQ=YEARLY;BYMONTH=13"):
            дни = dr.повторы("2026-11-08", текст, [], date(2026, 1, 1), date(2030, 1, 1))
            self.assertEqual(дни, [date(2026, 11, 8)], текст)


class Напоминания(unittest.TestCase):
    весь_день = {"day": "2026-10-26", "start_time":"", "tz": "Europe/Kyiv", "rrule": ""}

    def test_в_этот_день_в_9_после_перехода_на_зимнее(self):
        # 25.10.2026 в 04:00 Киев переходит с +3 на +2.
        момент, повтор = dr.следующее(self.весь_день, -540, КИЕВ, utc(2026, 10, 20))
        self.assertEqual(повтор, date(2026, 10, 26))
        self.assertEqual(момент, utc(2026, 10, 26, 7))  # 9:00 по +2

    def test_за_день_в_9_накануне_перехода(self):
        момент, _ = dr.следующее(self.весь_день, 900, КИЕВ, utc(2026, 10, 20))
        self.assertEqual(момент, utc(2026, 10, 25, 7))  # 25.10 уже +2

    def test_за_неделю_в_9_через_переход(self):
        запись = dict(self.весь_день, day="2026-10-30")
        момент, _ = dr.следующее(запись, 9540, КИЕВ, utc(2026, 10, 1))
        self.assertEqual(момент, utc(2026, 10, 23, 6))  # 23.10 ещё +3

    def test_прошедшее_без_повтора_молчит(self):
        запись = dict(self.весь_день, day="2026-01-01")
        self.assertIsNone(dr.следующее(запись, 900, КИЕВ, utc(2026, 11, 28)))

    def test_каждый_год_берёт_следующий_год(self):
        запись = {"day": "2025-11-08", "start_time":"", "tz": "Europe/Moscow", "rrule": "FREQ=YEARLY"}
        момент, повтор = dr.следующее(запись, 900, МОСКВА, utc(2026, 11, 28))
        self.assertEqual(повтор, date(2027, 11, 8))
        self.assertEqual(момент, utc(2027, 11, 7, 6))

    def test_выброшенный_день_пропускается(self):
        запись = {"day": "2026-11-29", "start_time":"", "tz": "Europe/Moscow",
                  "rrule": "FREQ=DAILY", "exdates": ["2026-11-29"]}
        _, повтор = dr.следующее(запись, -540, МОСКВА, utc(2026, 11, 28, 12))
        self.assertEqual(повтор, date(2026, 11, 30))

    def test_со_временем_у_партнёра_в_нью_йорке(self):
        # Концерт 4.12 в 19:00 по Москве = 16:00 UTC; за 30 минут — 15:30 UTC.
        запись = {"day": "2026-12-04", "start_time":"19:00", "tz": "Europe/Moscow", "rrule": ""}
        момент, повтор = dr.следующее(запись, 30, НЬЮ_ЙОРК, utc(2026, 12, 1))
        self.assertEqual(момент, utc(2026, 12, 4, 15, 30))
        self.assertEqual(повтор, date(2026, 12, 4))

    def test_пояс_человека_из_виджета(self):
        self.assertEqual(str(dr.пояс_человека({"tzn": "Europe/Kyiv", "tz": "+02:00"}, None)), "Europe/Kyiv")
        смещение = dr.пояс_человека({"tz": "+05:30"}, None)
        self.assertEqual(смещение.utcoffset(None).total_seconds(), 5.5 * 3600)
        self.assertEqual(str(dr.пояс_человека({}, "America/New_York")), "America/New_York")
        self.assertEqual(str(dr.пояс_человека(None, "мусор")), "Europe/Moscow")


class Тексты(unittest.TestCase):
    def test_весь_день(self):
        запись = {"title": "Первое свидание", "day": "2026-12-01", "start_time":""}
        сейчас = utc(2026, 11, 28, 6)
        for повтор, ru, en in [(date(2026, 11, 28), "Сегодня", "Today"),
                               (date(2026, 11, 29), "Завтра", "Tomorrow"),
                               (date(2026, 12, 1), "Через 3 дня", "In 3 days"),
                               (date(2026, 12, 3), "Через 5 дней", "In 5 days"),
                               (date(2026, 12, 19), "Через 21 день", "In 21 days")]:
            self.assertEqual(dr.текст_напоминания(запись, повтор, МОСКВА, "ru", сейчас),
                             ("Первое свидание", ru))
            self.assertEqual(dr.текст_напоминания(запись, повтор, МОСКВА, "en", сейчас)[1], en)

    def test_со_временем(self):
        запись = {"title": "Концерт", "day": "2026-12-04", "start_time":"19:00", "tz": "Europe/Moscow"}
        повтор = date(2026, 12, 4)
        def текст(сейчас, язык="ru"):
            return dr.текст_напоминания(запись, повтор, МОСКВА, язык, сейчас)[1]
        self.assertEqual(текст(utc(2026, 12, 4, 16)), "Начинается сейчас")
        self.assertEqual(текст(utc(2026, 12, 4, 15, 30)), "Через 30 минут")
        self.assertEqual(текст(utc(2026, 12, 4, 14)), "Через 2 часа")
        self.assertEqual(текст(utc(2026, 12, 4, 6)), "Сегодня в 19:00")
        self.assertEqual(текст(utc(2026, 12, 3, 16)), "Завтра в 19:00")
        self.assertEqual(текст(utc(2026, 12, 1, 16)), "Через 3 дня, в 19:00")
        self.assertEqual(текст(utc(2026, 12, 4, 15, 30), "en"), "In 30 minutes")

    def test_без_названия(self):
        запись = {"title": "  ", "day": "2026-11-28", "start_time":""}
        заголовок, _ = dr.текст_напоминания(запись, date(2026, 11, 28), МОСКВА, "ru", utc(2026, 11, 28, 6))
        self.assertEqual(заголовок, "Наша дата")


if __name__ == "__main__":
    unittest.main(verbosity=1)
