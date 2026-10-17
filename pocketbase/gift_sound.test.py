#!/usr/bin/env python3
"""Живой регресс звука к «Песне».

Проверяем, что кусок песни дарителя доходит до записи подарка вместе с
волной, что получатель открывает сам файл, и что сервер не берёт чужое:
файл другой пары, внешнюю ссылку, звук к «Сердцу» и битый meta.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/gift_sound.test.py
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
import uuid

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8090")
DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
T0 = time.time()
OK, FAIL = [], []

# Короткий m4a не нужен: PocketBase принимает любой файл, тип пишет по содержимому
SOUND = b"\x00\x00\x00\x18ftypM4A \x00\x00\x02\x00M4A isomiso2" + b"\x00" * 64
PEAKS = "1234567890123456789012345678901234567890"
META = json.dumps({"ms": 20000, "peaks": PEAKS, "kind": "song",
                   "title": "  Lovely   Day ", "artist": "Bill Withers", "лишнее": "x"})


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
    """Загружает звук в `media` так же, как приложение, и отдаёт pb://-ссылку."""
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in (("uid", uid), ("group_id", group_id), ("kind", "gift")):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; "
                     f"name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
                 f"filename=\"sound.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".encode()
                 + SOUND + b"\r\n")
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
    email = f"giftsound-probe-{tag}-{rnd(6)}@example.com"
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


def send(who, pair, key, sound, meta=META):
    return api("/api/gifts/send", {
        "giftId": gift_id(), "groupId": pair, "giftKey": key,
        "sound": sound, "soundMeta": meta, "ad": True}, who["token"])


def main():
    her, him = signup("dar"), signup("pol")
    x, y = signup("chu1"), signup("chu2")
    pair = pair_of(her, him)
    other = pair_of(x, y)
    check("пары собраны", bool(pair) and bool(other), f"{pair} {other}")

    media, sound = upload(her["token"], her["uid"], pair)
    foreign_media, foreign = upload(x["token"], x["uid"], other)
    log(f"звук пары {sound}, чужой {foreign}")

    log("=== «Песня» со своим звуком ===")
    gid = gift_id()
    st, res = api("/api/gifts/send", {"giftId": gid, "groupId": pair, "giftKey": "song",
                                       "sound": sound, "soundMeta": META, "ad": True},
                  her["token"])
    check("подарок ушёл", st == 200 and res.get("ok") is True, f"{st} {res}")
    check("звук лёг в запись подарка", sql(f"SELECT sound FROM gifts WHERE id = '{gid}'") == sound)
    stored = json.loads(sql(f"SELECT sound_meta FROM gifts WHERE id = '{gid}'") or "{}")
    check("meta записан начисто",
          stored == {"ms": 20000, "peaks": PEAKS, "kind": "song",
                     "title": "Lovely Day", "artist": "Bill Withers"}, f"{stored}")
    st, rec = api(f"/api/collections/gifts/records/{gid}", None, him["token"])
    check("получатель видит звук", st == 200 and rec.get("sound") == sound, f"{st}")
    st, tok = api("/api/files/token", {}, him["token"])
    fname = sound.rsplit("/", 1)[1]
    req = urllib.request.Request(
        f"{BASE}/api/files/media/{media}/{fname}?token={tok.get('token', '')}")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            got = r.status
    except urllib.error.HTTPError as e:
        got = e.code
    check("получатель открывает сам файл", got == 200, f"{got}")

    log("=== отказы ===")
    st, res = send(her, pair, "song", foreign)
    check("звук чужой пары не принят", st == 400 and res.get("error") == "bad_sound", f"{st} {res}")
    st, res = send(her, pair, "song", "https://example.com/x.m4a")
    check("внешняя ссылка не принята", st == 400 and res.get("error") == "bad_sound", f"{st} {res}")
    st, res = send(her, pair, "heart", sound)
    check("к «Сердцу» звук не прикладывается", st == 400 and res.get("error") == "bad_sound", f"{st} {res}")
    st, res = send(her, pair, "song", sound, meta="{битый")
    check("битый meta не принят", st == 400 and res.get("error") == "bad_sound", f"{st} {res}")
    long_meta = json.dumps({"ms": 600000, "peaks": PEAKS, "kind": "song"})
    st, res = send(her, pair, "song", sound, meta=long_meta)
    check("десять минут не принимаются", st == 400 and res.get("error") == "bad_sound", f"{st} {res}")
    gid2 = gift_id()
    st, res = api("/api/gifts/send", {"giftId": gid2, "groupId": pair,
                                       "giftKey": "song", "note": "без звука", "ad": True},
                  her["token"])
    check("«Песня» без звука уходит как раньше",
          st == 200 and res.get("ok") is True
          and sql(f"SELECT sound FROM gifts WHERE id = '{gid2}'") == "", f"{st} {res}")

    log("=== уборка ===")
    sql(f"DELETE FROM gifts WHERE group_id IN ('{pair}', '{other}')")
    api(f"/api/collections/media/records/{media}", None, her["token"], method="DELETE")
    api(f"/api/collections/media/records/{foreign_media}", None, x["token"], method="DELETE")
    for p, owner in ((pair, her), (other, x)):
        api(f"/api/collections/groups/records/{p}", None, owner["token"], method="DELETE")
    for who in (her, him, x, y):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"], method="DELETE")
    if sql("SELECT count(*) FROM users WHERE email LIKE 'giftsound-probe-%'") != "0":
        sql("DELETE FROM users WHERE email LIKE 'giftsound-probe-%'")
    check("тестовые аккаунты убраны",
          sql("SELECT count(*) FROM users WHERE email LIKE 'giftsound-probe-%'") == "0")
    check("тестовые файлы убраны",
          sql(f"SELECT count(*) FROM media WHERE id IN ('{media}', '{foreign_media}')") == "0")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  упало:", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
