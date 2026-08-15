#!/usr/bin/env python3
"""Повторяет запросы экрана «профиль партнёра» от лица живого участника пары.

Экран собирается из четырёх источников, и любой из них молча роняет его в
пустоту: карточка партнёра (роут /api/user/card), запись пары, подарки и
«Скучаю». Скрипт заводит свою пару, ходит теми же запросами и печатает, что
ответил каждый. За собой убирает.

    /opt/hotpath/venv/bin/python probe_partner_profile.py
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import time

import asyncio
import asyncpg
import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"
PG_DSN = os.environ["HOTPATH_PG_DSN"]


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def pg(sql: str, *args):
    async def _run():
        c = await asyncpg.connect(PG_DSN)
        try:
            if sql.strip().lower().startswith("select"):
                return await c.fetchval(sql, *args)
            await c.execute(sql, *args)
        finally:
            await c.close()
    return asyncio.run(_run())


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]

gid = "prof" + secrets.token_hex(6)
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
люди, шапки = [], []
for tag in ("a", "b"):
    uid = f"prof{tag}" + secrets.token_hex(5)
    tk = secrets.token_hex(25)
    lite.execute(
        "INSERT INTO users (id, email, tokenKey, password, verified, created, "
        "updated, group_ids, display_name, avatar_url) "
        "VALUES (?,?,?,?,1,?,?,?,?,'')",
        (uid, f"{uid}@togetherly.test", tk, "x", now_s, now_s,
         json.dumps([gid]), f"Проба {tag.upper()}"))
    h = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid,
                         "type": "auth", "refreshable": True,
                         "exp": int(time.time()) + 3600}).encode())
    sig = b64u(hmac.new((tk + secret).encode(), f"{h}.{p}".encode(),
                        hashlib.sha256).digest())
    люди.append(uid)
    шапки.append({"Authorization": f"{h}.{p}.{sig}"})
lite.commit()
A, B = люди
HA, HB = шапки
lite.execute(
    "INSERT INTO `groups` (id, members, created_at, updated) VALUES (?,?,?,?)",
    (gid, json.dumps(люди), now_s, now_s))
lite.commit()
pg("INSERT INTO groups (id, members, created_at, updated) "
   "VALUES ($1, $2::jsonb, $3, $3) ON CONFLICT (id) DO NOTHING",
   gid, json.dumps(люди), now_s)
print(f"пара {gid}: {A} смотрит профиль {B}\n", flush=True)

c = httpx.Client(timeout=30)
try:
    r = c.get(f"{PB}/api/user/card", params={"uid": B}, headers=HA)
    print(f"1. карточка партнёра   : {r.status_code} {r.text[:160]}")

    r = c.get(f"{HP}/api/collections/groups/records/{gid}", headers=HA)
    print(f"2. запись пары         : {r.status_code} "
          f"{'ok' if r.status_code == 200 else r.text[:160]}")

    r = c.get(f"{PB}/api/collections/gifts/records", headers=HA,
              params={"filter": f'group_id = "{gid}" && recipient_uid = "{B}"',
                      "perPage": 200, "sort": "-created"})
    print(f"3. подарки партнёру    : {r.status_code} "
          f"{'записей ' + str(len(r.json().get('items', []))) if r.status_code == 200 else r.text[:160]}")

    r = c.get(f"{HP}/api/collections/miss_you/records", headers=HA,
              params={"filter": f'group_id = "{gid}" && user_uid = "{B}"',
                      "perPage": 1, "skipTotal": 1})
    видно = (r.status_code == 200 and r.json().get("items"))
    print(f"4. «Скучаю» партнёра   : {r.status_code} "
          f"{'запись есть' if видно else 'записей нет (для новой пары это норма)'}")
    if r.status_code != 200:
        print(f"   тело: {r.text[:200]}")

    r = c.get(f"{PB}/api/collections/gifts/records", headers=HA,
              params={"filter": f'recipient_uid = "{B}"', "perPage": 1})
    print(f"3б. счётчик подарков   : {r.status_code} "
          f"{'ok' if r.status_code == 200 else r.text[:160]}")

    # тот же запрос, но как его шлёт SDK: getFirstListItem
    r = c.get(f"{HP}/api/collections/miss_you/records", headers=HA,
              params={"filter": f'group_id="{gid}" && user_uid="{B}"',
                      "perPage": 1, "skipTotal": 1, "page": 1})
    print(f"5. то же без пробелов  : {r.status_code} "
          f"{'ok' if r.status_code == 200 else r.text[:200]}")
finally:
    c.close()
    lite.execute("DELETE FROM `groups` WHERE id = ?", (gid,))
    for u in люди:
        lite.execute("DELETE FROM users WHERE id = ?", (u,))
    lite.commit()
    lite.close()
    pg("DELETE FROM groups WHERE id = $1", gid)
    print("\nтестовые записи убраны")
