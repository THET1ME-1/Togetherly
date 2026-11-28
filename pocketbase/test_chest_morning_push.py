"""Правило отбора утреннего пуша сундука: python3 pocketbase/test_chest_morning_push.py"""
import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(__file__))
import chest_morning_push as m  # noqa: E402


def user(**kw):
    base = {"fcm_token": "t", "apns_token": "", "notif_chest_off": 0, "notif_synced_at": ""}
    base.update(kw)
    return base


class Отбор(unittest.TestCase):
    def test_обычный_человек_получает(self):
        self.assertTrue(m.wants_push(user(), False, False))

    def test_без_токена_некуда(self):
        self.assertFalse(m.wants_push(user(fcm_token=""), False, False))

    def test_выключил_тумблер(self):
        self.assertFalse(m.wants_push(user(notif_chest_off=1), False, False))

    def test_старая_сборка_с_нулём_получает(self):
        # Колонка перевёрнута: ноль у тех, кто про неё не знает, значит «присылать».
        self.assertTrue(m.wants_push(user(notif_chest_off=0), False, False))

    def test_выключил_все_уведомления(self):
        u = user(notif_synced_at="2026-10-01", **{f: 0 for f in m.NOTIF_FIELDS})
        self.assertFalse(m.wants_push(u, False, False))

    def test_нули_без_метки_не_выбор(self):
        u = user(**{f: 0 for f in m.NOTIF_FIELDS})
        self.assertTrue(m.wants_push(u, False, False))

    def test_уже_открыл_или_уже_получил(self):
        self.assertFalse(m.wants_push(user(), True, False))
        self.assertFalse(m.wants_push(user(), False, True))


class Пояс(unittest.TestCase):
    def test_разбор(self):
        self.assertEqual(m.tz_minutes("+03:00"), 180)
        self.assertEqual(m.tz_minutes("-05:30"), -330)
        self.assertIsNone(m.tz_minutes(""))
        self.assertIsNone(m.tz_minutes("+99:00"))

    def test_утро_у_каждого_своё(self):
        utc = datetime(2026, 10, 3, 7, 5, tzinfo=timezone.utc)
        self.assertEqual(m.local_now(utc, 180).hour, 10)   # Москва
        self.assertEqual(m.local_now(utc, 420).hour, 14)   # Новосибирск


class Обложка(unittest.TestCase):
    """Уведомления «А» (28.11.2026): иконка приложения, сундук в развёрнутом."""

    def test_новая_сборка_android_данными(self):
        u = {"id": "u1", "apns_token": "a", "fcm_token": "f", "lang": "ru", "notif_v": 1}
        apns, fcm = m.relay_bodies(u, look=lambda _id: (["still_c.png"], {}))
        self.assertEqual(apns["cover"]["kind"], "chest")
        self.assertEqual(apns["cover"]["art"], {"app": True})
        self.assertTrue(fcm["data_only"])

    def test_старая_сборка_по_старому(self):
        u = {"id": "u1", "fcm_token": "f", "lang": "en", "notif_v": 0}
        _apns, fcm = m.relay_bodies(u, look=lambda _id: None)
        self.assertNotIn("cover", fcm)
        self.assertEqual(fcm["title"], m.text_for(m.TITLE, "en"))


if __name__ == "__main__":
    unittest.main()
