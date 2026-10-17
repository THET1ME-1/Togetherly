#!/usr/bin/env python3
"""Живой регресс продажи подарка из запаса сундука.

Открытия в запасе заводятся прямо в базе: настоящее открытие требует ролика.
Проверяем цену по редкости, начисление монет, повтор без второго начисления,
отказ по чужому открытию и по уже решённому подарку.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/chest_sell.test.py
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
        with urllib.request.urlopen(req, timeout=25) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def sql(query):
    out = subprocess.run(["sqlite3", DB, query], capture_output=True, text=True)
    return out.stdout.strip()


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"chestsell-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"], "email": email}


def stash(uid, prize, state="stash"):
    """Открытие сундука с выпавшим подарком — как его пишет chest.pb.js."""
    open_id = rnd(15)
    now = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
    sql("INSERT INTO chest_opens (id, user_uid, group_id, day, prize, amount, state, gift_id, created, updated) "
        f"VALUES ('{open_id}', '{uid}', '', 'probe|{rnd(4)}', '{prize}', 0, '{state}', '', '{now}', '{now}')")
    return open_id


def coins(uid):
    return int(sql(f"SELECT coins FROM users WHERE id = '{uid}'") or 0)


def main():
    me, other = signup("me"), signup("other")
    start = coins(me["uid"])

    log("=== обычный подарок ===")
    teddy = stash(me["uid"], "teddy")
    st, res = api("/api/chest/sell", {"openId": teddy}, me["token"])
    check("продан", st == 200 and res.get("ok") is True and res.get("price") == 5, f"{st} {res}")
    check("монеты начислены", coins(me["uid"]) == start + 5, f"{coins(me['uid'])}")
    check("открытие помечено sold", sql(f"SELECT state FROM chest_opens WHERE id = '{teddy}'") == "sold")

    st, res = api("/api/chest/sell", {"openId": teddy}, me["token"])
    check("повтор отвечает тем же балансом", st == 200 and res.get("repeated") is True
          and res.get("coins") == start + 5, f"{st} {res}")
    check("второго начисления нет", coins(me["uid"]) == start + 5)

    log("=== редкий и легендарный ===")
    record = stash(me["uid"], "record")
    st, res = api("/api/chest/sell", {"openId": record}, me["token"])
    check("редкий за 10", st == 200 and res.get("price") == 10, f"{st} {res}")
    rings = stash(me["uid"], "rings")
    st, res = api("/api/chest/sell", {"openId": rings}, me["token"])
    check("легендарный за 25", st == 200 and res.get("price") == 25, f"{st} {res}")
    check("итог на счету", coins(me["uid"]) == start + 40, f"{coins(me['uid'])}")

    log("=== отказы ===")
    kept = stash(me["uid"], "teddy", state="kept")
    st, res = api("/api/chest/sell", {"openId": kept}, me["token"])
    check("оставленный себе не продаётся", st == 409 and res.get("error") == "already_used", f"{st} {res}")
    foreign = stash(other["uid"], "teddy")
    st, res = api("/api/chest/sell", {"openId": foreign}, me["token"])
    check("чужое открытие не найти", st == 404 and res.get("error") == "not_found", f"{st} {res}")
    check("у владельца чужого открытия ничего не ушло",
          sql(f"SELECT state FROM chest_opens WHERE id = '{foreign}'") == "stash")
    st, res = api("/api/chest/sell", {"openId": "плохой"}, me["token"])
    check("кривой номер отклонён", st == 400 and res.get("error") == "bad_request", f"{st} {res}")
    st, res = api("/api/chest/sell", {"openId": teddy})
    check("без входа нельзя", st in (401, 403), f"{st}")

    log("=== уборка ===")
    sql(f"DELETE FROM chest_opens WHERE user_uid IN ('{me['uid']}', '{other['uid']}')")
    for who in (me, other):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"], method="DELETE")
    if sql("SELECT count(*) FROM users WHERE email LIKE 'chestsell-probe-%'") != "0":
        sql("DELETE FROM users WHERE email LIKE 'chestsell-probe-%'")
    check("тестовые аккаунты убраны",
          sql("SELECT count(*) FROM users WHERE email LIKE 'chestsell-probe-%'") == "0")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  упало:", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
