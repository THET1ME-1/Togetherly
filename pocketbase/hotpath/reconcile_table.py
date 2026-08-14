#!/usr/bin/env python3
"""Сверка вынесенной коллекции между SQLite PocketBase и Postgres.

Обобщение reconcile_widget_data.py на все коллекции hotpath. Закрывает тот же
зазор: перенос идёт по rowid, а rowid меняется только на ВСТАВКЕ, поэтому
правки, сделанные в SQLite между массовой копией и переключением маршрута, в
Postgres не попадают. Плюс добирает записи, которых там нет вовсе.

Что свежее — решает колонка времени (`updated` или `updated_at`), ключ —
уникальный индекс коллекции (id либо составной). Идемпотентно.

    /opt/hotpath/venv/bin/python reconcile_table.py memories [--commit]
"""

import argparse
import asyncio
import json
import os
import sqlite3
import sys

import asyncpg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_table import TABLES, conv  # noqa: E402  (общая карта колонок)

# Штрихи переезжали первыми, до обобщённого migrate_table — карта колонок для
# них живёт здесь (в migrate_strokes.py она зашита в SQL).
TABLES.setdefault("canvas_strokes", {
    "canvas_id": "text", "data": "json", "deleted": "bool",
    "group_id": "text", "order_index": "num",
})

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]

# колонка времени и ключ конфликта (как в уникальном индексе Postgres)
META = {
    "chat_messages": ("updated", ["id"]),
    "mood_entries": ("updated", ["id"]),
    "memories": ("updated", ["id"]),
    "widget_data": ("updated", ["group_id", "user_uid"]),
    "canvas_meta": ("updated_at", ["group_id", "canvas_id"]),
    "canvas_strokes": (None, ["id"]),   # штрихи не правятся, только id
}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("table", choices=sorted(META))
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()
    table = args.table
    tcol, key = META[table]
    cols = list(TABLES[table]) if table in TABLES else None
    if cols is None:
        print(f"нет карты колонок для {table}")
        return

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    lite.execute("PRAGMA busy_timeout=30000")
    src = {}
    for row in lite.execute(f"SELECT id, {', '.join(cols)} FROM {table}"):
        d = dict(zip(["id"] + cols, row))
        src[tuple(d[k] for k in key)] = d

    pg = await asyncpg.connect(PG_DSN)
    sel = ", ".join(key + ([tcol] if tcol else []))
    dst = {}
    for r in await pg.fetch(f"SELECT {sel} FROM {table}"):
        dst[tuple(r[k] for k in key)] = (r[tcol] if tcol else "")

    todo = [d for k, d in src.items()
            if k not in dst or (tcol and (d.get(tcol) or "") > (dst[k] or ""))]
    print(f"{table}: в SQLite {len(src)}, в Postgres {len(dst)}, к доливу {len(todo)}")
    if not args.commit or not todo:
        if not args.commit:
            print("(прогон без --commit, ничего не записано)")
        await pg.close(); lite.close(); return

    types = TABLES[table]
    upd = ", ".join(f"{c} = EXCLUDED.{c}" for c in cols if c not in key)
    ph = ", ".join(f"${i + 1}" for i in range(len(cols) + 1))
    done = 0
    for d in todo:
        vals = [d["id"]]
        for c in cols:
            v = d[c]
            if types[c] == "json":
                vals.append(v if isinstance(v, str) or v is None else json.dumps(v))
            else:
                vals.append(conv(types[c], v))
        await pg.execute(
            f"INSERT INTO {table} (id, {', '.join(cols)}) VALUES ({ph}) "
            f"ON CONFLICT ({', '.join(key)}) DO UPDATE SET {upd}", *vals)
        done += 1
    print(f"долито {done}")
    await pg.close()
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
