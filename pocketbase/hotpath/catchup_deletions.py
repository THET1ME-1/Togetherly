#!/usr/bin/env python3
"""Догон удалений после переключения маршрута (переезд 19.10.2026).

Массовый перенос копирует строки заранее. Запись, удалённая в SQLite между
переносом и переключением маршрута, осталась бы в Postgres и вернулась бы к
людям. Скрипт удаляет из Postgres строки, которых нет в SQLite, но только
старше момента переключения: всё новее заведено уже в Postgres.

    /opt/hotpath/venv/bin/python catchup_deletions.py mascots \
        --before '2026-10-19 00:30:00' [--commit]
"""

import argparse
import asyncio
import os
import sqlite3

import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("table", choices=["love_tests", "mascots", "cycle_entries",
                                      "wishes", "wish_categories"])
    ap.add_argument("--before", required=True,
                    help="момент переключения, UTC, как в колонке updated")
    ap.add_argument("--commit", action="store_true", help="без флага — только счёт")
    args = ap.parse_args()
    table = args.table

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    lite.execute("PRAGMA busy_timeout=30000")
    lite_ids = {r[0] for r in lite.execute(f"SELECT id FROM {table}")}
    lite.close()

    pg = await asyncpg.connect(PG_DSN)
    rows = await pg.fetch(f"SELECT id FROM {table} WHERE updated < $1", args.before)
    gone = [r["id"] for r in rows if r["id"] not in lite_ids]
    print(f"{table}: в Postgres старше {args.before} и нет в SQLite: {len(gone)}")
    if not args.commit:
        print("(прогон без --commit, ничего не удалено)")
    elif gone:
        status = await pg.execute(
            f"DELETE FROM {table} WHERE id = ANY($1::text[]) AND updated < $2",
            gone, args.before)
        print(f"удалено: {status}")
    await pg.close()


if __name__ == "__main__":
    asyncio.run(main())
