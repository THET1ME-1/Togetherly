#!/usr/bin/env python3
"""Откат canvas_strokes: долить в SQLite PocketBase то, что появилось в Postgres
после переключения маршрута. Запускать ПОСЛЕ возврата маршрута в Caddy на PB.

Сравнивает множества id (у штрихов нет отметок времени, диффа по дате не
построить), недостающее вставляет прямо в SQLite с busy_timeout. Правки
существующих штрихов (patchStroke) откат не переносит — они редки, а последняя
версия остаётся в Postgres.

    /opt/hotpath/venv/bin/python /opt/hotpath/rollback_strokes.py [--commit]
"""

import argparse
import asyncio
import json
import os
import sqlite3

import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true", help="без флага — только счёт")
    args = ap.parse_args()

    pg = await asyncpg.connect(PG_DSN)
    pg_ids = {r["id"] for r in await pg.fetch("SELECT id FROM canvas_strokes")}

    lite = sqlite3.connect(SQLITE, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    lite_ids = {r[0] for r in lite.execute("SELECT id FROM canvas_strokes")}

    missing = pg_ids - lite_ids
    print(f"в PG {len(pg_ids)}, в SQLite {len(lite_ids)}, долить: {len(missing)}")
    if not args.commit:
        print("(прогон без --commit, ничего не записано)")
        return

    moved = 0
    for chunk_start in range(0, len(missing), 1000):
        chunk = list(missing)[chunk_start:chunk_start + 1000]
        rows = await pg.fetch(
            "SELECT id, canvas_id, group_id, order_index, deleted, data "
            "FROM canvas_strokes WHERE id = ANY($1)", chunk,
        )
        lite.executemany(
            "INSERT OR IGNORE INTO canvas_strokes "
            "(id, canvas_id, group_id, order_index, deleted, data) VALUES (?,?,?,?,?,?)",
            [
                (r["id"], r["canvas_id"], r["group_id"], r["order_index"],
                 1 if r["deleted"] else 0,
                 r["data"] if isinstance(r["data"], str) else json.dumps(r["data"]))
                for r in rows
            ],
        )
        lite.commit()
        moved += len(rows)
        print(f"  долито {moved}/{len(missing)}", flush=True)
    await pg.close()
    lite.close()
    print("готово")


if __name__ == "__main__":
    asyncio.run(main())
