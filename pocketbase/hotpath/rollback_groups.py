#!/usr/bin/env python3
"""Реверс-долив пар: Postgres → SQLite PocketBase.

Нужен для отката переезда. Порядок отката целиком:
  1) вернуть блоки маршрутов в /etc/caddy/Caddyfile и `systemctl reload caddy`;
  2) вернуть хуки из копий `*.bak-before-pg` (PocketBase перечитает их сам);
  3) снять HOTPATH_GROUPS=pg в /opt/hotpath/env и перезапустить hotpath;
  4) прогнать этот скрипт с --commit — он вернёт в SQLite всё, что успело
     измениться в Postgres, пока пары жили там.

Строки не удаляются никогда: скрипт только обновляет и добавляет.

    /opt/hotpath/venv/bin/python rollback_groups.py --since "2026-08-15 00:00:00" --commit
    /opt/hotpath/venv/bin/python rollback_groups.py --all --commit
"""

import argparse
import asyncio
import json
import os
import sqlite3
import sys

import asyncpg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_table import TABLES  # noqa: E402

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]
КОЛОНКИ = list(TABLES["groups"])


def привести(kind: str, v):
    if kind == "json":
        if v is None:
            return None
        return v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    if kind == "bool":
        return 1 if v else 0
    if kind == "num":
        return float(v or 0)
    return v if v is not None else ""


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="", help="только правленные после этого времени")
    ap.add_argument("--all", action="store_true", help="все пары целиком")
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()
    if not args.since and not args.all:
        print("укажи --since '<время>' или --all")
        return

    pg = await asyncpg.connect(PG_DSN)
    поля = ", ".join(КОЛОНКИ)
    if args.all:
        строки = await pg.fetch(f"SELECT id, {поля} FROM groups")
    else:
        строки = await pg.fetch(
            f"SELECT id, {поля} FROM groups WHERE updated > $1", args.since)
    await pg.close()
    print(f"в Postgres к возврату: {len(строки)}")
    if not args.commit:
        print("(прогон без --commit, ничего не записано)")
        return

    lite = sqlite3.connect(SQLITE, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    места = ", ".join("?" * (len(КОЛОНКИ) + 1))
    назначения = ", ".join(f"`{c}` = ?" for c in КОЛОНКИ)
    обновлено = добавлено = 0
    lite.execute("BEGIN IMMEDIATE")
    try:
        for row in строки:
            значения = [привести(TABLES["groups"][c], row[c]) for c in КОЛОНКИ]
            cur = lite.execute(
                f"UPDATE `groups` SET {назначения} WHERE id = ?",
                (*значения, row["id"]))
            if cur.rowcount:
                обновлено += 1
            else:
                lite.execute(
                    f"INSERT INTO `groups` (id, {', '.join(f'`{c}`' for c in КОЛОНКИ)}) "
                    f"VALUES ({места})", (row["id"], *значения))
                добавлено += 1
        lite.commit()
    except BaseException:
        lite.rollback()
        raise
    finally:
        lite.close()
    print(f"в SQLite обновлено {обновлено}, добавлено {добавлено}")


if __name__ == "__main__":
    asyncio.run(main())
