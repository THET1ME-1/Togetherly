#!/usr/bin/env python3
"""Сверка членства: пары в Postgres против users.group_ids в SQLite.

Список групп человека — ключ ко ВСЕМ правилам доступа коллекций, оставшихся в
PocketBase. Пустой или неполный список означает «не удалось сохранить» при
живой паре, и человек этого никак не объяснит. Поэтому после переезда пар в
Postgres список сверяется отсюда, а не только подметальщиком.

    /opt/hotpath/venv/bin/python check_membership.py [--fix]
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
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()

    pg = await asyncpg.connect(PG_DSN)
    строки = await pg.fetch(
        "SELECT id, members FROM groups WHERE disbanded = false")
    await pg.close()

    надо = {}
    for r in строки:
        состав = r["members"]
        if isinstance(состав, str):
            try:
                состав = json.loads(состав)
            except ValueError:
                состав = []
        for uid in (состав or []):
            надо.setdefault(str(uid), set()).add(r["id"])

    lite = sqlite3.connect(SQLITE, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    есть = {}
    for uid, raw in lite.execute("SELECT id, COALESCE(group_ids,'') FROM users"):
        try:
            v = json.loads(raw) if raw else []
        except ValueError:
            v = []
        есть[uid] = set(str(x) for x in (v if isinstance(v, list) else [v]))

    нет_пары, лишние = [], []
    for uid, пары in надо.items():
        текущие = есть.get(uid)
        if текущие is None:
            continue          # человека нет в users — чужой uid в составе
        if пары - текущие:
            нет_пары.append((uid, sorted(пары - текущие)))
        if текущие - пары:
            лишние.append((uid, sorted(текущие - пары)))

    print(f"живых пар: {len(строки)}, людей в них: {len(надо)}")
    print(f"НЕ ВИДЯТ свою пару (запись закрыта): {len(нет_пары)}")
    print(f"помнят лишнюю пару: {len(лишние)}")
    for uid, пары in нет_пары[:10]:
        print(f"  {uid}: не хватает {пары}")

    if args.fix and (нет_пары or лишние):
        for uid, _ in нет_пары + лишние:
            lite.execute(
                "UPDATE users SET group_ids = COALESCE((SELECT json_group_array(g.id) "
                "FROM `groups` g WHERE EXISTS (SELECT 1 FROM json_each("
                "CASE WHEN json_valid(g.members) THEN g.members ELSE '[]' END) je "
                "WHERE je.value = ?)), '[]') WHERE id = ?", (uid, uid))
        lite.commit()
        print(f"поправлено людей: {len(нет_пары) + len(лишние)}")
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
