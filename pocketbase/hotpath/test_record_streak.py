#!/usr/bin/env python3
"""Рекорд серии маскота пишется в Postgres (переезд маскотов 19.10.2026).

До переезда `_record_activity_pg` писал рекорд только в SQLite PocketBase.
После переезда приложение читает маскотов из Postgres, и рекорд, записанный
по-старому, до телефонов не доехал бы никогда. Здесь проверяется, что рекорд
уходит в обе базы, растёт только вверх и доезжает до пары событием канала.

    python3 test_record_streak.py
"""

import asyncio
from pathlib import Path

источник = (Path(__file__).parent / "hotpath.py").read_text(encoding="utf-8")
начало = источник.index("async def _record_streak(")
конец = источник.index("\nasync def _record_activity_pg(", начало)
провалы = []


def проверить(имя, ok, подробно=""):
    print(("ОК   " if ok else "ПЛОХО") + f" {имя} {'' if ok else подробно}")
    if not ok:
        провалы.append(имя)


class ОшибкаБазы(Exception):
    pass


class asyncpg:  # noqa: N801 (подменяем модуль)
    PostgresError = ОшибкаБазы
    InterfaceError = ОшибкаБазы


class Соединение:
    def __init__(self, ответ, сбой):
        self.ответ, self.сбой, self.запросы = ответ, сбой, []

    async def fetchrow(self, sql, *args):
        self.запросы.append((sql, args))
        if self.сбой:
            raise ОшибкаБазы("нет связи")
        return self.ответ


class Пул:
    def __init__(self, conn):
        self.conn = conn

    def acquire(self):
        conn = self.conn

        class _Ctx:
            async def __aenter__(self):
                return conn

            async def __aexit__(self, *exc):
                return False
        return _Ctx()


def собрать(ответ, сбой=False):
    sqlite, события = [], []

    async def опубликовать(col, event, record):
        события.append((col, event, record))

    conn = Соединение(ответ, сбой)
    пространство = {
        "asyncio": asyncio, "asyncpg": asyncpg, "pg": Пул(conn),
        "now_pb": lambda: "2026-10-19 01:00:00.000Z",
        "_record_streak_sqlite": lambda *a: sqlite.append(a),
        "_record_json": lambda col, row: dict(row),
        "_publish": опубликовать,
    }
    exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)

    async def вызвать():
        await пространство["_record_streak"]("g1", "feya", 12)
        await asyncio.sleep(0)  # рассылка уходит отдельной задачей
    asyncio.run(вызвать())
    return conn, sqlite, события


conn, sqlite, события = собрать({"id": "m1", "record_streak": 12.0})
sql, args = conn.запросы[0]
проверить("рекорд пишется в Postgres", "UPDATE mascots SET record_streak = $1" in sql
          and args[0] == 12.0 and args[2:] == ("g1", "feya"), str(conn.запросы))
проверить("рекорд только растёт", "record_streak < $1" in sql, sql)
проверить("правка двигает updated", "updated = $2" in sql and args[1].endswith("Z"), sql)
проверить("копия остаётся в SQLite для отката", sqlite == [("g1", "feya", 12)], str(sqlite))
проверить("паре уходит событие правки",
          события == [("mascots", "update", {"id": "m1", "record_streak": 12.0})],
          str(события))

_, _, события = собрать(None)
проверить("прежний рекорд выше — события нет", события == [], str(события))

_, sqlite, события = собрать(None, сбой=True)
проверить("сбой базы не роняет зачёт дня", события == [] and len(sqlite) == 1,
          str(события))

print(f"итог: провалов {len(провалы)}" + (f" — {провалы}" if провалы else ""))
raise SystemExit(1 if провалы else 0)
