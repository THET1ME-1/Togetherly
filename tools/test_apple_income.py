#!/usr/bin/env python3
"""Тесты сбора App Store.

Что случилось. До 19.10.2026 доход App Store не считался вовсе: не было номера
поставщика, и Tessera показывала магазин «не подключён». Готовый скрипт при
этом посчитал бы покупкой каждую строку отчёта со штуками, а это ещё и
скачивания, повторные загрузки и обновления приложения: сотни в день, все с
нулевой долей. Возвраты он, наоборот, выбрасывал.

Запуск: python3 tools/test_apple_income.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import apple_income as A  # noqa: E402

ШАПКА = ("Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\t"
         "Units\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\t"
         "Currency of Proceeds\tApple Identifier\tCustomer Price")


def ряд(товар: str, тип: str, штук: int, доля: str, валюта: str) -> str:
    return "\t".join(["APPLE", "US", товар, " ", товар, "1.36.0", тип, str(штук), доля,
                      "10/17/2026", "10/17/2026", валюта, "US", валюта, "1", "0.00"])


def отчёт(*ряды: str) -> bytes:
    return ("\n".join([ШАПКА, *ряды]) + "\n").encode()


def плюс(штук: int, доля: str = "8.50", валюта: str = "USD") -> bytes:
    return отчёт(ряд("togetherly-love", "1", 40, "0.00", ""),
                 ряд("togetherly_plus", "IA1", штук, доля, валюта))


# День устроен как в настоящем отчёте, только строк меньше.
ДЕНЬ = отчёт(
    ряд("togetherly-love", "1", 40, "0.00", ""),      # скачивания
    ряд("togetherly-love", "3", 25, "0.00", "USD"),   # повторные загрузки
    ряд("togetherly-love", "7", 200, "0.00", "RUB"),  # обновления
    ряд("togetherly_plus", "IA1", 1, "8.50", "USD"),
    ряд("togetherly_plus", "IA1", 4, "627.05", "RUB"),
)


class Apple:
    """Отдаёт отчёты из словаря, на остальные дни — 404 (пустые байты), как настоящая."""

    def __init__(self, дни: dict, падает_на: str = ""):
        self.дни = дни
        self.падает_на = падает_на
        self.запросы: list = []

    def __call__(self, параметры: dict, доступ_: dict) -> bytes:
        дата = параметры["reportDate"]
        self.запросы.append(дата)
        if дата == self.падает_на:
            raise OSError("HTTP Error 503: Service Unavailable")
        return self.дни.get(дата, b"")


class РазборОтчёта(unittest.TestCase):
    def test_скачивания_и_обновления_не_покупки(self):
        self.assertEqual(A.покупки_дня(ДЕНЬ), [["togetherly_plus", 1, 8.5, "USD"],
                                               ["togetherly_plus", 4, 627.05, "RUB"]])

    def test_доля_умножается_на_штуки_и_переводится_в_доллары(self):
        usd, товары = A.в_доллары([["togetherly_plus", 4, 627.05, "RUB"]], {"USD": 1.0, "RUB": 80.0})
        self.assertAlmostEqual(usd, 31.3525)
        self.assertEqual(товары["togetherly_plus"]["count"], 4)

    def test_возврат_вычитается(self):
        usd, товары = A.в_доллары([["togetherly_plus", 1, 7.0, "USD"],
                                   ["togetherly_plus", -1, 7.0, "USD"]], {"USD": 1.0})
        self.assertEqual(usd, 0)
        self.assertEqual(товары["togetherly_plus"]["count"], 0)


class Сбор(unittest.TestCase):
    СЕГОДНЯ = date(2026, 10, 3)

    def setUp(self):
        self.папка = tempfile.mkdtemp()
        self.кэш = os.path.join(self.папка, "days.json")
        self.прежнее = (A.отчёт, A.доступ, A.курсы, A.НАЧАЛО, A.OUT_PATH)
        A.доступ = lambda: {"issuer": "i", "key_id": "k", "key_path": "p", "vendor": "1"}
        A.курсы = lambda: {"USD": 1.0, "RUB": 80.0}
        A.НАЧАЛО = date(2026, 9, 28)
        A.OUT_PATH = os.path.join(self.папка, "out.json")

    def tearDown(self):
        A.отчёт, A.доступ, A.курсы, A.НАЧАЛО, A.OUT_PATH = self.прежнее

    def собрать(self, apple: Apple) -> dict:
        A.отчёт = apple
        return A.собрать(сегодня=self.СЕГОДНЯ, кэш_путь=self.кэш)

    def test_второй_раз_качаются_только_новые_дни(self):
        все = {f"2026-{д}": плюс(1) for д in ("09-28", "09-29", "09-30", "10-01", "10-02")}
        первый = Apple(все)
        self.собрать(первый)
        self.assertEqual(len(первый.запросы), 5)
        второй = Apple(все)
        self.собрать(второй)
        self.assertEqual(второй.запросы, [])

    def test_пустой_старый_день_забывается_а_вчерашний_спрашивается_снова(self):
        # 28.09 отчёта нет и через пять суток — продаж не было. 02.10 Apple
        # ещё не выложила: его спросим в следующий час.
        дни = {"2026-09-29": плюс(1), "2026-09-30": плюс(1), "2026-10-01": плюс(1)}
        self.собрать(Apple(дни))
        второй = Apple(дни)
        self.собрать(второй)
        self.assertEqual(второй.запросы, ["2026-10-02"])

    def test_месяц_прошлый_месяц_вчера_и_покупки(self):
        итог = self.собрать(Apple({
            "2026-09-29": плюс(1),
            "2026-10-01": плюс(2),
            "2026-10-02": плюс(-1),
        }))
        self.assertTrue(итог["ok"])
        self.assertEqual(итог["prev_month"], 8.5)
        self.assertEqual(итог["month"], 8.5)
        self.assertEqual(итог["yesterday"], -8.5)
        self.assertEqual(итог["today"], 0.0)
        self.assertEqual(итог["purchases"], [{"name": "togetherly_plus", "count": 1, "usd": 8.5}])
        self.assertEqual(итог["months"], {"2026-09": {"usd": 8.5, "count": 1},
                                          "2026-10": {"usd": 8.5, "count": 1}})
        self.assertEqual([д["d"] for д in итог["days"]], ["2026-09-29", "2026-10-01", "2026-10-02"])

    def test_сбой_apple_не_теряет_скачанное_и_виден_в_заметке(self):
        дни = {"2026-09-28": плюс(1), "2026-09-29": плюс(1)}
        итог = self.собрать(Apple(дни, падает_на="2026-09-30"))
        self.assertTrue(итог["ok"])
        self.assertEqual(итог["prev_month"], 17.0)
        self.assertIn("503", итог["note"])
        with open(self.кэш, encoding="utf-8") as f:
            self.assertEqual(sorted(json.load(f)), ["2026-09-28", "2026-09-29"])

    def test_сбой_сбора_не_стирает_прошлую_сводку(self):
        with open(A.OUT_PATH, "w", encoding="ascii") as f:
            f.write('{"ok": true, "month": 100.0}')

        def упал(**_):
            raise OSError("курсы не отвечают")

        прежний = A.собрать
        A.собрать = упал
        try:
            self.assertEqual(A.main(), 1)
        finally:
            A.собрать = прежний
        with open(A.OUT_PATH, encoding="ascii") as f:
            self.assertEqual(json.load(f), {"ok": True, "month": 100.0})


if __name__ == "__main__":
    unittest.main(verbosity=2)
