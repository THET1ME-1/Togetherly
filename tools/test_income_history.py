#!/usr/bin/env python3
"""Тесты архива дохода по месяцам: реклама Яндекса.

Что случилось. В октябре 2026 РСЯ стала отвечать 400 «Очень большой период» на
любой запрос длиннее восьми дней. Архив просил всю историю одним запросом,
получал отказ и молча писал Яндексу ноль за КАЖДЫЙ месяц, включая давно
закрытые: в таблице пропал главный источник дохода, а ошибки не было нигде.

Запуск: python3 tools/test_income_history.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import income_history as H  # noqa: E402

СЕГОДНЯ = date(2026, 10, 14)


class Яндекс:
    """Строгий, как настоящий: длинный период не отдаёт, короткий — доллар в день."""

    def __init__(self, лежит: bool = False, пусто_до: str = ""):
        self.запросы: list = []
        self.лежит = лежит
        self.пусто_до = пусто_до

    def __call__(self, a: str, b: str):
        self.запросы.append((a, b))
        дней = (date.fromisoformat(b) - date.fromisoformat(a)).days + 1
        if self.лежит or not 1 <= дней <= 8:
            raise OSError("HTTP Error 400: Очень большой период")
        if b < self.пусто_до:
            return 0.0, 0
        return float(дней), дней * 100


class АрхивЯндекса(unittest.TestCase):
    def setUp(self):
        self.кэш = os.path.join(tempfile.mkdtemp(), "rsya.json")
        self._since = H.SINCE
        H.SINCE = "2026-07-01"

    def tearDown(self):
        H.SINCE = self._since

    def собрать(self, яндекс, сегодня: date = СЕГОДНЯ) -> dict:
        return H.rsya_months(ask=яндекс, today=сегодня, cache_path=self.кэш)

    def test_месяц_складывается_из_окон_целиком(self):
        out = self.собрать(Яндекс())
        self.assertEqual(out["2026-07"], {"usd": 31.0, "shows": 3100})
        self.assertEqual(out["2026-09"], {"usd": 30.0, "shows": 3000})
        self.assertEqual(out["2026-10"], {"usd": 14.0, "shows": 1400})

    def test_ни_один_запрос_не_длиннее_семи_дней(self):
        яндекс = Яндекс()
        self.собрать(яндекс)
        self.assertTrue(яндекс.запросы)
        for a, b in яндекс.запросы:
            self.assertLessEqual((date.fromisoformat(b) - date.fromisoformat(a)).days + 1, 7, (a, b))

    def test_окна_покрывают_каждый_день_один_раз_и_не_выходят_из_месяца(self):
        яндекс = Яндекс()
        self.собрать(яндекс)
        дни = []
        for a, b in яндекс.запросы:
            self.assertEqual(a[:7], b[:7], (a, b))
            d = date.fromisoformat(a)
            while d <= date.fromisoformat(b):
                дни.append(d)
                d += timedelta(days=1)
        ждём = [date(2026, 7, 1) + timedelta(days=n) for n in range((СЕГОДНЯ - date(2026, 7, 1)).days + 1)]
        self.assertEqual(sorted(дни), ждём)

    def test_закрытые_месяцы_второй_раз_не_запрашиваются(self):
        self.собрать(Яндекс())
        яндекс = Яндекс()
        out = self.собрать(яндекс)
        self.assertEqual({a[:7] for a, _ in яндекс.запросы}, {"2026-09", "2026-10"})
        self.assertEqual(out["2026-07"]["usd"], 31.0)

    def test_отказ_Яндекса_не_обнуляет_посчитанное(self):
        было = self.собрать(Яндекс())
        стало = self.собрать(Яндекс(лежит=True))
        self.assertEqual(стало, было)

    def test_отказ_без_прежних_данных_месяц_пропускает_а_не_пишет_ноль(self):
        self.assertEqual(self.собрать(Яндекс(лежит=True)), {})

    def test_месяцы_до_начала_рекламы_в_архив_не_попадают(self):
        out = self.собрать(Яндекс(пусто_до="2026-09-01"))
        self.assertEqual(sorted(out), ["2026-09", "2026-10"])

    def test_пустой_закрытый_месяц_тоже_запоминается(self):
        self.собрать(Яндекс(пусто_до="2026-09-01"))
        яндекс = Яндекс()
        self.собрать(яндекс)
        self.assertNotIn("2026-07", {a[:7] for a, _ in яндекс.запросы})

    def test_первого_числа_прошлый_месяц_ещё_пересчитывается(self):
        self.собрать(Яндекс(), date(2026, 10, 31))
        яндекс = Яндекс()
        out = self.собрать(яндекс, date(2026, 11, 1))
        self.assertEqual({a[:7] for a, _ in яндекс.запросы}, {"2026-10", "2026-11"})
        self.assertEqual(out["2026-11"], {"usd": 1.0, "shows": 100})

    def test_кэш_лежит_обычным_json(self):
        self.собрать(Яндекс())
        self.assertEqual(json.load(open(self.кэш, encoding="utf-8"))["2026-08"], {"usd": 31.0, "shows": 3100})


if __name__ == "__main__":
    unittest.main(verbosity=2)
