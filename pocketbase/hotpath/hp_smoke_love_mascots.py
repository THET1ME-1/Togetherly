#!/usr/bin/env python3
"""Смоук теста «Умение любить» и маскотов в hotpath (переезд 19.10.2026).

Заводит своих троих — двое в паре, третий посторонний — прямой вставкой в
SQLite (людям нужны токены), гоняет те же запросы, что шлёт приложение, и
убирает за собой. По умолчанию ходит прямо в hotpath, поэтому годится ДО
переключения маршрута; HP_URL=https://togetherly.day проверяет уже маршрут.

    /opt/hotpath/venv/bin/python hp_smoke_love_mascots.py
"""

import asyncio
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import sys
import time

import asyncpg
import httpx

HP = os.environ.get("HP_URL", "http://127.0.0.1:8120")
DB = "/opt/pocketbase/pb_data/data.db"
PG_DSN = os.environ["HOTPATH_PG_DSN"]
client = httpx.Client(timeout=60)
failures = []


def check(name, ok, extra=""):
    print(("ОК   " if ok else "ПЛОХО") + f" {name} {extra if not ok else ''}", flush=True)
    if not ok:
        failures.append(name)


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def pg(sql: str, *args) -> None:
    async def run():
        conn = await asyncpg.connect(PG_DSN)
        try:
            await conn.execute(sql, *args)
        finally:
            await conn.close()
    asyncio.run(run())


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]

gid = "smlm" + secrets.token_hex(5) + "x"
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
people, headers = [], []
for tag in ("a", "b", "c"):          # третий — посторонний
    uid = f"sml{tag}" + secrets.token_hex(6)
    token_key = secrets.token_hex(25)
    lite.execute(
        "INSERT INTO users (id, email, tokenKey, password, verified, created, updated, group_ids) "
        "VALUES (?,?,?,?,1,?,?,?)",
        (uid, f"{uid}@togetherly.test", token_key, "x", now_s, now_s,
         json.dumps([gid]) if tag != "c" else "[]"))
    head = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                            "refreshable": True, "exp": int(time.time()) + 3600}).encode())
    sig = b64u(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                        hashlib.sha256).digest())
    people.append(uid)
    headers.append({"Authorization": f"{head}.{body}.{sig}"})
lite.commit()
A, B, C = people
HA, HB, HC = headers
love_id = "lt" + secrets.token_hex(7)[:13]
mascot_ids = []
print(f"пара {gid}: {A} + {B}, посторонний {C}", flush=True)

