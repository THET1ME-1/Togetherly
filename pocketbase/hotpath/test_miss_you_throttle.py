#!/usr/bin/env python3
"""Серия нажатий «Скучаю» не превращается в лавину уведомлений.

Жалоба 16.08.2026: «если подряд много раз жать, уведомления идут без
остановки». Клиент копит нажатия и шлёт их пачками по двадцать — на каждую
пачку уходило отдельное уведомление, и партнёр получал их десятками.

Счёт при этом прибавляется весь, до единого нажатия: глушится только шум в
шторке, не сам импульс.

Запуск: python3 pocketbase/hotpath/test_miss_you_throttle.py
"""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")

пространство: dict = {}
начало = источник.index("_МОЛЧАНИЕ_MISS_MS")
конец = источник.index("\ndef _miss_you_push_text(")
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
_пора = пространство["_пора_слать_miss"]
ОКНО = пространство["_МОЛЧАНИЕ_MISS_MS"]


class Антидребезг(unittest.TestCase):
    def setUp(self):
        пространство["_последний_miss"].clear()

    def test_первое_нажатие_шлём(self):
        self.assertTrue(_пора("пара", 1_000_000))

    def test_серия_пачек_даёт_одно_уведомление(self):
        t = 1_000_000
        отправлено = sum(1 for i in range(10) if _пора("пара", t + i * 600))
        self.assertEqual(отправлено, 1, "десять пачек — одно уведомление")

    def test_через_минуту_снова_шлём(self):
        t = 1_000_000
        self.assertTrue(_пора("пара", t))
        self.assertTrue(_пора("пара", t + ОКНО + 1))

    def test_у_каждой_пары_своя_тишина(self):
        t = 1_000_000
        self.assertTrue(_пора("первая", t))
        self.assertTrue(_пора("вторая", t),
                        "чужая пара не должна молчать из-за соседей")

    def test_карта_не_растёт_без_края(self):
        t = 1_000_000
        for i in range(20_100):
            _пора(f"пара{i}", t)
        # Спустя окно тишины давние записи вычищаются следующей же отправкой.
        _пора("ещё одна", t + ОКНО + 1)
        self.assertLess(len(пространство["_последний_miss"]), 20_100)


if __name__ == "__main__":
    unittest.main(verbosity=2)
