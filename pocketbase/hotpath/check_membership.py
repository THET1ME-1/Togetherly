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
import time

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
# Больше правок за ночь бывает, только если Postgres отдал не все пары.
# Тогда запись срезала бы людям доступ к своей паре, поэтому без --force
# такая пачка не пишется.
ПРЕДЕЛ_ПРАВОК = 2000


def разобрать(группы, есть):
    """Кому чинить список пар.

    `группы` — (id, состав, распущена) из Postgres, `есть` — uid → множество
    из users.group_ids. Целевой список — все пары, где человек в составе,
    распущенные тоже: приложение держит такую пару, чтобы поднять её со всей
    историей. Возвращает (кто не видит живую пару, правки (uid, список)).
    """
    все, живые = {}, {}
    for gid, состав, распущена in группы:
        for uid in состав:
            все.setdefault(uid, set()).add(gid)
            if not распущена:
                живые.setdefault(uid, set()).add(gid)
    нет_пары, правки = [], []
    for uid, текущие in есть.items():
        недостаёт = живые.get(uid, set()) - текущие
        if недостаёт:
            нет_пары.append((uid, sorted(недостаёт)))
        цель = все.get(uid, set())
        if текущие != цель:
            правки.append((uid, sorted(цель)))
    return нет_пары, правки


def применить(lite, правки, пачка=100, пауза=0.05):
    """Пишет списки пачками. Каждая пачка — своя короткая транзакция, между
    ними запись свободна для PocketBase. Возвращает число пачек."""
    пачек = 0
    for i in range(0, len(правки), пачка):
        with lite:
            lite.executemany(
                "UPDATE users SET group_ids = ? WHERE id = ?",
                [(json.dumps(список, separators=(",", ":"), ensure_ascii=False), uid)
                 for uid, список in правки[i:i + пачка]])
        пачек += 1
        if пауза:
            time.sleep(пауза)
    return пачек


def _состав(raw):
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except ValueError:
            raw = []
    return [str(uid) for uid in (raw or [])]


async def main() -> None:
    import asyncpg

    ap = argparse.ArgumentParser()
    ap.add_argument("--fix", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help=f"писать и больше {ПРЕДЕЛ_ПРАВОК} правок")
    args = ap.parse_args()

    pg = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    строки = await pg.fetch("SELECT id, members, disbanded FROM groups")
    await pg.close()
    группы = [(r["id"], _состав(r["members"]), bool(r["disbanded"])) for r in строки]

    lite = sqlite3.connect(SQLITE, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    есть = {}
    for uid, raw in lite.execute("SELECT id, COALESCE(group_ids,'') FROM users"):
        try:
            v = json.loads(raw) if raw else []
        except ValueError:
            v = []
        есть[uid] = set(str(x) for x in (v if isinstance(v, list) else [v]))

    нет_пары, правки = разобрать(группы, есть)
    живых = [g for g in группы if not g[2]]
    людей = len({uid for _, состав, _ in живых for uid in состав})
    print(f"живых пар: {len(живых)}, людей в них: {людей}")
    print(f"НЕ ВИДЯТ свою пару (запись закрыта): {len(нет_пары)}")
    print(f"список пар расходится с составом: {len(правки)}")
    for uid, пары in нет_пары[:10]:
        print(f"  {uid}: не хватает {пары}")

    if args.fix and правки:
        if len(правки) > ПРЕДЕЛ_ПРАВОК and not args.force:
            print(f"правок {len(правки)} больше предела {ПРЕДЕЛ_ПРАВОК}, не пишу без --force")
        else:
            пачек = применить(lite, правки)
            print(f"поправлено людей: {len(правки)}, пачек: {пачек}")
    lite.close()


if __name__ == "__main__":
    asyncio.run(main())