try:
    url = f"{HP}/api/collections/love_tests/records"
    body = {"id": love_id, "group_id": gid, "user_uid": A, "data": {"total": 7, "facets": {"care": 3}}, "total": 7}
    r = client.post(url, headers=HA, json=body)
    check("тест: автор заводит свою запись", r.status_code == 200 and r.json().get("id") == love_id,
          f"{r.status_code} {r.text[:150]}")
    if r.status_code == 200:
        rec = r.json()
        check("тест: форма ответа как у PocketBase",
              rec.get("collectionName") == "love_tests" and rec.get("data", {}).get("total") == 7
              and rec.get("total") == 7, json.dumps(rec)[:200])
    r = client.post(url, headers=HA, json=body)
    err = r.json() if r.status_code == 400 else {}
    check("тест: повтор отвечает «уже есть»",
          r.status_code == 400 and "validation_not_unique" in json.dumps(err), f"{r.status_code} {r.text[:150]}")
    r = client.post(url, headers=HA, json={"id": "lt" + secrets.token_hex(7)[:13], "group_id": gid,
                                           "user_uid": B, "data": {}, "total": 1})
    check("тест: от чужого имени завести нельзя", r.status_code == 400, f"{r.status_code}")
    r = client.post(url, headers=HC, json={"id": "lt" + secrets.token_hex(7)[:13], "group_id": gid,
                                           "user_uid": C, "data": {}, "total": 1})
    check("тест: посторонний не заводит в чужой паре", r.status_code == 400, f"{r.status_code}")
    r = client.get(url, headers=HB, params={"filter": f"group_id = '{gid}'"})
    items = r.json().get("items", []) if r.status_code == 200 else []
    check("тест: партнёр видит запись списком", any(i["id"] == love_id for i in items),
          f"{r.status_code} {r.text[:150]}")
    r = client.get(url, headers=HC, params={"filter": f"group_id = '{gid}'"})
    check("тест: посторонний не видит", r.status_code == 200 and not r.json().get("items"),
          f"{r.status_code} {r.text[:150]}")
    r = client.patch(f"{url}/{love_id}", headers=HB, json={"total": 99})
    check("тест: партнёр не правит чужую запись", r.status_code == 404, f"{r.status_code}")
    r = client.patch(f"{url}/{love_id}", headers=HA, json={"total": 9, "data": {"total": 9}})
    check("тест: автор правит свою", r.status_code == 200 and r.json().get("total") == 9,
          f"{r.status_code} {r.text[:150]}")
    r = client.delete(f"{url}/{love_id}", headers=HB)
    check("тест: партнёр не удаляет чужую", r.status_code == 404, f"{r.status_code}")
    r = client.delete(f"{url}/{love_id}", headers=HA)
    check("тест: автор удаляет свою", r.status_code == 204, f"{r.status_code} {r.text[:100]}")

    url = f"{HP}/api/collections/mascots/records"
    mascot = {"group_id": gid, "mascot_id": "smoke_m1", "name": "Пудя", "image_url": "",
              "default_asset": "assets/x.png", "created_by": A,
              "created_at": "2026-10-19T01:02:03.000Z", "is_default": False}
    r = client.post(url, headers=HA, json=mascot)
    if r.status_code == 200:
        mascot_ids.append(r.json()["id"])
    check("маскот: член пары заводит", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    if r.status_code == 200:
        rec = r.json()
        check("маскот: дата приходит в виде PocketBase", rec.get("created_at") == "2026-10-19 01:02:03.000Z",
              str(rec.get("created_at")))
    r = client.post(url, headers=HB, json=mascot)
    check("маскот: дубль пары и mascot_id отвечает «уже есть»",
          r.status_code == 400 and "validation_not_unique" in r.text, f"{r.status_code} {r.text[:150]}")
    r = client.get(url, headers=HB, params={
        "filter": f"group_id = '{gid}' && mascot_id = 'smoke_m1'", "perPage": 1, "skipTotal": 1})
    found = r.json().get("items", []) if r.status_code == 200 else []
    check("маскот: поиск по паре и mascot_id", len(found) == 1, f"{r.status_code} {r.text[:150]}")
    if found:
        mid = found[0]["id"]
        r = client.patch(f"{url}/{mid}", headers=HB, json={"record_streak": 12})
        check("маскот: второй из пары правит", r.status_code == 200 and r.json().get("record_streak") == 12,
              f"{r.status_code} {r.text[:150]}")
        r = client.patch(f"{url}/{mid}", headers=HC, json={"record_streak": 1})
        check("маскот: посторонний не правит", r.status_code == 404, f"{r.status_code}")
        r = client.get(url, headers=HC, params={"filter": f"group_id = '{gid}'"})
        check("маскот: посторонний не видит", r.status_code == 200 and not r.json().get("items"),
              f"{r.status_code}")
        r = client.get(url, headers=HA, params={"filter": f"group_id = '{gid}' && updated > '2000-01-01 00:00:00'",
                                                "sort": "updated"})
        check("маскот: дельта по updated работает", r.status_code == 200 and len(r.json().get("items", [])) == 1,
              f"{r.status_code} {r.text[:150]}")
        r = client.delete(f"{url}/{mid}", headers=HC)
        check("маскот: посторонний не удаляет", r.status_code == 404, f"{r.status_code}")
        r = client.delete(f"{url}/{mid}", headers=HB)
        check("маскот: член пары удаляет", r.status_code == 204, f"{r.status_code}")
finally:
    for uid in people:
        lite.execute("DELETE FROM users WHERE id = ?", (uid,))
    lite.commit()
    lite.close()
    pg("DELETE FROM love_tests WHERE group_id = $1", gid)
    pg("DELETE FROM mascots WHERE group_id = $1", gid)
    print("тестовые записи убраны", flush=True)

print(f"итог: провалов {len(failures)}" + (f" — {failures}" if failures else ""))
sys.exit(1 if failures else 0)
