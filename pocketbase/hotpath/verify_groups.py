#!/usr/bin/env python3
"""Построчная сверка groups: SQLite PocketBase против Postgres.

Считать строки бесполезно — у пары строка одна и живёт правками, поэтому
сверяется ЗНАЧЕНИЕ каждого поля у каждой пары. Разница типов между базами
учтена: json сравнивается разобранным (в jsonb порядок ключей свой), пустая
строка json равна NULL, пустой текст равен NULL, число без значения равно нулю.

Строки, изменённые в SQLite ПОСЛЕ снимка (по колонке updated), из сверки не
выкидываются, а показываются отдельно — это работа для reconcile_table.

    /opt/hotpath/venv/bin/python verify_groups.py [--show 10]
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
COLS = TABLES["groups"]


def норм(kind: str, v):
    """Привести значение к виду, в котором две базы сравнимы."""
    if kind == "json":
        if v is None:
            return None
        s = v if isinstance(v, str) else json.dumps(v)
        s = s.strip()
        if not s or s == "null":
            return None
        try:
            return json.dumps(json.loads(s), sort_keys=True, ensure_ascii=False)
        except (ValueError, TypeError):
            return s
    if kind == "num":
        try:
            return round(float(v or 0), 6)
        except (TypeError, ValueError):
            return 0.0
    if kind == "bool":
        return bool(v)
    return str(v) if v is not None else ""


async def долить(pg, names, строки: list) -> int:
    """Залить строки из SQLite в Postgres целиком (id + все колонки).

    Долив идёт по РАСХОЖДЕНИЮ ЗНАЧЕНИЙ, а не по колонке времени: счётчики
    messages_count и memories_count пишутся в SQLite прямым UPDATE мимо
    PocketBase и `updated` при этом не трогают — сверка по времени их бы не
    заметила и оставила в Postgres заниженными навсегда.
    """
    ph = ", ".join(f"${i + 1}" for i in range(len(names) + 1))
    upd = ", ".join(f"{c} = EXCLUDED.{c}" for c in names)
    сделано = 0
    for gid, src in строки:
        vals = [gid]
        for c in names:
            v = src[c]
            if COLS[c] == "json":
                s = v if isinstance(v, str) or v is None else json.dumps(v)
                vals.append(s if (s or "").strip() else None)
            elif COLS[c] == "num":
                vals.append(float(v or 0))
            elif COLS[c] == "bool":
                vals.append(bool(v))
            else:
                vals.append(str(v) if v is not None else "")
        await pg.execute(
            f"INSERT INTO groups (id, {', '.join(names)}) VALUES ({ph}) "
            f"ON CONFLICT (id) DO UPDATE SET {upd}", *vals)
        сделано += 1
    return сделано


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", type=int, default=10)
    ap.add_argument("--fix", action="store_true",
                    help="долить в Postgres расхождения и недостающие пары")
    ap.add_argument("--only-missing", action="store_true",
                    help="долить ТОЛЬКО пары, которых нет в Postgres. После "
                         "переключения источник правды — Postgres, и полный "
                         "долив откатил бы там свежие правки")
    args = ap.parse_args()
    names = list(COLS)

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    исходные = {
        r[0]: dict(zip(names, r[1:]))
        for r in lite.execute(f"SELECT id, {', '.join(names)} FROM groups")
    }

    pg = await asyncpg.connect(PG_DSN)
    копия = {
        r["id"]: dict(r)
        for r in await pg.fetch(f"SELECT id, {', '.join(names)} FROM groups")
    }

    нет_в_копии = sorted(set(исходные) - set(копия))
    лишние = sorted(set(копия) - set(исходные))
    расхождения = []   # (id, поле, было, стало)
    свежее = []        # правки после снимка — работа для reconcile

    for gid, src in исходные.items():
        dst = копия.get(gid)
        if dst is None:
            continue
        поля = []
        for c in names:
            a, b = норм(COLS[c], src[c]), норм(COLS[c], dst[c])
            if a != b:
                поля.append((c, a, b))
        if поля:
            if норм("text", src["updated"]) != норм("text", dst["updated"]):
                свежее.append((gid, поля))
            else:
                расхождения.append((gid, поля))

    print(f"пар в SQLite: {len(исходные)}, в Postgres: {len(копия)}")
    print(f"нет в Postgres: {len(нет_в_копии)}")
    print(f"лишних в Postgres: {len(лишние)}")
    print(f"правок после снимка (доберёт reconcile): {len(свежее)}")
    print(f"РАСХОЖДЕНИЙ при одинаковом updated: {len(расхождения)}")

    for gid, поля in расхождения[:args.show]:
        print(f"\n  пара {gid}")
        for c, a, b in поля[:6]:
            print(f"    {c}: SQLite {str(a)[:70]!r} -> Postgres {str(b)[:70]!r}")
    for gid in нет_в_копии[:args.show]:
        print(f"  нет в Postgres: {gid} (updated {исходные[gid]['updated']})")

    if args.fix or args.only_missing:
        строки = [(gid, исходные[gid]) for gid in нет_в_копии]
        if not args.only_missing:
            строки += ([(gid, исходные[gid]) for gid, _ in расхождения]
                       + [(gid, исходные[gid]) for gid, _ in свежее])
        сделано = await долить(pg, names, строки)
        print(f"\nдолито в Postgres: {сделано}")
    elif расхождения or нет_в_копии:
        print("\nПЕРЕКЛЮЧАТЬ НЕЛЬЗЯ: данные разошлись. Долив: --fix")
    else:
        print("\nПоля сходятся у всех пар.")

    await pg.close()
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
