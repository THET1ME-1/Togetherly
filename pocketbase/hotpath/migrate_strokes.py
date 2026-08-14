#!/usr/bin/env python3
"""Перенос canvas_strokes из SQLite PocketBase в Postgres (hotpath).

Идёт по rowid, поэтому перенос повторяемый: первый прогон тащит всё, после
переключения маршрута в Caddy второй прогон с `--since-rowid <N>` доливает то,
что успело записаться в PB между копией и переключением. Контрольная точка
(MAX(rowid) на момент старта) печатается в конце и пишется в
/opt/hotpath/.strokes_rowid.

Заливка — COPY во временную таблицу и INSERT ... ON CONFLICT (id) DO NOTHING:
повтор безопасен, уже перенесённые строки не трогаются.

Запуск на VPS:
    /opt/hotpath/venv/bin/python /opt/hotpath/migrate_strokes.py
    /opt/hotpath/venv/bin/python /opt/hotpath/migrate_strokes.py --since-rowid 1234567
"""

import argparse
import asyncio
import os
import sqlite3
import time

import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]
CHECKPOINT = "/opt/hotpath/.strokes_rowid"
BATCH = 20000


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since-rowid", type=int, default=0)
    args = ap.parse_args()

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    lite.execute("PRAGMA busy_timeout=30000")
    max_rowid = lite.execute("SELECT COALESCE(MAX(rowid), 0) FROM canvas_strokes").fetchone()[0]

    pg = await asyncpg.connect(PG_DSN)
    await pg.execute(
        """CREATE TEMP TABLE _stage
           (id text, canvas_id text, group_id text,
            order_index double precision, deleted boolean, data text)"""
    )

    moved = 0
    t0 = time.time()
    cursor = args.since_rowid
    while True:
        rows = lite.execute(
            "SELECT rowid, id, canvas_id, group_id, order_index, deleted, data "
            "FROM canvas_strokes WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?",
            (cursor, max_rowid, BATCH),
        ).fetchall()
        if not rows:
            break
        cursor = rows[-1][0]
        await pg.copy_records_to_table(
            "_stage",
            records=[
                (r[1], r[2] or "", r[3] or "", float(r[4] or 0), bool(r[5]), r[6])
                for r in rows
            ],
        )
        await pg.execute(
            """INSERT INTO canvas_strokes (id, canvas_id, group_id, order_index, deleted, data)
               SELECT id, canvas_id, group_id, order_index, deleted, data::jsonb
               FROM _stage ON CONFLICT (id) DO NOTHING"""
        )
        await pg.execute("TRUNCATE _stage")
        moved += len(rows)
        print(f"  перенесено {moved} (rowid {cursor}/{max_rowid}), "
              f"{moved / (time.time() - t0):.0f}/с", flush=True)

    sq = lite.execute("SELECT COUNT(*) FROM canvas_strokes").fetchone()[0]
    pgc = await pg.fetchval("SELECT COUNT(*) FROM canvas_strokes")
    print(f"итого: SQLite {sq}, Postgres {pgc}, контрольная точка rowid={max_rowid}")
    with open(CHECKPOINT, "w") as f:
        f.write(str(max_rowid))
    await pg.close()
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
