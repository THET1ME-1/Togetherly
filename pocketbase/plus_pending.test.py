#!/usr/bin/env python3
"""Живая проверка автовыдачи оплаченного (pb_hooks/plus_pending.pb.js).

Проверяет то, ради чего хук написан: человек оплатил на почту, аккаунта с ней
ещё не было — и Togetherly+ включается сам, без кода и переписки с поддержкой.

Гоняется на сервере, за собой убирает:
    python3 plus_pending.test.py
"""

import json
import secrets
import sqlite3
import sys
import time

import httpx

PB = "http://127.0.0.1:8090"
DB = "/opt/pocketbase/pb_data/data.db"
ок, плохо = [], []


def проверка(имя, условие, добавка=""):
    (ок if условие else плохо).append(имя)
    print(("ОК   " if условие else "ПЛОХО") + f" {имя} {добавка}", flush=True)


почта = f"probe{secrets.token_hex(4)}@togetherly.test"
# домен в платеже и домен входа намеренно разные: ровно так путают в жизни
почта_платежа = почта.split("@")[0] + "@oplata.test"
код = "TG" + secrets.token_hex(4).upper()
сейчас = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
rid = secrets.token_hex(7) + "a"

lite = sqlite3.connect(DB, timeout=60)
lite.execute("PRAGMA busy_timeout=60000")
lite.execute(
    "INSERT INTO redeem_codes (id, code, plus, coins, buyer_email, sku, "
    "order_key, created, updated) VALUES (?,?,?,?,?,?,?,?,?)",
    (rid, код, 1, 0, почта_платежа, "ec861b44-проба", "PROBE" + secrets.token_hex(4),
     сейчас, сейчас))
lite.commit()
print(f"заведён код {код} на почту платежа {почта_платежа},\n"
      f"а входить будем с {почта}\n", flush=True)

c = httpx.Client(timeout=30)
uid = ""
try:
    пароль = secrets.token_hex(8) + "Aa1!"
    r = c.post(f"{PB}/api/collections/users/records", json={
        "email": почта, "password": пароль, "passwordConfirm": пароль,
        "display_name": "Проба выдачи",
    })
    проверка("регистрация проходит", r.status_code == 200,
             "" if r.status_code == 200 else r.text[:200])
    if r.status_code != 200:
        raise SystemExit(1)
    uid = r.json()["id"]
    time.sleep(1.5)

    row = lite.execute(
        "SELECT plus, coalesce(plus_platform,''), coalesce(last_plus_grant_ms,0) "
        "FROM users WHERE id = ?", (uid,)).fetchone()
    проверка("Togetherly+ включился сам", bool(row and row[0]),
             f"plus={row[0] if row else '?'}")
    проверка("канал оплаты записан", bool(row and row[1] == "lava"),
             f"plus_platform={row[1] if row else '?'!r}")
    проверка("время выдачи проставлено", bool(row and row[2]),
             f"last_plus_grant_ms={row[2] if row else 0}")

    погашен = lite.execute(
        "SELECT coalesce(used_by,''), coalesce(used_at,0) FROM redeem_codes "
        "WHERE code = ?", (код,)).fetchone()
    проверка("код погашен и привязан к человеку",
             bool(погашен and погашен[0] == uid), f"used_by={погашен[0]!r}")

    # второй вход не должен ничего задваивать
    r = c.post(f"{PB}/api/collections/users/auth-with-password",
               json={"identity": почта, "password": пароль})
    проверка("вход после выдачи проходит", r.status_code == 200,
             "" if r.status_code == 200 else r.text[:150])
    сколько = lite.execute(
        "SELECT count(*) FROM redeem_codes WHERE code = ? AND used_by = ?",
        (код, uid)).fetchone()[0]
    проверка("повторный вход код не задваивает", сколько == 1)
finally:
    if uid:
        lite.execute("DELETE FROM users WHERE id = ?", (uid,))
    lite.execute("DELETE FROM redeem_codes WHERE code = ?", (код,))
    lite.commit()
    lite.close()
    c.close()
    print("\nтестовые записи убраны", flush=True)

print(f"\nитог: пройдено {len(ок)}, провалено {len(плохо)}"
      + (f" — {плохо}" if плохо else ""))
sys.exit(1 if плохо else 0)
