#!/usr/bin/env python3
"""Проверка экрана «профиль партнёра» на живой паре — только чтение.

Ничего не создаёт и не меняет. Печатает коды ответов и наличие полей, но не
содержимое: переписка и личные данные в вывод не попадают.

    /opt/hotpath/venv/bin/python probe_real_pair.py <uid> <group_id>
"""

import base64
import hashlib
import hmac
import json
import os
import sqlite3
import sys
import time

import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


uid, gid = sys.argv[1], sys.argv[2]
lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]
tk = lite.execute("SELECT tokenKey FROM users WHERE id = ?", (uid,)).fetchone()[0]
lite.close()

h = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
p = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid,
                     "type": "auth", "refreshable": True,
                     "exp": int(time.time()) + 900}).encode())
sig = b64u(hmac.new((tk + secret).encode(), f"{h}.{p}".encode(),
                    hashlib.sha256).digest())
H = {"Authorization": f"{h}.{p}.{sig}"}
c = httpx.Client(timeout=30)

пара = c.get(f"{HP}/api/collections/groups/records/{gid}", headers=H)
print(f"запись пары            : {пара.status_code}")
if пара.status_code != 200:
    print(f"  тело: {пара.text[:200]}")
    sys.exit(1)

данные = пара.json()
состав = данные.get("members") or []
партнёр = next((str(m) for m in состав if str(m) != uid), "")
имена = данные.get("member_names") or {}
аватары = данные.get("member_avatars") or {}
print(f"  участников {len(состав)}, партнёр найден: {'да' if партнёр else 'НЕТ'}")
print(f"  имя партнёра в паре: {'есть' if имена.get(партнёр) else 'ПУСТО'}, "
      f"аватар: {'есть' if аватары.get(партнёр) else 'пусто'}")

if not партнёр:
    print("  партнёра в составе нет — экрану профиля нечего открывать")
    sys.exit(1)

r = c.get(f"{PB}/api/user/card", params={"uid": партнёр}, headers=H)
поля = list(r.json().keys()) if r.status_code == 200 else []
print(f"карточка партнёра      : {r.status_code}, полей {len(поля)}")
if r.status_code != 200:
    print(f"  тело: {r.text[:200]}")

r = c.get(f"{PB}/api/collections/gifts/records", headers=H,
          params={"filter": f'group_id = "{gid}" && recipient_uid = "{партнёр}"',
                  "perPage": 200, "sort": "-created"})
print(f"подарки партнёру       : {r.status_code}"
      + (f", записей {len(r.json().get('items', []))}" if r.status_code == 200
         else f" — {r.text[:200]}"))

r = c.get(f"{HP}/api/collections/miss_you/records", headers=H,
          params={"filter": f'group_id = "{gid}" && user_uid = "{партнёр}"',
                  "perPage": 1, "skipTotal": 1})
print(f"«Скучаю» партнёра      : {r.status_code}"
      + (f", записей {len(r.json().get('items', []))}" if r.status_code == 200
         else f" — {r.text[:200]}"))

r = c.get(f"{HP}/api/collections/mood_entries/records", headers=H,
          params={"filter": f'group_id = "{gid}" && user_uid = "{партнёр}"',
                  "perPage": 5, "sort": "-timestamp"})
print(f"настроения партнёра    : {r.status_code}"
      + (f", записей {len(r.json().get('items', []))}" if r.status_code == 200
         else f" — {r.text[:200]}"))
c.close()
