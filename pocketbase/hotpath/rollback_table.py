#!/usr/bin/env python3
"""Откат вынесенной коллекции: вернуть в SQLite PocketBase то, что изменилось
в Postgres после переключения маршрута. Запускать ПОСЛЕ возврата маршрута в
Caddy на PocketBase.

Новые записи и правки берутся по колонке updated (строки свежее --since).
Удаления — по множеству id: строка есть в SQLite, но пропала из Postgres.
После полного переноса так бывает только при удалении, поэтому они идут
отдельным флагом --deletions. Пишет пачками по сто строк: длинная транзакция
заняла бы единственного писателя PocketBase.

    /opt/hotpath/venv/bin/python rollback_table.py mascots \
        --since '2026-10-19 00:00:00' [--deletions] [--commit]
"""

import argparse
import asyncio
import json
import os
import sqlite3
import sys

import asyncpg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_table import TABLES  # noqa: E402  (общая карта колонок)

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]
BATCH = 100


def to_lite(kind: str, value):
    if kind == "json":
        if value is None:
            return None
        return value if isinstance(value, str) else json.dumps(value)
    if kind == "bool":
        return 1 if value else 0
    return value


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("table", choices=["love_tests", "mascots"])
    ap.add_argument("--since", required=True, help="UTC, как в колонке updated")
    ap.add_argument("--deletions", action="store_true", help="удалить в SQLite пропавшие из Postgres")
    ap.add_argument("--commit", action="store_true", help="без флага — только счёт")
    args = ap.parse_args()
    table = args.table
    kinds = TABLES[table]
    cols = list(kinds)

    pg = await asyncpg.connect(PG_DSN)
    changed = await pg.fetch(
        f"SELECT id, {', '.join(cols)} FROM {table} WHERE updated >= $1", args.since)
    pg_ids = {r["id"] for r in await pg.fetch(f"SELECT id FROM {table}")}
    await pg.close()

    lite = sqlite3.connect(SQLITE, timeout=60, isolation_level=None)
    lite.execute("PRAGMA busy_timeout=60000")
    lite_ids = {r[0] for r in lite.execute(f"SELECT id FROM {table}")}
    has_created = any(r[1] == "created" for r in lite.execute(f"PRAGMA table_info({table})"))
    gone = sorted(lite_ids - pg_ids) if args.deletions else []
    print(f"{table}: изменено в Postgres с {args.since}: {len(changed)}, "
          f"удалить в SQLite: {len(gone)} (флаг удалений {'есть' if args.deletions else 'нет'})")
    if not args.commit:
        print("(прогон без --commit, ничего не записано)")
        return

    names = ["id"] + cols + (["created"] if has_created else [])
    placeholders = ", ".join("?" for _ in names)
    updates = ", ".join(f"{c} = excluded.{c}" for c in cols)
    sql = (f"INSERT INTO {table} ({', '.join(names)}) VALUES ({placeholders}) "
           f"ON CONFLICT(id) DO UPDATE SET {updates}")
    for start in range(0, len(changed), BATCH):
        lite.execute("BEGIN IMMEDIATE")
        for row in changed[start:start + BATCH]:
            values = [row["id"]] + [to_lite(kinds[c], row[c]) for c in cols]
            if has_created:
                values.append(row["updated"])
            lite.execute(sql, values)
        lite.execute("COMMIT")
    for start in range(0, len(gone), BATCH):
        chunk = gone[start:start + BATCH]
        lite.execute("BEGIN IMMEDIATE")
        lite.execute(f"DELETE FROM {table} WHERE id IN ({', '.join('?' for _ in chunk)})", chunk)
        lite.execute("COMMIT")
    lite.close()
    print(f"вернул в SQLite: {len(changed)}, удалил: {len(gone)}")


if __name__ == "__main__":
    asyncio.run(main())
