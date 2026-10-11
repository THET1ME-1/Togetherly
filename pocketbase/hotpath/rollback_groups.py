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
import time

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")


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


def совпадает(kind: str, новое, старое) -> bool:
    """Лежит ли в SQLite уже то же, что собираемся записать."""
    if kind == "json":
        # Postgres отдаёт json с пробелами, PocketBase хранит без них.
        try:
            return json.loads(новое or "null") == json.loads(старое or "null")
        except (TypeError, ValueError):
            return новое == старое
    if kind == "bool":
        return новое == (1 if старое else 0)
    if kind == "num":
        try:
            return новое == float(старое or 0)
        except (TypeError, ValueError):
            return False
    return новое == (старое if старое is not None else "")


def залить(lite, строки, виды, пачка=50, между_пачками=None, писать=True):
    """Пишет строки пар в SQLite, возвращает (обновлено, добавлено, совпало).

    Замок записи берётся на одну пачку, и только если в ней есть что писать.
    Одна транзакция на все строки держала его пять с половиной минут
    (14 тысяч пар за ночь): PocketBase всё это время писать не мог, а после
    отпуска замка застоявшиеся записи пользователей ложились поверх свежих и
    съедали приз сундука (разбор 11.10.2026, test_rollback_groups.py).
    Соединение должно быть открыто с isolation_level=None. С `писать=False`
    только считает, что изменилось бы.
    """
    колонки = list(виды)
    поля = ", ".join(f"`{c}`" for c in колонки)
    места = ", ".join("?" * (len(колонки) + 1))
    назначения = ", ".join(f"`{c}` = ?" for c in колонки)
    обновлено = добавлено = совпало = 0
    for начало in range(0, len(строки), пачка):
        править, вставить = [], []
        for row in строки[начало:начало + пачка]:
            значения = [привести(виды[c], row[c]) for c in колонки]
            есть = lite.execute(
                f"SELECT {поля} FROM `groups` WHERE id = ?", (row["id"],)).fetchone()
            if есть is None:
                вставить.append((row["id"], *значения))
            elif all(совпадает(виды[c], н, с) for c, н, с in zip(колонки, значения, есть)):
                совпало += 1
            else:
                править.append((*значения, row["id"]))
        if not писать:
            обновлено += len(править)
            добавлено += len(вставить)
            continue
        if править or вставить:
            lite.execute("BEGIN IMMEDIATE")
            try:
                lite.executemany(f"UPDATE `groups` SET {назначения} WHERE id = ?", править)
                lite.executemany(
                    f"INSERT INTO `groups` (id, {поля}) VALUES ({места})", вставить)
                lite.execute("COMMIT")
            except BaseException:
                lite.execute("ROLLBACK")
                raise
            обновлено += len(править)
            добавлено += len(вставить)
        if между_пачками:
            между_пачками()
    return обновлено, добавлено, совпало


async def main() -> None:
    import asyncpg

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from migrate_table import TABLES

    PG_DSN = os.environ["HOTPATH_PG_DSN"]
    КОЛОНКИ = list(TABLES["groups"])
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

    lite = sqlite3.connect(SQLITE, timeout=60, isolation_level=None)
    lite.execute("PRAGMA busy_timeout=60000")
    try:
        обновлено, добавлено, совпало = залить(
            lite, строки, TABLES["groups"], писать=args.commit,
            между_пачками=lambda: time.sleep(0.05))
    finally:
        lite.close()
    if not args.commit:
        print(f"к обновлению {обновлено}, к добавлению {добавлено}, совпало {совпало} "
              "(прогон без --commit, ничего не записано)")
        return
    print(f"в SQLite обновлено {обновлено}, добавлено {добавлено}, совпало {совпало}")


if __name__ == "__main__":
    asyncio.run(main())
