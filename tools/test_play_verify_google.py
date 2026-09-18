#!/usr/bin/env python3
"""Тесты сверки покупки Google Play: тестовый чек отбивается и гасится.

18.09.2026: бывшая тестировщица не могла купить Togetherly+ настоящей картой,
Play отвечал «You already own this item». Её тестовая покупка от 09.09 так и
числилась купленной: сервер с того дня отбивает тестовые чеки
(`purchaseType == 0`), но в Play её никто не гасил. Разовую покупку, которая
числится за человеком, Play второй раз не продаёт. Непогашенную Google сам
снимает только через трое суток без подтверждения, а её чек подтвердили ещё
до правки, и он висел бы вечно.

Теперь сверка, отбив тестовый чек, сразу гасит его (`:consume`): человек может
купить по-настоящему в ту же минуту. Настоящие покупки не трогаются.

Запуск: python3 tools/test_play_verify_google.py
"""
from __future__ import annotations

import io
import json
import os
import sys
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_verify  # noqa: E402


class Ответ(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Google:
    """Подмена Play Developer API: отвечает на GET чека и пишет вызовы."""

    def __init__(self, покупка: dict, гасить_ошибкой: bool = False):
        self.покупка = покупка
        self.гасить_ошибкой = гасить_ошибкой
        self.вызовы: list[tuple[str, str]] = []

    def __call__(self, req, timeout=None):
        метод = req.get_method()
        self.вызовы.append((метод, req.full_url))
        if req.full_url.endswith(":consume"):
            if self.гасить_ошибкой:
                raise urllib.error.HTTPError(req.full_url, 500, "boom", {}, io.BytesIO(b""))
            return Ответ(b"")
        return Ответ(json.dumps(self.покупка).encode())

    def погашено(self) -> bool:
        return any(u.endswith(":consume") and м == "POST" for м, u in self.вызовы)


def сверить(google: Google, товар: str = "togetherly_plus"):
    with mock.patch.object(play_verify, "access_token", return_value="t"), \
         mock.patch.object(play_verify.urllib.request, "urlopen", google):
        return play_verify.verify(товар, "токен-покупки")


class ТестовыйЧек(unittest.TestCase):
    def test_тестовый_непогашенный_чек_отбит_и_погашен(self):
        g = Google({"purchaseState": 0, "purchaseType": 0, "consumptionState": 0,
                    "orderId": "GPA.3360-5881-4352-36276"})
        итог = сверить(g)
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "test_purchase")
        self.assertTrue(g.погашено(), "тестовый чек должен гаситься, иначе Play не продаст товар снова")
        self.assertTrue(итог.get("consumed"))

    def test_гасится_именно_этот_товар_и_токен(self):
        g = Google({"purchaseState": 0, "purchaseType": 0, "consumptionState": 0})
        сверить(g, "coins_300")
        адрес = [u for м, u in g.вызовы if м == "POST"][0]
        self.assertIn("/purchases/products/coins_300/tokens/", адрес)
        self.assertTrue(адрес.endswith(":consume"))

    def test_уже_погашенный_тестовый_не_трогается(self):
        g = Google({"purchaseState": 0, "purchaseType": 0, "consumptionState": 1})
        итог = сверить(g)
        self.assertEqual(итог["reason"], "test_purchase")
        self.assertFalse(g.погашено())

    def test_сбой_гашения_не_меняет_вердикт(self):
        g = Google({"purchaseState": 0, "purchaseType": 0, "consumptionState": 0}, гасить_ошибкой=True)
        итог = сверить(g)
        self.assertTrue(итог["ok"])
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "test_purchase")
        self.assertFalse(итог.get("consumed"))


class НастоящийЧек(unittest.TestCase):
    def test_настоящая_покупка_принята_и_не_гасится(self):
        g = Google({"purchaseState": 0, "consumptionState": 0, "orderId": "GPA.1"})
        итог = сверить(g)
        self.assertTrue(итог["valid"])
        self.assertFalse(g.погашено(), "настоящую покупку Плюса гасить нельзя: она пропадёт из восстановления")

    def test_промо_код_не_гасится(self):
        g = Google({"purchaseState": 0, "purchaseType": 1, "consumptionState": 0})
        сверить(g)
        self.assertFalse(g.погашено())


def сверить_подписку(google: Google):
    with mock.patch.object(play_verify, "access_token", return_value="t"), \
         mock.patch.object(play_verify.urllib.request, "urlopen", google):
        return play_verify.verify_subscription("токен-подписки", "com.togetherly.money")


class ТестоваяПодписка(unittest.TestCase):
    """Wallet+ — подписка. 18.09.2026 решено: тестировщики получают его из
    базы (`money_plus_testers`), а не покупкой. Тестовую подписку Play отдаёт
    с полем `testPurchase`, и сверка его не смотрела: тестовая карта открывала
    настоящий Wallet+ — та же дыра, что 09.09 у разовых покупок."""

    def test_тестовая_подписка_отбита(self):
        g = Google({"subscriptionState": "SUBSCRIPTION_STATE_ACTIVE", "testPurchase": {},
                    "lineItems": [{"productId": "wallet_plus", "expiryTime": "2026-09-18T12:00:00Z"}]})
        итог = сверить_подписку(g)
        self.assertTrue(итог["ok"])
        self.assertFalse(итог["valid"])
        self.assertEqual(итог["reason"], "test_purchase")

    def test_настоящая_подписка_принята(self):
        g = Google({"subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
                    "lineItems": [{"productId": "wallet_plus", "expiryTime": "2026-10-18T12:00:00Z"}]})
        итог = сверить_подписку(g)
        self.assertTrue(итог["valid"])
        self.assertEqual(итог["expiry"], "2026-10-18T12:00:00Z")


if __name__ == "__main__":
    unittest.main(verbosity=1)
