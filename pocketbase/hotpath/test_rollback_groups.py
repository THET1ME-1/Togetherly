#!/usr/bin/env python3
"""Ночной догон пар не держит замок записи SQLite дольше одной пачки.

Разбор 11.10.2026 (обращение 254): `rollback_groups.py` из `reconcile_all.sh`
писал 14 тысяч пар одной транзакцией `BEGIN IMMEDIATE` и держал замок записи
пять с половиной минут, с 03:40:53 до 03:46:19 по Москве. PocketBase всё это
время писать не мог (`database is locked`), а в первые секунды после отпуска
замка застоявшиеся записи пользователей ложились поверх свежих: у четверых
пропал приз сундука, выпавший в 03:45:54–03:46:21 (рамка «Облачко» и три
значка) — запись `chest_opens` есть, во владении пусто.

Тест гоняет настоящую `залить` на временной базе. Второе соединение без
ожидания замка пишет между пачками: получилось — замок отпущен.

Запуск: python3 pocketbase/hotpath/test_rollback_groups.py
"""
import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path

спец = importlib.util.spec_from_file_location(
    "rollback_groups", Path(__file__).parent / "rollback_groups.py")
модуль = importlib.util.module_from_spec(спец)
спец.loader.exec_module(модуль)

ВИДЫ = {"members": "json", "xp": "num", "waiting_mode": "bool", "start_date": "text"}


def пара(ид, xp=0, участники=("a", "b"), ждёт=False, дата="2026-01-01"):
    return {"id": ид, "members": list(участники), "xp": xp,
            "waiting_mode": ждёт, "start_date": дата}


class Догон(unittest.TestCase):
    def setUp(self):
        self.папка = tempfile.TemporaryDirectory()
        self.путь = str(Path(self.папка.name) / "data.db")
        self.lite = sqlite3.connect(self.путь, timeout=0, isolation_level=None)
        self.lite.execute("PRAGMA journal_mode=WAL")
        self.lite.execute(
            "CREATE TABLE groups (id TEXT PRIMARY KEY, members JSON, xp NUMERIC, "
            "waiting_mode BOOLEAN, start_date TEXT)")
        self.lite.execute("CREATE TABLE users (id TEXT PRIMARY KEY, coins NUMERIC)")
        self.lite.execute("INSERT INTO users VALUES ('u', 0)")

    def tearDown(self):
        self.lite.close()
        self.папка.cleanup()

    def положить(self, ид, xp=0, участники='["a","b"]', ждёт=0, дата="2026-01-01"):
        self.lite.execute("INSERT INTO groups VALUES (?, ?, ?, ?, ?)",
                          (ид, участники, xp, ждёт, дата))

    def прочитать(self, ид):
        return self.lite.execute(
            "SELECT members, xp, waiting_mode, start_date FROM groups WHERE id = ?",
            (ид,)).fetchone()

    def test_между_пачками_замок_записи_свободен(self):
        for i in range(5):
            self.положить(f"g{i}")
        чужой = sqlite3.connect(self.путь, timeout=0, isolation_level=None)
        записей = []

        def сосед_пишет():
            # timeout=0: занятый замок даёт ошибку сразу, а не ожидание.
            чужой.execute("UPDATE users SET coins = coins + 1 WHERE id = 'u'")
            записей.append(1)

        try:
            модуль.залить(self.lite, [пара(f"g{i}", xp=7) for i in range(5)], ВИДЫ,
                          пачка=2, между_пачками=сосед_пишет)
        finally:
            чужой.close()
        # Пять строк по две: после первой и второй пачки сосед успел записать.
        self.assertGreaterEqual(len(записей), 2)
        self.assertEqual(self.прочитать("g4")[1], 7)

    def test_совпавшие_строки_не_переписываются(self):
        # Postgres отдаёт json с пробелами, в SQLite он лежит без них.
        self.положить("g0", xp=3)
        self.положить("g1", xp=3)
        до = self.lite.total_changes
        итог = модуль.залить(self.lite, [пара("g0", xp=3), пара("g1", xp=3)], ВИДЫ)
        self.assertEqual(итог, (0, 0, 2))
        self.assertEqual(self.lite.total_changes, до)

    def test_изменённая_обновляется_а_недостающая_добавляется(self):
        self.положить("g0", xp=3)
        итог = модуль.залить(
            self.lite,
            [пара("g0", xp=9, ждёт=True), пара("g1", xp=1, участники=("c",), дата="")],
            ВИДЫ)
        self.assertEqual(итог, (1, 1, 0))
        self.assertEqual(self.прочитать("g0")[1:3], (9, 1))
        self.assertEqual(self.прочитать("g1"), ('["c"]', 1, 0, ""))

    def test_упавшая_пачка_не_оставляет_открытой_транзакции(self):
        self.положить("g0")
        with self.assertRaises(sqlite3.Error):
            модуль.залить(self.lite, [{"id": "g0", "нет_такой": 5}], {"нет_такой": "num"})
        self.assertFalse(self.lite.in_transaction)


if __name__ == "__main__":
    unittest.main(verbosity=2)
