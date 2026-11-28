#!/usr/bin/env python3
"""Смоук «Наших дат» в hotpath (TOG-61, 28.11.2026).

Заводит троих прямой вставкой в SQLite (двое в паре, третий посторонний) и
пару в Postgres, гоняет те же запросы, что шлёт приложение, смотрит
будильники в `date_alarms` и убирает за собой.

Каждая проверка ловит свою поломку: дату не видит партнёр, посторонний
читает или правит чужую, автора подменяют, будильник не встал или не снялся.

    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python hp_smoke_pair_dates.py
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


def pg_run(sql: str, *args, fetch=False):
    async def run():
        conn = await asyncpg.connect(PG_DSN)
        try:
            return await (conn.fetch(sql, *args) if fetch else conn.execute(sql, *args))
        finally:
            await conn.close()
    return asyncio.run(run())


def alarms(date_id: str) -> list:
    return pg_run("SELECT uid, minutes, occ FROM date_alarms WHERE kind = 'pair_date' AND ref_id = $1",
                  date_id, fetch=True)


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]

gid = "smpd" + secrets.token_hex(5) + "x"
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
people, headers = [], []
for tag in ("a", "b", "c"):          # третий — посторонний
    uid = f"smd{tag}" + secrets.token_hex(6)
    token_key = secrets.token_hex(25)
    lite.execute(
        "INSERT INTO users (id, email, tokenKey, password, verified, created, updated, group_ids, display_name) "
        "VALUES (?,?,?,?,1,?,?,?,?)",
        (uid, f"{uid}@togetherly.test", token_key, "x", now_s, now_s,
         json.dumps([gid]) if tag != "c" else "[]", f"Проба {tag}"))
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
pg_run("INSERT INTO groups (id, members, disbanded) VALUES ($1, $2::jsonb, false)",
       gid, json.dumps([A, B]))
print(f"пара {gid}: {A} + {B}, посторонний {C}", flush=True)

url = f"{HP}/api/collections/pair_dates/records"
date_id = "smpd" + secrets.token_hex(6)
try:
    r = client.post(url, headers=HA, json={
        "id": date_id, "group_id": gid, "author_uid": A, "title": "Первое свидание",
        "symbol": "favorite", "note": "", "day": "2025-11-08", "start_time": "",
        "tz": "Europe/Kyiv", "rrule": "FREQ=YEARLY", "exdates": [], "reminders": [900, -540]})
    made = r.json() if r.status_code == 200 else {}
    check("дата заводится", made.get("id") == date_id, f"{r.status_code} {r.text[:200]}")
    check("напоминания приходят списком", made.get("reminders") == [900, -540], str(made.get("reminders")))
    r = client.post(url, headers=HA, json={
        "id": "smpd" + secrets.token_hex(6), "group_id": gid, "author_uid": B, "title": "x",
        "day": "2026-01-01"})
    check("от чужого имени не заводится", r.status_code == 400, f"{r.status_code}")
    r = client.post(url, headers=HC, json={
        "id": "smpd" + secrets.token_hex(6), "group_id": gid, "author_uid": C, "title": "x",
        "day": "2026-01-01"})
    check("посторонний не заводит в чужой паре", r.status_code == 400, f"{r.status_code}")

    flt = {"filter": f"group_id = '{gid}'"}
    r = client.get(url, headers=HB, params=flt)
    check("партнёр видит дату", [x["id"] for x in r.json().get("items", [])] == [date_id],
          f"{r.status_code} {r.text[:200]}")
    r = client.get(url, headers=HC, params=flt)
    check("посторонний не видит", r.status_code == 200 and not r.json().get("items"), f"{r.status_code}")

    time.sleep(2)
    a = alarms(date_id)
    check("будильники встали обоим по два", len(a) == 4 and {x["uid"] for x in a} == {A, B},
          str([dict(x) for x in a]))

    r = client.patch(f"{url}/{date_id}", headers=HB, json={"title": "Наше первое свидание",
                                                           "reminders": [900]})
    check("партнёр правит дату", r.status_code == 200 and r.json().get("title") == "Наше первое свидание",
          f"{r.status_code} {r.text[:200]}")
    r = client.patch(f"{url}/{date_id}", headers=HB, json={"author_uid": B})
    check("автора не подменить", r.status_code != 200 or r.json().get("author_uid") == A,
          f"{r.status_code} {r.text[:200]}")
    r = client.patch(f"{url}/{date_id}", headers=HC, json={"title": "чужое"})
    check("посторонний не правит", r.status_code == 404, f"{r.status_code}")
    time.sleep(2)
    a = alarms(date_id)
    check("после правки будильников по одному", len(a) == 2 and all(x["minutes"] == 900 for x in a),
          str([dict(x) for x in a]))

    r = client.delete(f"{url}/{date_id}", headers=HC)
    check("посторонний не удаляет", r.status_code == 404, f"{r.status_code}")
    r = client.delete(f"{url}/{date_id}", headers=HB)
    check("партнёр удаляет", r.status_code == 204, f"{r.status_code} {r.text[:200]}")
    time.sleep(2)
    check("будильники сняты", not alarms(date_id), str(alarms(date_id)))

    # Очередь приложения начинает с правки: 404 на новый id — и тогда создание.
    r = client.patch(f"{url}/smpd{secrets.token_hex(6)}", headers=HA, json={"title": "x"})
    check("правка нового id отвечает 404", r.status_code == 404, f"{r.status_code} {r.text[:120]}")

    # Настоящее срабатывание: дата через три минуты, напоминание за минуту.
    if os.environ.get("FIRE"):
        from datetime import datetime, timedelta, timezone
        начало = (datetime.now(timezone.utc) + timedelta(minutes=3)).replace(second=0, microsecond=0)
        fire_id = "smpd" + secrets.token_hex(6)
        с_какого = time.strftime("%Y-%m-%d %H:%M:%S")
        r = client.post(url, headers=HA, json={
            "id": fire_id, "group_id": gid, "author_uid": A, "title": "Проба напоминания",
            "symbol": "favorite", "day": начало.date().isoformat(),
            "start_time": начало.strftime("%H:%M"), "tz": "UTC", "rrule": "", "reminders": [1]})
        check("дата с напоминанием через 2 минуты заводится", r.status_code == 200, f"{r.status_code}")
        time.sleep(2)
        check("будильник встал обоим", len(alarms(fire_id)) == 2, str(alarms(fire_id)))
        ждать = (начало - timedelta(minutes=1) - datetime.now(timezone.utc)).total_seconds() + 50
        print(f"ждём срабатывания {int(ждать)} с", flush=True)
        time.sleep(max(0, ждать))
        check("будильник забран рассылкой", not alarms(fire_id), str(alarms(fire_id)))
        import subprocess
        журнал = subprocess.run(["journalctl", "-u", "hotpath", "--since", с_какого, "--no-pager", "-o", "cat"],
                                capture_output=True, text=True).stdout
        check("в журнале нет сорвавшихся напоминаний", "сорвалось" not in журнал and "сбой рассылки" not in журнал)
        check("в журнале есть рассылка", "даты: напоминаний" in журнал)
finally:
    for uid in people:
        lite.execute("DELETE FROM users WHERE id = ?", (uid,))
    lite.commit()
    lite.close()
    for sql in ("DELETE FROM pair_dates WHERE group_id = $1",
                "DELETE FROM date_alarms WHERE group_id = $1",
                "DELETE FROM groups WHERE id = $1"):
        try:
            pg_run(sql, gid)
        except asyncpg.PostgresError:
            pass  # таблицы ещё нет — до выкладки проверка и должна падать
    print("тестовые записи убраны", flush=True)

print(f"итог: провалов {len(failures)}" + (f" — {failures}" if failures else ""))
sys.exit(1 if failures else 0)
