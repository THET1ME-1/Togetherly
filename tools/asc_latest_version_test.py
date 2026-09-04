#!/usr/bin/env python3
"""Проверки выбора самой свежей версии App Store.

Запуск: `python3 tools/asc_latest_version_test.py`
"""

import unittest

from asc_latest_version import latest_id


def версия(vid: str, created: str, state: str = "READY_FOR_SALE") -> dict:
    return {
        "id": vid,
        "attributes": {"createdDate": created, "appStoreState": state},
    }


class LatestId(unittest.TestCase):
    def test_берёт_самую_свежую_по_дате(self):
        # Порядок в ответе Apple не гарантирован, а `sort` этот запрос не
        # принимает вовсе («The parameter 'sort' can not be used»).
        data = [
            версия("старая", "2026-08-20T03:03:36-07:00"),
            версия("свежая", "2026-09-04T03:15:09-07:00"),
            версия("средняя", "2026-09-01T12:01:03-07:00"),
        ]
        self.assertEqual(latest_id(data), "свежая")

    def test_на_пустом_списке_молчит(self):
        # Первый релиз приложения: версии ещё нет, и заметки уходят одной
        # основной локали — так же, как раньше.
        self.assertEqual(latest_id([]), "")

    def test_принимает_одиночную_версию_объектом(self):
        self.assertEqual(latest_id(версия("одна", "2026-09-04T03:15:09-07:00")), "одна")

    def test_сравнивает_моменты_а_не_строки(self):
        # Смещение у Apple приезжает то -07:00, то Z: посимвольно
        # «2026-09-04T03:15-07:00» (это 10:15 UTC) выглядит старше, чем
        # «2026-09-04T09:00Z», хотя случилось позже.
        data = [
            версия("тихоокеанская", "2026-09-04T03:15:09-07:00"),
            версия("утренняя", "2026-09-04T09:00:00Z"),
        ]
        self.assertEqual(latest_id(data), "тихоокеанская")

    def test_версия_без_даты_не_роняет_разбор(self):
        data = [{"id": "безДаты", "attributes": {}}, версия("сдатой", "2026-09-01T12:01:03-07:00")]
        self.assertEqual(latest_id(data), "сдатой")


if __name__ == "__main__":
    unittest.main()
