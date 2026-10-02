#!/usr/bin/env python3
"""Живой регресс передачи рамки партнёру (`pb_hooks/frame_gift.pb.js`).

Рамка переходит целиком: у дарителя пропадает (надетая снимается), у партнёра
появляется, монеты списываются по редкости, ролик делит лимит с подарками
за рекламу. Повтор того же `giftId` ничего не двигает.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/frame_gift.test.py
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
    email = f"framegift-probe-{tag}-{rnd(6)}@example.com"
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


def owned(uid):
    return json.loads(sql(f"SELECT owned_features FROM users WHERE id='{uid}'") or "[]")


def coins(uid):
    return int(sql(f"SELECT coins FROM users WHERE id='{uid}'") or 0)


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

    rows = sql("SELECT id, json_extract(data,'$.key'), json_extract(data,'$.rarity') "
               "FROM catalog_items WHERE kind='frame' AND enabled=1 ORDER BY sort").splitlines()
    frames = [r.split("|") for r in rows]
    if len(frames) < 3:
        log("!! в каталоге меньше трёх рамок")
        sys.exit(1)
    (id1, k1, r1), (id2, k2, _), (id3, k3, _) = frames[:3]
    price1 = {"common": 20, "rare": 40, "legendary": 60}.get(r1, 20)
    sql(f"UPDATE users SET owned_features='{json.dumps(['frame:' + id1, 'frame:' + id2, 'frame:' + id3])}', "
        f"coins=100, frame='{k1}' WHERE id='{me['uid']}'")

    log("=== 1. цена и проверка до ролика ===")
    st, q = api(f"/api/frames/gift-quote?key={k1}&groupId={pair}", None, me["token"])
    check("цена по редкости", st == 200 and q.get("price") == price1, f"{st} {q}")
    check("рамка моя, у партнёра нет", q.get("owns") and not q.get("partnerHas"), str(q))
    check("роликов на сегодня три", q.get("adLeft") == 3, str(q))
    st, q = api(f"/api/frames/gift-quote?key={k1}&groupId={pair}", None, mate["token"])
    check("партнёр видит, что рамки у него нет", st == 200 and not q.get("owns"), f"{st} {q}")

    log("=== 2. отдать за монеты ===")
    gid = rnd(15)
    st, r = api("/api/frames/give", {"giftId": gid, "groupId": pair, "key": k1}, me["token"])
    check("рамка ушла", st == 200 and r.get("ok"), f"{st} {r}")
    check("монеты списаны по цене", r.get("coins") == 100 - price1 and coins(me["uid"]) == 100 - price1,
          f"{r.get('coins')} / {coins(me['uid'])}")
    check("у дарителя рамки нет", "frame:" + id1 not in owned(me["uid"]), str(owned(me["uid"])))
    check("ответ отдаёт покупки без неё", "frame:" + id1 not in (r.get("ownedFeatures") or []))
    check("надетая отданная рамка снята", sql(f"SELECT frame FROM users WHERE id='{me['uid']}'") == "",
          sql(f"SELECT frame FROM users WHERE id='{me['uid']}'"))
    check("у партнёра рамка есть", "frame:" + id1 in owned(mate["uid"]), str(owned(mate["uid"])))
    rec = sql(f"SELECT gift_key, state, price, recipient_uid FROM gifts WHERE id='{gid}'")
    check("партнёру пришёл подарок-рамка", rec == f"frame_{k1}|sent|{price1}|{mate['uid']}", rec)

    st, r = api("/api/frames/give", {"giftId": gid, "groupId": pair, "key": k1}, me["token"])
    check("повтор того же giftId ничего не двигает",
          st == 200 and r.get("repeated") and coins(me["uid"]) == 100 - price1, f"{st} {r}")

    st, r = api("/api/frames/give", {"giftId": rnd(15), "groupId": pair, "key": k1}, me["token"])
    check("отданную второй раз не отдать", st == 409 and r.get("error") == "not_owned", f"{st} {r}")

    log("=== 3. рамка, которая у партнёра уже есть ===")
    sql(f"UPDATE users SET owned_features='{json.dumps(owned(mate['uid']) + ['frame:' + id2])}' "
        f"WHERE id='{mate['uid']}'")
    st, q = api(f"/api/frames/gift-quote?key={k2}&groupId={pair}", None, me["token"])
    check("проверка видит, что у партнёра есть", q.get("partnerHas") is True, str(q))
    st, r = api("/api/frames/give", {"giftId": rnd(15), "groupId": pair, "key": k2}, me["token"])
    check("передача отклонена partner_has", st == 409 and r.get("error") == "partner_has", f"{st} {r}")
    check("рамка осталась у дарителя", "frame:" + id2 in owned(me["uid"]))

    log("=== 4. за ролик и лимит ===")
    sql(f"UPDATE users SET coins=0 WHERE id='{me['uid']}'")
    st, r = api("/api/frames/give", {"giftId": rnd(15), "groupId": pair, "key": k3}, me["token"])
    check("без монет не уходит", st == 402 and r.get("error") == "insufficient", f"{st} {r}")
    gid3 = rnd(15)
    st, r = api("/api/frames/give", {"giftId": gid3, "groupId": pair, "key": k3, "ad": True}, me["token"])
    check("за ролик уходит бесплатно", st == 200 and r.get("ok") and coins(me["uid"]) == 0, f"{st} {r}")
    check("подарок за ролик с нулевой ценой",
          sql(f"SELECT price FROM gifts WHERE id='{gid3}'") == "0")
    st, q = api(f"/api/frames/gift-quote?key={k2}&groupId={pair}", None, me["token"])
    check("ролик съел одну попытку из трёх", q.get("adLeft") == 2, str(q))

    log("=== 5. чужой не может дарить в пару ===")
    stranger = signup("x")
    sql(f"UPDATE users SET owned_features='{json.dumps(['frame:' + id2])}', coins=100 WHERE id='{stranger['uid']}'")
    st, r = api("/api/frames/give", {"giftId": rnd(15), "groupId": pair, "key": k2}, stranger["token"])
    check("не участник пары получает 403", st == 403 and r.get("error") == "not_member", f"{st} {r}")
    st, r = api("/api/frames/give", {"giftId": rnd(15), "groupId": pair, "key": "nope"}, me["token"])
    check("незнакомая рамка 404", st == 404, f"{st} {r}")

    log("=== 6. отклик закрывает подарок ===")
    st, r = api("/api/gifts/react", {"giftId": gid}, mate["token"])
    check("отклик засчитан", st == 200 and r.get("ok"), f"{st} {r}")
    check("подарок больше не ждёт", sql(f"SELECT state FROM gifts WHERE id='{gid}'") == "reacted")

    log("=== уборка ===")
    sql(f"DELETE FROM gifts WHERE group_id='{pair}'")
    api(f"/api/collections/groups/records/{pair}", None, me["token"], method="DELETE")
    for who in (me, mate, stranger):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"], method="DELETE")
    if sql("SELECT count(*) FROM users WHERE email LIKE 'framegift-probe-%'") != "0":
        sql("DELETE FROM users WHERE email LIKE 'framegift-probe-%'")
    left = sql("SELECT count(*) FROM users WHERE email LIKE 'framegift-probe-%'")
    check("тестовые аккаунты убраны", left == "0", f"осталось {left}")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
