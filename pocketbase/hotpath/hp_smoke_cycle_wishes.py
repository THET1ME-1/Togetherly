#!/usr/bin/env python3
"""Смоук отметок цикла, желаний, категорий и настроек в hotpath (19.10.2026).

Заводит троих прямой вставкой в SQLite (двое в паре, третий посторонний),
гоняет те же запросы, что шлёт приложение, и убирает за собой. По умолчанию
ходит прямо в hotpath, поэтому годится ДО переключения маршрута;
HP_URL=https://togetherly.day проверяет уже маршрут.

Каждая проверка ловит свою поломку: партнёр видит скрытую отметку цикла,
чужое правится или удаляется, не-автор переименовывает желание, правка
затирает время создания, настройки требуют входа или пускают запись.

    /opt/hotpath/venv/bin/python hp_smoke_cycle_wishes.py
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


def new_id(prefix: str) -> str:
    return prefix + secrets.token_hex(6)


def items(r) -> list:
    return r.json().get("items", []) if r.status_code == 200 else []


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]

gid = "smcw" + secrets.token_hex(5) + "x"
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
people, headers = [], []
for tag in ("a", "b", "c"):          # третий — посторонний
    uid = f"smw{tag}" + secrets.token_hex(6)
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
print(f"пара {gid}: {A} + {B}, посторонний {C}", flush=True)

try:
    # ── отметки цикла ────────────────────────────────────────────────────
    url = f"{HP}/api/collections/cycle_entries/records"
    hidden = new_id("smc")
    r = client.post(url, headers=HA, json={
        "id": hidden, "group_id": gid, "user_uid": A,
        "day": "2026-10-10T00:00:00.000Z", "kind": "period", "flow": "medium",
        "shared": False})
    created = r.json() if r.status_code == 200 else {}
    check("цикл: своя отметка заводится", r.status_code == 200 and created.get("id") == hidden,
          f"{r.status_code} {r.text[:150]}")
    check("цикл: день приходит в виде PocketBase",
          created.get("day") == "2026-10-10 00:00:00.000Z", str(created.get("day")))
    check("цикл: время создания ставит сервер", bool(created.get("created")),
          str(created.get("created")))
    r = client.post(url, headers=HA, json={
        "id": new_id("smc"), "group_id": gid, "user_uid": B, "day": "2026-10-11", "shared": True})
    check("цикл: от чужого имени завести нельзя", r.status_code == 400, f"{r.status_code}")
    r = client.post(url, headers=HC, json={
        "id": new_id("smc"), "group_id": gid, "user_uid": C, "day": "2026-10-11", "shared": True})
    check("цикл: посторонний не заводит в чужой паре", r.status_code == 400, f"{r.status_code}")
    flt = {"filter": f"group_id = '{gid}' && user_uid = '{A}'", "sort": "day"}
    r = client.get(url, headers=HA, params=flt)
    check("цикл: автор видит свою скрытую отметку", len(items(r)) == 1,
          f"{r.status_code} {r.text[:150]}")
    r = client.get(url, headers=HB, params=flt)
    check("цикл: партнёр НЕ видит скрытую отметку", r.status_code == 200 and not items(r),
          f"{r.status_code} {r.text[:150]}")
    r = client.get(f"{url}/{hidden}", headers=HB)
    check("цикл: скрытая отметка партнёру по id не отдаётся", r.status_code == 404,
          f"{r.status_code}")
    r = client.patch(f"{url}/{hidden}", headers=HB, json={"shared": True})
    check("цикл: партнёр не правит чужую отметку", r.status_code == 404, f"{r.status_code}")
    r = client.patch(f"{url}/{hidden}", headers=HA, json={
        "shared": True, "created": "2000-01-01 00:00:00.000Z"})
    shared = r.json() if r.status_code == 200 else {}
    check("цикл: автор открывает отметку партнёру", shared.get("shared") is True,
          f"{r.status_code} {r.text[:150]}")
    check("цикл: правка не трогает время создания",
          bool(created.get("created")) and shared.get("created") == created.get("created"),
          f"{created.get('created')} -> {shared.get('created')}")
    r = client.get(url, headers=HB, params=flt)
    check("цикл: партнёр видит открытую отметку", len(items(r)) == 1,
          f"{r.status_code} {r.text[:150]}")
    r = client.get(url, headers=HC, params=flt)
    check("цикл: посторонний не видит и открытую", r.status_code == 200 and not items(r),
          f"{r.status_code}")
    r = client.get(url, headers=HA, params={
        "filter": f"group_id = '{gid}' && user_uid = '{A}' && updated > '2000-01-01 00:00:00'",
        "sort": "updated"})
    check("цикл: дельта по updated работает", len(items(r)) == 1, f"{r.status_code} {r.text[:150]}")
    r = client.delete(f"{url}/{hidden}", headers=HB)
    check("цикл: партнёр не удаляет чужую отметку", r.status_code == 404, f"{r.status_code}")
    r = client.delete(f"{url}/{hidden}", headers=HA)
    check("цикл: автор удаляет свою", r.status_code == 204, f"{r.status_code}")

    # ── желания ──────────────────────────────────────────────────────────
    url = f"{HP}/api/collections/wishes/records"
    wish = new_id("smw")
    r = client.post(url, headers=HA, json={
        "id": wish, "group_id": gid, "author_uid": A, "title": "Море",
        "kind": "deed", "price": 0, "done": False})
    made = r.json() if r.status_code == 200 else {}
    check("желание: автор заводит", r.status_code == 200 and made.get("title") == "Море",
          f"{r.status_code} {r.text[:150]}")
    r = client.post(url, headers=HA, json={
        "id": new_id("smw"), "group_id": gid, "author_uid": B, "title": "Чужое"})
    check("желание: от чужого имени завести нельзя", r.status_code == 400, f"{r.status_code}")
    r = client.get(url, headers=HB, params={"filter": f"group_id = '{gid}'"})
    check("желание: партнёр видит", any(i["id"] == wish for i in items(r)),
          f"{r.status_code} {r.text[:150]}")
    r = client.patch(f"{url}/{wish}", headers=HB, json={
        "done": True, "done_by": B, "done_at": "2026-10-19T01:00:00.000Z", "done_note": "Было!"})
    check("желание: партнёр отмечает «сбылось»",
          r.status_code == 200 and r.json().get("done") is True and r.json().get("done_by") == B,
          f"{r.status_code} {r.text[:150]}")
    r = client.patch(f"{url}/{wish}", headers=HB, json={"title": "Горы"})
    check("желание: партнёр не переименовывает чужое", r.status_code == 403, f"{r.status_code}")
    r = client.delete(f"{url}/{wish}", headers=HB)
    check("желание: партнёр не удаляет чужое", r.status_code == 403, f"{r.status_code}")
    r = client.patch(f"{url}/{wish}", headers=HC, json={"done": False})
    check("желание: посторонний не отмечает", r.status_code == 404, f"{r.status_code}")
    r = client.patch(f"{url}/{wish}", headers=HA, json={"title": "Горы"})
    renamed = r.json() if r.status_code == 200 else {}
    check("желание: автор переименовывает", renamed.get("title") == "Горы",
          f"{r.status_code} {r.text[:150]}")
    check("желание: правка не трогает время создания",
          bool(made.get("created")) and renamed.get("created") == made.get("created"),
          f"{made.get('created')} -> {renamed.get('created')}")
    r = client.get(url, headers=HC, params={"filter": f"group_id = '{gid}'"})
    check("желание: посторонний не видит", r.status_code == 200 and not items(r), f"{r.status_code}")
    r = client.delete(f"{url}/{wish}", headers=HA)
    check("желание: автор удаляет", r.status_code == 204, f"{r.status_code}")

    # ── категории желаний ────────────────────────────────────────────────
    url = f"{HP}/api/collections/wish_categories/records"
    cat = new_id("smk")
    r = client.post(url, headers=HA, json={
        "id": cat, "group_id": gid, "author_uid": A, "title": "Поездки", "symbol": "flight"})
    check("категория: автор заводит", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    r = client.patch(f"{url}/{cat}", headers=HB, json={"title": "Путешествия"})
    check("категория: партнёр правит", r.status_code == 200
          and r.json().get("title") == "Путешествия", f"{r.status_code} {r.text[:150]}")
    r = client.patch(f"{url}/{cat}", headers=HC, json={"title": "Взлом"})
    check("категория: посторонний не правит", r.status_code == 404, f"{r.status_code}")
    r = client.delete(f"{url}/{cat}", headers=HB)
    check("категория: партнёр удаляет", r.status_code == 204, f"{r.status_code}")

    # ── настройки приложения ─────────────────────────────────────────────
    url = f"{HP}/api/collections/app_config/records"
    want = lite.execute(
        "SELECT id, min_build, chest_enabled, room_native_ios FROM app_config").fetchone()
    r = client.get(url, params={"perPage": 1})
    got = items(r)
    check("настройки: читаются без входа", r.status_code == 200 and len(got) == 1,
          f"{r.status_code} {r.text[:150]}")
    if got and want:
        g = got[0]
        check("настройки: совпадают с SQLite",
              g.get("id") == want[0] and g.get("min_build") == int(want[1] or 0)
              and g.get("chest_enabled") is bool(want[2])
              and g.get("room_native_ios") == int(want[3] or 0),
              f"{json.dumps(g)[:200]} против {want}")
    r = client.post(url, headers=HA, json={"min_build": 999})
    check("настройки: создать нельзя", r.status_code == 403, f"{r.status_code}")
    if want:
        r = client.patch(f"{url}/{want[0]}", headers=HA, json={"min_build": 999})
        check("настройки: править нельзя", r.status_code == 403, f"{r.status_code}")
        r = client.delete(f"{url}/{want[0]}", headers=HA)
        check("настройки: удалить нельзя", r.status_code == 403, f"{r.status_code}")
finally:
    for uid in people:
        lite.execute("DELETE FROM users WHERE id = ?", (uid,))
    lite.commit()
    lite.close()
    for table in ("cycle_entries", "wishes", "wish_categories"):
        try:
            pg(f"DELETE FROM {table} WHERE group_id = $1", gid)
        except asyncpg.PostgresError:
            pass  # таблицы ещё нет — до выкладки проверка и должна падать
    print("тестовые записи убраны", flush=True)

print(f"итог: провалов {len(failures)}" + (f" — {failures}" if failures else ""))
sys.exit(1 if failures else 0)
