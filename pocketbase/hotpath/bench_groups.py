#!/usr/bin/env python3
"""Замер чтения и правки записи пары — до и после переезда groups в Postgres.

Заводит свою тестовую пару прямой вставкой в SQLite (как смоуки), подписывает
токен тем же ключом, что PocketBase, и гоняет те же запросы, что шлёт
приложение. За собой убирает.

    /opt/hotpath/venv/bin/python bench_groups.py --target pb    # PocketBase
    /opt/hotpath/venv/bin/python bench_groups.py --target hp    # hotpath
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import statistics
import time

import asyncio

import asyncpg
import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def срез(v: list) -> str:
    if not v:
        return "нет данных"
    v = sorted(v)
    p90 = v[int(len(v) * 0.9) - 1]
    return (f"медиана {statistics.median(v) * 1000:7.1f} мс   "
            f"p90 {p90 * 1000:7.1f} мс   худший {v[-1] * 1000:7.1f} мс")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=["pb", "hp"], default="pb")
    ap.add_argument("--runs", type=int, default=25)
    args = ap.parse_args()
    base = PB if args.target == "pb" else HP

    lite = sqlite3.connect(DB, timeout=60)
    lite.execute("PRAGMA busy_timeout=60000")
    secret = json.loads(
        lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
    )["authToken"]["secret"]

    gid = "benchg" + secrets.token_hex(5)
    now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
    users = []
    heads = []
    for tag in ("a", "b"):
        uid = f"bench{tag}" + secrets.token_hex(5)
        tk = secrets.token_hex(25)
        lite.execute(
            "INSERT INTO users (id, email, tokenKey, password, verified, created, "
            "updated, group_ids) VALUES (?,?,?,?,1,?,?,?)",
            (uid, f"{uid}@togetherly.test", tk, "x", now_s, now_s, json.dumps([gid])))
        h = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
        p = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid,
                             "type": "auth", "refreshable": True,
                             "exp": int(time.time()) + 3600}).encode())
        sig = b64u(hmac.new((tk + secret).encode(), f"{h}.{p}".encode(),
                            hashlib.sha256).digest())
        users.append(uid)
        heads.append({"Authorization": f"{h}.{p}.{sig}"})
    lite.execute(
        "INSERT INTO groups (id, members, member_moods, memories_count, "
        "drawings_count, messages_count, created_at, updated) VALUES (?,?,?,0,0,0,?,?)",
        (gid, json.dumps(users), "{}", now_s, now_s))
    lite.commit()

    # Пару заводим в ОБЕИХ базах: с 15.08.2026 источник правды — Postgres, а
    # токены и профили людей остались в SQLite PocketBase.
    async def _в_postgres(запрос, *args):
        conn = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
        try:
            await conn.execute(запрос, *args)
        finally:
            await conn.close()

    asyncio.run(_в_postgres(
        "INSERT INTO groups (id, members, member_moods, created_at, updated) "
        "VALUES ($1, $2::jsonb, '{}'::jsonb, $3, $3) ON CONFLICT (id) DO NOTHING",
        gid, json.dumps(users), now_s))
    print(f"тестовая пара {gid}: {users[0]} + {users[1]}", flush=True)

    c = httpx.Client(timeout=120)
    ha = heads[0]
    чтение_списком, чтение_по_id, правка = [], [], []
    try:
        for i in range(args.runs):
            t = time.perf_counter()
            r = c.get(f"{base}/api/collections/groups/records",
                      params={"filter": f'id="{gid}"', "perPage": 1}, headers=ha)
            if r.status_code == 200:
                чтение_списком.append(time.perf_counter() - t)
            elif i == 0:
                print(f"  список: {r.status_code} {r.text[:120]}")

            t = time.perf_counter()
            r = c.get(f"{base}/api/collections/groups/records/{gid}", headers=ha)
            if r.status_code == 200:
                чтение_по_id.append(time.perf_counter() - t)
            elif i == 0:
                print(f"  по id: {r.status_code} {r.text[:120]}")

            t = time.perf_counter()
            r = c.patch(f"{base}/api/collections/groups/records/{gid}", headers=ha,
                        json={"member_moods": {users[0]: f"happy{i}"}})
            if r.status_code == 200:
                правка.append(time.perf_counter() - t)
            elif i == 0:
                print(f"  правка: {r.status_code} {r.text[:160]}")

        цель = "PocketBase" if args.target == "pb" else "hotpath"
        print(f"\n=== {цель}, прогонов {args.runs} ===")
        print(f"чтение списком : {срез(чтение_списком)}  удачных {len(чтение_списком)}")
        print(f"чтение по id   : {срез(чтение_по_id)}  удачных {len(чтение_по_id)}")
        print(f"правка настроя : {срез(правка)}  удачных {len(правка)}")
    finally:
        lite.execute("DELETE FROM groups WHERE id = ?", (gid,))
        lite.executemany("DELETE FROM users WHERE id = ?", [(u,) for u in users])
        lite.commit()
        lite.close()
        asyncio.run(_в_postgres("DELETE FROM groups WHERE id = $1", gid))
        print("\nтестовые записи убраны", flush=True)


if __name__ == "__main__":
    main()
