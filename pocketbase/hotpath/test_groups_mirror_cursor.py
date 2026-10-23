# -*- coding: utf-8 -*-
"""Зеркало пар не теряет строки с одинаковым updated.

Запуск на сервере (нужен Postgres hotpath, данные не трогаются — всё во
временной таблице сессии):
    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python test_groups_mirror_cursor.py [путь к hotpath.py]

Ночной пересчёт счётчиков пишет тысячам пар одну и ту же метку updated.
Выборка «updated > отметка LIMIT 1000» с отметкой по последней строке брала
первую тысячу, а остальные строки с той же меткой не видела никогда (22.10.2026:
4321 пара с updated = 00:41:02.418Z). Тест прогоняет зеркало пачками по 1000 по
1500 строкам с одной меткой и сверяет, что прошли все.
"""
import asyncio
import os
import sys

import asyncpg

путь = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), "hotpath.py")
# Модуль поднимает соединения при импорте, поэтому берём из файла только запрос
# и разбор отметки.
источник = open(путь, encoding="utf-8").read()
начало = источник.index("ЗЕРКАЛО_ЗАПРОС = (")
конец = источник.index("def _прочитать_отметку")
пространство: dict = {}
exec(compile(источник[начало:конец], "зеркало", "exec"), пространство)
запрос = пространство["ЗЕРКАЛО_ЗАПРОС"]
разобрать = пространство["_разобрать_отметку"]

ПРЕЖНИЙ_ЗАПРОС = "SELECT * FROM groups WHERE updated > $1 ORDER BY updated LIMIT $2"
ОДНА_МЕТКА = "2026-10-22 00:41:02.418Z"
ПАЧКА = 1000
ok = True


def проверка(имя: str, условие: bool) -> None:
    global ok
    ok = ok and условие
    print(("  ✓ " if условие else "  ✗ ") + имя)


async def заполнить(c) -> set:
    await c.execute("CREATE TEMP TABLE groups (id text PRIMARY KEY, updated text)")
    await c.execute("CREATE INDEX ON groups (updated)")
    строки = [(f"r{(i * 7919) % 1500:04d}x", ОДНА_МЕТКА) for i in range(1500)]
    строки += [(f"later{i}", f"2026-10-22 01:0{i}:00.000Z") for i in range(5)]
    строки += [(f"early{i}", f"2026-10-21 23:0{i}:00.000Z") for i in range(3)]
    await c.executemany("INSERT INTO groups VALUES ($1, $2)", строки)
    return {gid for gid, upd in строки if upd >= ОДНА_МЕТКА}


async def пройти_новым(c, отметка: str) -> list:
    увидел = []
    for _ in range(20):
        время, ид = разобрать(отметка)
        пачка = await c.fetch(запрос, время, ид, ПАЧКА)
        if not пачка:
            break
        увидел += [r["id"] for r in пачка]
        отметка = f"{пачка[-1]['updated']}\t{пачка[-1]['id']}"
    return увидел


async def пройти_прежним(c, отметка: str) -> list:
    увидел = []
    for _ in range(20):
        пачка = await c.fetch(ПРЕЖНИЙ_ЗАПРОС, отметка, ПАЧКА)
        if not пачка:
            break
        увидел += [r["id"] for r in пачка]
        отметка = пачка[-1]["updated"]
    return увидел


async def main() -> None:
    c = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    try:
        # Таблица живёт только в этой сессии и заслоняет настоящую groups
        ждём = await заполнить(c)
        схема = await c.fetchval(
            "SELECT n.nspname FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace "
            "WHERE t.oid = 'groups'::regclass")
        проверка("запросы идут во временную таблицу, а не в боевую", схема.startswith("pg_temp"))

        прежний = await пройти_прежним(c, "2026-10-21 23:30:00.000Z")
        print(f"    прежняя выборка прошла {len(set(прежний))} из {len(ждём)}")
        проверка("прежняя выборка теряет строки (тест видит поломку)",
                 len(set(прежний)) < len(ждём))

        новый = await пройти_новым(c, "2026-10-21 23:30:00.000Z")
        print(f"    новая выборка прошла {len(set(новый))} из {len(ждём)}")
        проверка("новая выборка проходит все строки", set(новый) == ждём)
        проверка("ни одна строка не взята дважды", len(новый) == len(set(новый)))

        # Отметка, записанная прежним кодом, — одна метка без id
        с_прежней = await пройти_новым(c, ОДНА_МЕТКА)
        проверка("со старой отметкой без id пропуска нет", set(с_прежней) == ждём)
        проверка("разбор старой отметки даёт пустой id", разобрать(ОДНА_МЕТКА) == (ОДНА_МЕТКА, ""))
    finally:
        await c.close()


asyncio.run(main())
print("ВСЁ ВЕРНО" if ok else "ЕСТЬ ОШИБКИ")
sys.exit(0 if ok else 1)
