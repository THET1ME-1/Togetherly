#!/usr/bin/env python3
"""Сверка widget_data между SQLite PocketBase и Postgres после кат-овера.

Зачем: перенос идёт по rowid, а rowid меняется только на ВСТАВКЕ. Правки,
сделанные в SQLite между массовой копией и переключением маршрута, дельта не
видит — у таких пар в Postgres остаются значения на момент копии (виджет
показывает вчерашний статус, пока человек не тронет его снова). У widget_data
это заметно: строка на пару одна и живёт правками.

Что делает: берёт строки SQLite, чьё `updated` СВЕЖЕЕ, чем в Postgres (или
которых там нет вовсе), и вливает их поверх по ключу (group_id, user_uid) —
именно по нему стоит уникальный индекс, поэтому вставка по id тут не годится.
Идемпотентно, безопасно повторять.

    /opt/hotpath/venv/bin/python reconcile_widget_data.py [--commit]
"""

import argparse
import asyncio
import json
import os
import sqlite3

import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]

COLS = [
    "avatar_url", "data", "display_name", "gender", "group_id", "message",
    "mood_emoji", "mood_label", "music_artist", "music_cover_url", "music_title",
    "music_url", "photo_for_partner_url", "photo_for_partner_urls",
    "photo_grid_count", "photo_grid_urls", "photo_url", "status", "updated_at",
    "user_uid", "updated", "plus",
]
JSON_COLS = {"data", "photo_for_partner_urls", "photo_grid_urls"}
NUM_COLS = {"photo_grid_count"}
BOOL_COLS = {"plus"}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true", help="без флага — только счёт")
    args = ap.parse_args()

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    lite.execute("PRAGMA busy_timeout=30000")
    src = {}
    for row in lite.execute(f"SELECT id, {', '.join(COLS)} FROM widget_data"):
        d = dict(zip(["id"] + COLS, row))
        src[(d["group_id"], d["user_uid"])] = d

    pg = await asyncpg.connect(PG_DSN)
    dst = {(r["group_id"], r["user_uid"]): r["updated"]
           for r in await pg.fetch("SELECT group_id, user_uid, updated FROM widget_data")}

    todo = [d for k, d in src.items()
            if k not in dst or (d["updated"] or "") > (dst[k] or "")]
    print(f"строк в SQLite {len(src)}, в Postgres {len(dst)}, к доливу {len(todo)}")
    if not args.commit:
        print("(прогон без --commit, ничего не записано)")
        await pg.close()
        lite.close()
        return

    set_sql = ", ".join(f"{c} = EXCLUDED.{c}" for c in COLS if c not in ("group_id", "user_uid"))
    ph = ", ".join(f"${i + 1}" for i in range(len(COLS) + 1))
    done = 0
    for d in todo:
        vals = [d["id"]]
        for c in COLS:
            v = d[c]
            if c in JSON_COLS:
                vals.append(v if isinstance(v, str) or v is None else json.dumps(v))
            elif c in NUM_COLS:
                vals.append(float(v or 0))
            elif c in BOOL_COLS:
                vals.append(bool(v))
            else:
                vals.append("" if v is None else str(v))
        await pg.execute(
            f"INSERT INTO widget_data (id, {', '.join(COLS)}) VALUES ({ph}) "
            f"ON CONFLICT (group_id, user_uid) DO UPDATE SET {set_sql}", *vals)
        done += 1
    print(f"долито {done}")
    await pg.close()
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
