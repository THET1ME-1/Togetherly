#!/usr/bin/env python3
"""Смоук: значок Togetherly+ в карточке widget_data догоняет покупку.

Обращение в канале 23.10.2026: «В приложении написано, что Плюс достаточно
купить одному, купили, а теперь говорит, что нужно купить и второму». Телефон
партнёра узнаёт о Плюсе купившего по `widget_data.plus`. Флаг ставил сервер,
но при правке карточки только тогда, когда приложение само присылало поле
`plus`, а оно его не шлёт. Купивший после того, как карточка завелась,
навсегда оставался для партнёра без Плюса: 673 человека из 773 на 23.10.2026.

Человек вставляется прямо в SQLite PB, токен подписывается тем же ключом, что
у PocketBase (см. hp_smoke4). За собой убирает.

    /opt/hotpath/venv/bin/python /opt/hotpath/hp_smoke_widget_plus.py
"""
import base64
import hashlib
import hmac
import json
import secrets
import sqlite3
import sys
import time

import httpx

HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"
c = httpx.Client(timeout=30)
fails = []


def check(name, ok, extra=""):
    print(("OK  " if ok else "FAIL") + f" {name} {extra}", flush=True)
    if not ok:
        fails.append(name)


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
secret = json.loads(
    lite.execute("SELECT options FROM _collections WHERE name='users'").fetchone()[0]
)["authToken"]["secret"]
gid = "hpsmokewp" + secrets.token_hex(3)
now_s = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())


def mk_user(tag):
    uid = f"hpwp{tag}" + secrets.token_hex(5)
    tk = secrets.token_hex(25)
    lite.execute(
        "INSERT INTO users (id, email, tokenKey, password, verified, created, updated, "
        "group_ids, plus) VALUES (?,?,?,?,1,?,?,?,0)",
        (uid, f"{uid}@togetherly.test", tk, "direct-insert", now_s, now_s,
         json.dumps([gid])),
    )
    h = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                         "refreshable": True, "exp": int(time.time()) + 3600}).encode())
    sig = b64u(hmac.new((tk + secret).encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return uid, {"Authorization": f"{h}.{p}.{sig}"}


def set_plus(uid, value):
    lite.execute("UPDATE users SET plus = ? WHERE id = ?", (value, uid))
    lite.commit()


ua, HA = mk_user("a")
ub, HB = mk_user("b")
lite.commit()
print(f"пара: {ua} + {ub}, группа {gid}", flush=True)
wid = ""

try:
    r = c.post(f"{HP}/api/collections/widget_data/records", headers=HA,
               json={"group_id": gid, "user_uid": ua, "status": "до покупки"})
    check("карточка заведена без Плюса", r.status_code == 200 and r.json().get("plus") is False,
          r.text[:160] if r.status_code != 200 else "")
    wid = r.json().get("id", "")

    set_plus(ua, 1)  # купил Togetherly+ после того, как карточка завелась
    r = c.patch(f"{HP}/api/collections/widget_data/records/{wid}", headers=HA,
                json={"status": "после покупки"})
    check("правка без поля plus подтягивает покупку", r.status_code == 200
          and r.json().get("plus") is True, f"(plus={r.json().get('plus')})")

    r = c.get(f"{HP}/api/collections/widget_data/records", headers=HB,
              params={"filter": f"group_id = '{gid}' && user_uid = '{ua}'"})
    items = r.json().get("items", []) if r.status_code == 200 else []
    check("партнёр видит Плюс купившего", bool(items) and items[0].get("plus") is True,
          f"(items={[i.get('plus') for i in items]})")

    # Правило widget_data пускает править карточку любого из пары: флаг
    # обязан браться у хозяина карточки, а не у того, кто правит.
    r = c.patch(f"{HP}/api/collections/widget_data/records/{wid}", headers=HB,
                json={"message": "от партнёра без Плюса"})
    if r.status_code == 200:
        check("правка партнёра не снимает Плюс хозяину", r.json().get("plus") is True,
              f"(plus={r.json().get('plus')})")

    r = c.patch(f"{HP}/api/collections/widget_data/records/{wid}", headers=HA,
                json={"status": "вру", "plus": False})
    check("приписать себе «без Плюса» тоже нельзя", r.json().get("plus") is True)

    set_plus(ua, 0)  # возврат денег
    r = c.patch(f"{HP}/api/collections/widget_data/records/{wid}", headers=HA,
                json={"status": "после возврата"})
    check("после возврата значок снимается", r.json().get("plus") is False,
          f"(plus={r.json().get('plus')})")

    r = c.patch(f"{HP}/api/collections/widget_data/records/{wid}", headers=HA,
                json={"status": "вру", "plus": True})
    check("подделка Плюса отбита", r.json().get("plus") is False)

    # Купил и ничего в карточке не правит: значок обязан доехать до партнёра
    # сам, фоновая сверка идёт раз в минуту.
    set_plus(ua, 1)
    seen = None
    for _ in range(20):
        time.sleep(5)
        r = c.get(f"{HP}/api/collections/widget_data/records", headers=HB,
                  params={"filter": f"group_id = '{gid}' && user_uid = '{ua}'"})
        items = r.json().get("items", []) if r.status_code == 200 else []
        seen = items[0].get("plus") if items else None
        if seen is True:
            break
    check("покупка без правки карточки доезжает до партнёра", seen is True, f"(plus={seen})")
finally:
    if wid:
        c.delete(f"{HP}/api/collections/widget_data/records/{wid}", headers=HA)
    lite.execute("DELETE FROM users WHERE id IN (?,?)", (ua, ub))
    lite.commit()
    lite.close()
    print("тестовые записи удалены", flush=True)

print("\nИТОГ:", "все проверки прошли" if not fails else f"ПРОВАЛЫ: {fails}")
sys.exit(1 if fails else 0)
