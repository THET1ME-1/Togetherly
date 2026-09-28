#!/usr/bin/env python3
"""Живой регресс снимка к «Кадру».

Проверяем, что снимок дарителя доходит до записи подарка и что сервер не
берёт чужой файл: другой пары, внешнюю ссылку и снимок к подарку, которому он
не положен.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/gift_photo.test.py
"""
import base64
import json
import os
import random
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8090")
DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
T0 = time.time()
OK, FAIL = [], []

# Картинка 1×1: настоящий PNG, чтобы PocketBase принял файл.
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA"
    "hKmMIQAAAABJRU5ErkJggg==")


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


def upload(token, uid, group_id):
    """Загружает снимок в `media` так же, как приложение, и отдаёт pb://-ссылку."""
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in (("uid", uid), ("group_id", group_id), ("kind", "gift")):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; "
                     f"name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
                 f"filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\n".encode()
                 + PNG + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    req = urllib.request.Request(BASE + "/api/collections/media/records",
                                 data=b"".join(parts), method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Authorization", token)
    with urllib.request.urlopen(req, timeout=25) as r:
        rec = json.loads(r.read().decode())
    return rec["id"], f"pb://media/{rec['id']}/{rec['file']}"


def sql(query):
    out = subprocess.run(["sqlite3", DB, query], capture_output=True, text=True)
    return out.stdout.strip()


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def gift_id():
    return rnd(15)


def signup(tag):
    email = f"giftphoto-probe-{tag}-{rnd(6)}@example.com"
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


def pair_of(a, b):
    st, res = api("/api/waiting/create",
                  {"name": "Партнёр", "returnDate": "2027-05-15 00:00:00.000Z"},
                  a["token"])
    pair = (res or {}).get("pairId", "")
    api("/api/waiting/claim", {"code": (res or {}).get("code", "")}, b["token"])
    api("/api/waiting/approve", {"groupId": pair, "approve": True}, a["token"])
    return pair


def send(who, pair, key, photo):
    return api("/api/gifts/send", {
        "giftId": gift_id(), "groupId": pair, "giftKey": key,
        "photo": photo, "ad": True}, who["token"])


def main():
    her, him = signup("dar"), signup("pol")
    x, y = signup("chu1"), signup("chu2")
    pair = pair_of(her, him)
    other = pair_of(x, y)
    check("пары собраны", bool(pair) and bool(other), f"{pair} {other}")

    media, photo = upload(her["token"], her["uid"], pair)
    foreign_media, foreign = upload(x["token"], x["uid"], other)
    log(f"снимок пары {photo}, чужой {foreign}")

    log("=== «Кадр» со своим снимком ===")
    gid = gift_id()
    st, res = api("/api/gifts/send", {"giftId": gid, "groupId": pair,
                                       "giftKey": "photo", "photo": photo,
                                       "ad": True}, her["token"])
    check("подарок ушёл", st == 200 and res.get("ok") is True, f"{st} {res}")
    check("снимок лёг в запись подарка",
          sql(f"SELECT photo FROM gifts WHERE id = '{gid}'") == photo)
    st, rec = api(f"/api/collections/gifts/records/{gid}", None, him["token"])
    check("получатель видит ссылку", st == 200 and rec.get("photo") == photo, f"{st}")
    st, tok = api("/api/files/token", {}, him["token"])
    fname = photo.rsplit("/", 1)[1]
    req = urllib.request.Request(
        f"{BASE}/api/files/media/{media}/{fname}?token={tok.get('token', '')}")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            got = r.status
    except urllib.error.HTTPError as e:
        got = e.code
    check("получатель открывает сам файл", got == 200, f"{got}")

    log("=== отказы ===")
    st, res = send(her, pair, "photo", foreign)
    check("снимок чужой пары не принят", st == 400 and res.get("error") == "bad_photo", f"{st} {res}")
    st, res = send(her, pair, "photo", "https://example.com/x.jpg")
    check("внешняя ссылка не принята", st == 400 and res.get("error") == "bad_photo", f"{st} {res}")
    st, res = send(her, pair, "heart", photo)
    check("к «Сердцу» снимок не прикладывается", st == 400 and res.get("error") == "bad_photo", f"{st} {res}")
    gid2 = gift_id()
    st, res = api("/api/gifts/send", {"giftId": gid2, "groupId": pair,
                                       "giftKey": "photo", "ad": True}, her["token"])
    check("«Кадр» без снимка уходит как раньше",
          st == 200 and res.get("ok") is True
          and sql(f"SELECT photo FROM gifts WHERE id = '{gid2}'") == "", f"{st} {res}")

    log("=== уборка ===")
    sql(f"DELETE FROM gifts WHERE group_id IN ('{pair}', '{other}')")
    api(f"/api/collections/media/records/{media}", None, her["token"], method="DELETE")
    api(f"/api/collections/media/records/{foreign_media}", None, x["token"], method="DELETE")
    for p, owner in ((pair, her), (other, x)):
        api(f"/api/collections/groups/records/{p}", None, owner["token"], method="DELETE")
    for who in (her, him, x, y):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"], method="DELETE")
    if sql("SELECT count(*) FROM users WHERE email LIKE 'giftphoto-probe-%'") != "0":
        sql("DELETE FROM users WHERE email LIKE 'giftphoto-probe-%'")
    check("тестовые аккаунты убраны",
          sql("SELECT count(*) FROM users WHERE email LIKE 'giftphoto-probe-%'") == "0")
    check("тестовые снимки убраны",
          sql(f"SELECT count(*) FROM media WHERE id IN ('{media}', '{foreign_media}')") == "0")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  упало:", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
