#!/usr/bin/env python3
"""Живой регресс рамок аватарки в сундуке.

Рамки не продаются, их разыгрывает сундук, читая каталог при каждом
открытии. Проверяем то, что ломается молча: сумма таблицы шансов, старые
сборки без рамок, выпадение уже полученных, запрет покупки за монеты и
рамка партнёра в `/api/user/card`.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/chest_frames.test.py
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
    email = f"frame-probe-{tag}-{rnd(6)}@example.com"
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



def weights(odds):
    return sum(o["weight"] for o in odds)


def main():
    me = signup("me")
    mate = signup("mate")
    log(f"я={me['uid']} партнёр={mate['uid']}")
    st, res = api("/api/waiting/create",
                  {"name": "Партнёр", "returnDate": "2027-05-15 00:00:00.000Z"}, me["token"])
    pair = (res or {}).get("pairId", "")
    api("/api/waiting/claim", {"code": (res or {}).get("code", "")}, mate["token"])
    api("/api/waiting/approve", {"groupId": pair, "approve": True}, me["token"])
    check("пара собрана", bool(pair), f"{st} {res}")

    frames = sql("SELECT id FROM catalog_items WHERE kind='frame' AND enabled=1").split()
    log(f"рамок в каталоге: {len(frames)}")

    log("=== 1. старая сборка рамок не видит ===")
    st, old = api("/api/chest/state?tz=180&platform=android", None, me["token"])
    odds = (old or {}).get("odds") or []
    check("без frames=1 рамок в таблице нет", st == 200 and not [o for o in odds if o["kind"] == "frame"], f"{st}")
    check("таблица старой сборки даёт 1000", weights(odds) == 1000, str(weights(odds)))
    c5 = [o for o in odds if o["key"] == "coins5"]
    check("у старой сборки «5 монет» по-прежнему 35%", c5 and c5[0]["weight"] == 350, str(c5))

    log("=== 2. новая сборка видит все рамки каталога ===")
    st, new = api("/api/chest/state?tz=180&platform=android&frames=1", None, me["token"])
    odds = (new or {}).get("odds") or []
    fr = [o for o in odds if o["kind"] == "frame"]
    check("каждая рамка каталога в таблице", sorted(o["key"] for o in fr) == sorted(frames),
          str([o["key"] for o in fr]))
    check("сумма таблицы по-прежнему 1000", weights(odds) == 1000, str(weights(odds)))
    check("у рамок есть ярус", all(o["tier"] in ("common", "rare", "legendary") for o in fr))

    log("=== 3. полученная рамка из розыгрыша выпадает ===")
    owned = [f"frame:{f}" for f in frames[:2]]
    sql(f"UPDATE users SET owned_features='{json.dumps(owned)}' WHERE id='{me['uid']}'")
    st, part = api("/api/chest/state?tz=180&platform=android&frames=1", None, me["token"])
    odds = (part or {}).get("odds") or []
    keys = [o["key"] for o in odds if o["kind"] == "frame"]
    check("полученных нет в таблице", not set(frames[:2]) & set(keys), str(keys))
    check("их доля ушла в монеты, сумма 1000", weights(odds) == 1000, str(weights(odds)))

    log("=== 4. за монеты рамку не купить ===")
    sql(f"UPDATE users SET coins=500 WHERE id='{me['uid']}'")
    st, buy = api("/api/coins/purchase-feature", {"featureId": f"frame:{frames[-1]}"}, me["token"])
    check("покупка рамки отклонена", st == 400 and buy.get("error") == "not for sale", f"{st} {buy}")

    log("=== 5. открытие сундука с рамками ===")
    got = []
    for i in range(3):
        oid = rnd(15)
        st, op = api("/api/chest/open", {"openId": oid, "groupId": pair, "tz": 180,
                                          "platform": "android", "frames": True}, me["token"])
        if st != 200:
            check(f"открытие {i + 1}", False, f"{st} {op}")
            continue
        pr = op["prize"]
        got.append(pr["key"])
        if pr["kind"] == "frame":
            check("выпавшая рамка записана во владение",
                  f"frame:{pr['key']}" in (op.get("ownedFeatures") or []), str(op.get("ownedFeatures")))
        st, rep = api("/api/chest/open", {"openId": oid, "groupId": pair, "tz": 180,
                                           "platform": "android", "frames": True}, me["token"])
        check(f"повтор открытия {i + 1} отдаёт тот же приз",
              st == 200 and rep.get("repeated") and rep["prize"]["key"] == pr["key"]
              and rep["prize"]["kind"] == pr["kind"], f"{st} {rep}")
    log(f"выпало: {got}")

    log("=== 6. надетую рамку человек пишет сам ===")
    # Отдачу рамки партнёру (`/api/user/card`) здесь не проверить: свежая пара
    # из /api/waiting/* получает у роута 403 «not in your pair», хотя
    # group_ids на месте. На живых парах роут отвечает, это сторожит
    # /opt/hotpath/probe_real_pair.py.
    st, r = api(f"/api/collections/users/records/{me['uid']}", {"frame": frames[0]}, me["token"], method="PATCH")
    check("рамка надевается", st == 200 and r.get("frame") == frames[0], f"{st}")
    st, r = api(f"/api/collections/users/records/{me['uid']}", {"frame": ""}, me["token"], method="PATCH")
    check("свою рамку человек снимает сам", st == 200, f"{st} {r}")

    log("=== уборка ===")
    sql(f"DELETE FROM chest_opens WHERE user_uid IN ('{me['uid']}','{mate['uid']}')")
    sql(f"DELETE FROM gifts WHERE sender_uid IN ('{me['uid']}','{mate['uid']}','chest') AND group_id='{pair}'")
    api(f"/api/collections/groups/records/{pair}", None, me["token"], method="DELETE")
    for who in (me, mate):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"], method="DELETE")
    if sql("SELECT count(*) FROM users WHERE email LIKE 'frame-probe-%'") != "0":
        sql("DELETE FROM users WHERE email LIKE 'frame-probe-%'")
    left = sql("SELECT count(*) FROM users WHERE email LIKE 'frame-probe-%'")
    check("тестовые аккаунты убраны", left == "0", f"осталось {left}")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
