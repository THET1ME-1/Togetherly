#!/usr/bin/env python3
"""Выполнить SQL-файл в Postgres тем же доступом, каким живёт hotpath.

Нужен, чтобы владелец новых таблиц совпадал с уже переехавшими, и чтобы
кавычки в SQL не съедала оболочка по дороге через ssh.

    /opt/hotpath/venv/bin/python apply_sql.py groups_table.sql
"""

import asyncio
import os
import sys

import asyncpg


async def main() -> None:
    if len(sys.argv) < 2:
        print("укажи файл с SQL")
        return
    with open(sys.argv[1], encoding="utf-8") as f:
        sql = f.read()
    pg = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    try:
        await pg.execute(sql)
        print(f"выполнено: {sys.argv[1]}")
        row = await pg.fetchrow(
            "select current_user as кто, "
            "(select count(*) from information_schema.columns "
            " where table_name = 'groups') as колонок")
        print(f"пользователь {row['кто']}, колонок в groups: {row['колонок']}")
    finally:
        await pg.close()


if __name__ == "__main__":
    asyncio.run(main())
