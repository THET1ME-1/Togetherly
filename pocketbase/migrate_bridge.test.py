#!/usr/bin/env python3
"""Живой регресс: мост паролей Firebase не возвращает старый пароль.

Мост (`/api/migrate/verify-password`) нужен тем, кто после переезда с Firebase
ещё ни разу не вошёл: он сверяет пароль в Firebase и переносит его в
PocketBase. До 10.11.2026 он делал это для любого аккаунта и в любой момент:
человек сменил пароль, а прежний, времён Firebase, по-прежнему открывал
аккаунт — мост ставил его обратно.

Теперь мост закрыт для аккаунта, чей пароль человек уже знает
(`users.password_set` > 0: вошёл по паролю, сменил его по письму или через
партнёра), и сам ставит эту отметку, когда перенёс пароль.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/migrate_bridge.test.py
"""
import json
import os
import random
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8090")
DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
T0 = time.time()
OK, FAIL = [], []


def log(*a):
    print(f"[{time.time() - T0:6.2f}s]", *a, flush=True)


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    log(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""))


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body,
                                 method=method or ("POST" if body else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def sql(query):
    out = subprocess.run(["sqlite3", "-cmd", ".timeout 8000", DB, query],
                         capture_output=True, text=True)
    return out.stdout.strip()


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def main():
    email = f"bridge-probe-{rnd(8)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    try:
        st, r = api("/api/collections/users/records", {
            "email": email, "password": pwd, "passwordConfirm": pwd,
            "display_name": "Probe bridge", "name": "Probe bridge"})
        if st not in (200, 201):
            log(f"!! регистрация: {st} {r}")
            sys.exit(1)
        uid = r["id"]
        st, _ = api("/api/collections/users/auth-with-password",
                    {"identity": email, "password": pwd})
        check("вход по своему паролю", st == 200, f"{st}")
        time.sleep(0.5)
        known = sql(f"SELECT coalesce(password_set, 0) FROM users WHERE id = '{uid}'")
        check("после входа стоит отметка «пароль знает»", known not in ("", "0"), known)

        log("=== 1. аккаунту с известным паролем мост закрыт ===")
        st, res = api("/api/migrate/verify-password",
                      {"email": email, "password": "Old" + rnd(10) + "!"})
        check("мост отвечает отказом без похода в Firebase",
              st == 200 and res.get("ok") is False and res.get("reason") == "password_known",
              f"{st} {res}")

        # Отметка «пароль выдуман сервером» (вход через Google погасил пароль
        # чужой заготовки) мост тоже закрывает.
        sql(f"UPDATE users SET password_set = -1 WHERE id = '{uid}'")
        st, res = api("/api/migrate/verify-password",
                      {"email": email, "password": "Old" + rnd(10) + "!"})
        check("аккаунту с погашенным паролем мост тоже закрыт",
              st == 200 and res.get("reason") == "password_known", f"{st} {res}")

        log("=== 2. кому мост ещё нужен, тому он по-прежнему отвечает ===")
        sql(f"UPDATE users SET password_set = 0 WHERE id = '{uid}'")
        st, res = api("/api/migrate/verify-password",
                      {"email": email, "password": "Old" + rnd(10) + "!"})
        check("без отметки мост спрашивает Firebase и получает «не тот пароль»",
              st == 200 and res.get("ok") is False and res.get("reason") == "bad_credentials",
              f"{st} {res}")

        log("=== 3. свой пароль никуда не делся ===")
        st, _ = api("/api/collections/users/auth-with-password",
                    {"identity": email, "password": pwd})
        check("вход по своему паролю после всех попыток", st == 200, f"{st}")
    finally:
        log("=== уборка ===")
        sql("DELETE FROM users WHERE email LIKE 'bridge-probe-%'")
        left = sql("SELECT count(*) FROM users WHERE email LIKE 'bridge-probe-%'")
        check("тестовый аккаунт убран", left == "0", f"осталось {left}")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
