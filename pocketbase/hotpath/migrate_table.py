#!/usr/bin/env python3
"""Перенос горячей коллекции из SQLite PocketBase в Postgres (hotpath).

Обобщение migrate_strokes.py: колонки и типы берутся из карты TABLES, ход по
rowid, повтор безопасен (ON CONFLICT DO NOTHING), контрольная точка в
/opt/hotpath/.{table}_rowid.

    /opt/hotpath/venv/bin/python migrate_table.py chat_messages
    /opt/hotpath/venv/bin/python migrate_table.py mood_entries --since-rowid N
"""

import argparse
import asyncio
import os
import sqlite3
import time

import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]
BATCH = 20000

# name -> (тип: text|num|bool|json|auto). Порядок колонок и типы должны
# совпадать с COLLECTIONS в hotpath.py.
TABLES = {
    "chat_messages": {
        "color": "num", "deleted": "bool", "edited_ts": "num", "face": "text",
        "face_x": "num", "face_y": "num", "group_id": "text", "pin_id": "text",
        "pin_thumb": "text", "pin_title": "text", "reactions": "json",
        "reply_to_id": "text", "reply_to_name": "text", "reply_to_text": "text",
        "text": "text", "ts": "num", "user_name": "text", "user_uid": "text",
        "updated": "auto", "text_color": "num", "voice_url": "text",
        "voice_ms": "num", "voice_peaks": "text", "voice_heard_at": "num",
    },
    "mood_entries": {
        "group_id": "text", "image_path": "text", "label": "text",
        "mood_id": "text", "timestamp": "text", "user_uid": "text",
        "updated": "auto", "tz": "text",
    },
}


def conv(kind: str, v):
    if kind == "num":
        return float(v or 0)
    if kind == "bool":
        return bool(v)
    if kind == "json":
        return v if (v is None or isinstance(v, str)) else str(v)
    return str(v) if v is not None else ""


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("table", choices=sorted(TABLES))
    ap.add_argument("--since-rowid", type=int, default=0)
    args = ap.parse_args()
    table = args.table
    cols = TABLES[table]
    names = list(cols)
    checkpoint = f"/opt/hotpath/.{table}_rowid"

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    lite.execute("PRAGMA busy_timeout=30000")
    max_rowid = lite.execute(f"SELECT COALESCE(MAX(rowid), 0) FROM {table}").fetchone()[0]

    pg = await asyncpg.connect(PG_DSN)
    stage_cols = ", ".join(
        f"{n} {'text' if cols[n] in ('text', 'json', 'auto') else ('boolean' if cols[n] == 'bool' else 'double precision')}"
        for n in names
    )
    await pg.execute(f"CREATE TEMP TABLE _stage (id text, {stage_cols})")
    cast = ", ".join(f"{n}::jsonb" if cols[n] == "json" else n for n in names)

    moved = 0
    t0 = time.time()
    cursor = args.since_rowid
    sel = f"SELECT rowid, id, {', '.join(names)} FROM {table} WHERE rowid > ? AND rowid <= ? ORDER BY rowid LIMIT ?"
    while True:
        rows = lite.execute(sel, (cursor, max_rowid, BATCH)).fetchall()
        if not rows:
            break
        cursor = rows[-1][0]
        await pg.copy_records_to_table(
            "_stage",
            records=[
                (r[1], *[conv(cols[n], r[i + 2]) for i, n in enumerate(names)])
                for r in rows
            ],
        )
        await pg.execute(
            f"INSERT INTO {table} (id, {', '.join(names)}) "
            f"SELECT id, {cast} FROM _stage ON CONFLICT (id) DO NOTHING"
        )
        await pg.execute("TRUNCATE _stage")
        moved += len(rows)
        print(f"  перенесено {moved} (rowid {cursor}/{max_rowid}), "
              f"{moved / (time.time() - t0):.0f}/с", flush=True)

    sq = lite.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    pgc = await pg.fetchval(f"SELECT COUNT(*) FROM {table}")
    print(f"итого: SQLite {sq}, Postgres {pgc}, контрольная точка rowid={max_rowid}")
    with open(checkpoint, "w") as f:
        f.write(str(max_rowid))
    await pg.close()
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
