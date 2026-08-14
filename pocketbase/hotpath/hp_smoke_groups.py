#!/usr/bin/env python3
"""Смоук записи пары в hotpath: чтение, правила доступа, ручки.

Заводит своих людей и свою пару, проверяет их же и убирает за собой. Пара
создаётся прямой вставкой в SQLite (людям нужны токены) и в Postgres — это
позволяет гонять смоук ДО переключения маршрута, когда приложение ещё ходит
в PocketBase.

    /opt/hotpath/venv/bin/python hp_smoke_groups.py
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import asyncio
import subprocess
import sys
import time

import asyncpg
import httpx

HP = os.environ.get("HP_URL", "http://127.0.0.1:8120")
DB = "/opt/pocketbase/pb_data/data.db"
PG_DSN = os.environ["HOTPATH_PG_DSN"]
c = httpx.Client(timeout=60)
провалы = []


def проверка(имя, ок, добавка=""):
    print(("ОК   " if ок else "ПЛОХО") + f" {имя} {добавка}", flush=True)
    if not ок:
        провалы.append(имя)


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def pg(sql: str, *args) -> str:
    """Короткий запрос в Postgres тем же доступом, что у hotpath.

    Через psql контейнера ходить нельзя: таблицы принадлежат роли togetherly,
    и роль postgres получает «permission denied» на запись.
    """
    async def _run():
        conn = await asyncpg.connect(PG_DSN)
        try:
            if sql.strip().lower().startswith("select"):
                v = await conn.fetchval(sql, *args)
                return "" if v is None else str(v)
            await conn.execute(sql, *args)
            return ""
        finally:
            await conn.close()
    return asyncio.run(_run())


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]

gid = "smgrp" + secrets.token_hex(5)
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
люди, шапки = [], []
for tag in ("a", "b", "c"):          # третий — посторонний, для проверки прав
    uid = f"smg{tag}" + secrets.token_hex(5)
    tk = secrets.token_hex(25)
    lite.execute(
        "INSERT INTO users (id, email, tokenKey, password, verified, created, "
        "updated, group_ids) VALUES (?,?,?,?,1,?,?,?)",
        (uid, f"{uid}@togetherly.test", tk, "x", now_s, now_s,
         json.dumps([gid]) if tag != "c" else "[]"))
    h = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid,
                         "type": "auth", "refreshable": True,
                         "exp": int(time.time()) + 3600}).encode())
    sig = b64u(hmac.new((tk + secret).encode(), f"{h}.{p}".encode(),
                        hashlib.sha256).digest())
    люди.append(uid)
    шапки.append({"Authorization": f"{h}.{p}.{sig}"})
lite.commit()
A, B, C = люди
HA, HB, HC = шапки
пара = json.dumps([A, B])
lite.execute(
    "INSERT INTO `groups` (id, members, member_moods, memories_count, "
    "messages_count, drawings_count, xp, created_at, updated) "
    "VALUES (?,?,'{}',0,0,0,0,?,?)", (gid, пара, now_s, now_s))
lite.commit()
pg("INSERT INTO groups (id, members, created_at, updated) VALUES ($1, $2::jsonb, $3, $4)",
   gid, пара, now_s, now_s)
print(f"пара {gid}: {A} + {B}, посторонний {C}", flush=True)

try:
    # ── чтение списком: тем же фильтром, что шлёт приложение ──
    r = c.get(f"{HP}/api/collections/groups/records", headers=HA,
              params={"filter": f"members ~ '{A}' && disbanded = false"})
    ок = r.status_code == 200 and any(i["id"] == gid for i in r.json().get("items", []))
    проверка("список своих пар (members ~ uid)", ок,
             "" if ок else f"{r.status_code} {r.text[:120]}")

    # ── чтение по id ──
    r = c.get(f"{HP}/api/collections/groups/records/{gid}", headers=HB)
    проверка("чтение пары по id", r.status_code == 200 and r.json().get("id") == gid,
             "" if r.status_code == 200 else f"{r.status_code} {r.text[:120]}")
    if r.status_code == 200:
        тело = r.json()
        проверка("форма ответа как у PocketBase",
                 тело.get("collectionName") == "groups"
                 and isinstance(тело.get("members"), list)
                 and тело.get("memories_count") == 0)

    # ── посторонний не видит чужую пару ──
    r = c.get(f"{HP}/api/collections/groups/records/{gid}", headers=HC)
    проверка("посторонний получает 404", r.status_code == 404, f"код {r.status_code}")
    r = c.get(f"{HP}/api/collections/groups/records", headers=HC,
              params={"filter": f"members ~ '{A}'"})
    пусто = r.status_code == 200 and not r.json().get("items")
    проверка("посторонний не находит пару списком", пусто)

    # ── правка записи ──
    r = c.patch(f"{HP}/api/collections/groups/records/{gid}", headers=HA,
                json={"member_moods": {A: "happy"}, "xp": 5})
    проверка("правка пары участником", r.status_code == 200
             and r.json().get("member_moods", {}).get(A) == "happy",
             "" if r.status_code == 200 else f"{r.status_code} {r.text[:120]}")
    r = c.patch(f"{HP}/api/collections/groups/records/{gid}", headers=HC,
                json={"xp": 999})
    проверка("посторонний не правит пару", r.status_code == 404, f"код {r.status_code}")

    # ── страж пары: третьего не вписать, служебные поля закрыты ──
    r = c.patch(f"{HP}/api/collections/groups/records/{gid}", headers=HA,
                json={"members": [A, B, C]})
    проверка("третьего в пару не вписать", r.status_code == 403,
             f"код {r.status_code}")
    r = c.patch(f"{HP}/api/collections/groups/records/{gid}", headers=HA,
                json={"claim_token": "ХАЛЯВА1"})
    проверка("код второго места клиенту закрыт", r.status_code == 403,
             f"код {r.status_code}")
    r = c.patch(f"{HP}/api/collections/groups/records/{gid}", headers=HA,
                json={"members": [A]})
    проверка("выйти из пары самому можно", r.status_code == 200,
             f"код {r.status_code}")
    if r.status_code == 200:
        time.sleep(1.5)
        оставшийся = pg("SELECT members::text FROM groups WHERE id = $1", gid)
        проверка("состав сократился", B not in оставшийся, f"состав {оставшийся}")
        pg("UPDATE groups SET members = $1::jsonb WHERE id = $2",
           json.dumps([A, B]), gid)

    # ── ручки (работают, когда источник правды уже Postgres) ──
    режим = subprocess.run(
        ["systemctl", "show", "hotpath", "-p", "Environment"],
        capture_output=True, text=True).stdout
    в_pg = "HOTPATH_GROUPS=pg" in режим or os.environ.get("HOTPATH_GROUPS") == "pg"

    r = c.post(f"{HP}/api/group/patch-map", headers=HB,
               json={"groupId": gid, "field": "member_moods", "uid": B,
                     "value": "sad"})
    if в_pg:
        проверка("ручка правки карты", r.status_code == 200 and r.json().get("ok"),
                 "" if r.status_code == 200 else f"{r.status_code} {r.text[:120]}")
        значение = pg("SELECT member_moods->>$1 FROM groups WHERE id = $2", B, gid)
        проверка("карта записалась в Postgres", значение == "sad", f"значение {значение!r}")
    else:
        проверка("ручка правки карты проксируется в PocketBase",
                 r.status_code in (200, 400, 403, 500), f"код {r.status_code}")

    r = c.post(f"{HP}/api/group/increment", headers=HA,
               json={"groupId": gid, "field": "xp", "by": 3})
    if в_pg:
        проверка("ручка опыта", r.status_code == 200 and r.json().get("ok"),
                 f"ответ {r.text[:100]}")
    r = c.post(f"{HP}/api/group/increment", headers=HA,
               json={"groupId": gid, "field": "memories_count", "by": 1})
    проверка("счётчик воспоминаний остаётся за сервером (noop)",
             r.status_code == 200 and r.json().get("noop") is True
             if в_pg else r.status_code in (200, 400, 500))

    r = c.post(f"{HP}/api/group/record-activity", headers=HA,
               json={"groupId": gid, "uid": A, "today": time.strftime("%Y-%m-%d")})
    проверка("отметка дня: первый ждёт второго",
             r.status_code == 200 and (r.json().get("pending") or r.json().get("ok")),
             f"ответ {r.text[:100]}")
    if в_pg:
        r = c.post(f"{HP}/api/group/record-activity", headers=HB,
                   json={"groupId": gid, "uid": B, "today": time.strftime("%Y-%m-%d")})
        проверка("отметка дня: оба зашли, серия выросла",
                 r.status_code == 200 and r.json().get("streak") == 1,
                 f"ответ {r.text[:100]}")

    # ── выход из пары ──
    if в_pg:
        r = c.post(f"{HP}/api/group/leave", headers=HB,
                   json={"groupId": gid, "uid": B})
        проверка("выход из пары", r.status_code == 200 and r.json().get("ok"),
                 f"ответ {r.text[:100]}")
        осталось = pg("SELECT members::text FROM groups WHERE id = $1", gid)
        проверка("состав пары в Postgres обновился", B not in осталось,
                 f"состав {осталось}")
        time.sleep(1.5)
        группы_B = lite.execute(
            "SELECT group_ids FROM users WHERE id = ?", (B,)).fetchone()[0]
        проверка("список пар ушедшего пересчитан в SQLite",
                 gid not in (группы_B or ""), f"group_ids {группы_B!r}")
        зеркало = lite.execute(
            "SELECT members FROM `groups` WHERE id = ?", (gid,)).fetchone()[0]
        проверка("зеркало в SQLite обновилось сразу", B not in (зеркало or ""),
                 f"зеркало {зеркало!r}")
finally:
    lite.execute("DELETE FROM `groups` WHERE id = ?", (gid,))
    for u in люди:
        lite.execute("DELETE FROM users WHERE id = ?", (u,))
    lite.commit()
    lite.close()
    pg("DELETE FROM groups WHERE id = $1", gid)
    print("\nтестовые записи убраны", flush=True)

print(f"\nитог: провалов {len(провалы)}" + (f" — {провалы}" if провалы else ""))
sys.exit(1 if провалы else 0)
