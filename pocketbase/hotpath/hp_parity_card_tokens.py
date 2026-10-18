#!/usr/bin/env python3
"""Сверка карточки партнёра и токенов Centrifugo: hotpath против PocketBase.

Берёт живые пары, выписывает участникам токены входа тем же ключом, что
PocketBase (ничего не пишет), и шлёт одни и те же запросы в PocketBase
(127.0.0.1:8090) и hotpath (127.0.0.1:8120):

* карточка партнёра, своя, чужого человека, несуществующего, без uid;
* токен подключения: те же поля, подпись hotpath сходится с секретом;
* пропуски в каналы: своя пара, рисование, свой и партнёрский личный канал,
  чужой, геопозиция своя и чужая, комната просмотра своей пары и выдуманная,
  чужая пара, пустой канал — решения «пустить» обязаны совпасть.

Код комнаты считается тем же способом, что в hotpath, поэтому у него есть
контроль: PocketBase обязан пустить в комнату по этому коду, иначе расчёт
разошёлся с watch.pb.js.

    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python hp_parity_card_tokens.py [--pairs 30]
"""

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import sys
import time

import asyncpg
import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"
ABC = "abcdefghjkmnpqrstuvwxyz23456789"


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def auth_token(uid: str, token_key: str, secret: str) -> str:
    head = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                            "refreshable": False, "exp": int(time.time()) + 900}).encode())
    sig = b64u(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                        hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def cent_secret() -> str:
    text = open("/etc/systemd/system/pocketbase.service.d/centrifugo.conf").read()
    m = re.search(r'CENTRIFUGO_TOKEN_HMAC=([^"\s]+)', text)
    return m.group(1) if m else ""


def claims(token: str) -> dict:
    body = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))


def signed_by(token: str, secret: str) -> bool:
    head, body, sig = token.split(".")
    want = b64u(hmac.new(secret.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return hmac.compare_digest(want, sig)


def room_code(group_id: str, secret: str) -> str:
    digest = hmac.new(secret.encode(), group_id.encode(), hashlib.sha256).hexdigest()
    return "".join(ABC[ord(ch) % len(ABC)] for ch in digest[:8])


async def pairs(n: int) -> list:
    conn = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    try:
        rows = await conn.fetch(
            "SELECT id, members FROM groups WHERE NOT coalesce(disbanded, false) "
            "AND jsonb_array_length(members) = 2 ORDER BY updated DESC LIMIT $1", n)
    finally:
        await conn.close()
    out = []
    for r in rows:
        m = r["members"]
        m = json.loads(m) if isinstance(m, str) else m
        out.append((r["id"], str(m[0]), str(m[1])))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pairs", type=int, default=30)
    args = ap.parse_args()

    secret_c = cent_secret()
    lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
    secret_u = json.loads(lite.execute(
        "SELECT options FROM _collections WHERE name='users'").fetchone()[0])["authToken"]["secret"]
    found = asyncio.run(pairs(args.pairs))
    client = httpx.Client(timeout=60)
    bad, total, room_ok = [], 0, 0

    def both(method, path, h, **kw):
        nonlocal total
        total += 1
        return (client.request(method, f"{PB}{path}", headers=h, **kw),
                client.request(method, f"{HP}{path}", headers=h, **kw))

    stranger = found[-1][1] if found else ""
    foreign_gid = found[-1][0] if found else ""
    for i, (gid, a, b) in enumerate(found[:-1]):
        row = lite.execute("SELECT tokenKey FROM users WHERE id = ?", (a,)).fetchone()
        if not row:
            continue
        h = {"Authorization": auth_token(a, row[0], secret_u)}
        label = f"{a[:6]}…"

        for name, params in (("карточка партнёра", {"uid": b}), ("своя карточка", {"uid": a}),
                             ("карточка чужого", {"uid": stranger}),
                             ("карточка несуществующего", {"uid": "nosuchuser00000"}),
                             ("карточка без uid", {})):
            p, q = both("GET", "/api/user/card", h, params=params)
            if p.status_code != q.status_code:
                bad.append(f"{label} {name}: код {p.status_code} против {q.status_code}")
            elif p.status_code == 200 and p.json() != q.json():
                keys = sorted(k for k in set(p.json()) | set(q.json())
                              if p.json().get(k) != q.json().get(k))
                bad.append(f"{label} {name}: поля {keys}")

        p, q = both("POST", "/api/centrifugo/connection-token", h, json={})
        if p.status_code != q.status_code:
            bad.append(f"{label} токен подключения: код {p.status_code} против {q.status_code}")
        elif p.status_code == 200:
            cp, cq = claims(p.json()["token"]), claims(q.json()["token"])
            if {k: v for k, v in cp.items() if k != "exp"} != {k: v for k, v in cq.items() if k != "exp"} \
                    or abs(cp["exp"] - cq["exp"]) > 5 or not signed_by(q.json()["token"], secret_c):
                bad.append(f"{label} токен подключения: поля или подпись разошлись")

        code = room_code(gid, secret_c)
        channels = [f"pair:{gid}", f"draw:{gid}", f"user:{a}", f"user:{b}", f"user:{stranger}",
                    f"loc:pair_{a}_{b}", "loc:pair_xxxxxxxxxxxxxxx_yyyyyyyyyyyyyyy",
                    f"watch:{code}", "watch:zzzzzzzz", f"pair:{foreign_gid}", ""]
        for channel in channels:
            p, q = both("POST", "/api/centrifugo/subscription-token", h, json={"channel": channel})
            if channel == f"watch:{code}" and p.status_code == 200:
                room_ok += 1
            if p.status_code != q.status_code:
                bad.append(f"{label} канал {channel.split(':')[0] or 'пусто'}: "
                           f"код {p.status_code} против {q.status_code}")
                continue
            if p.status_code == 200:
                cp, cq = claims(p.json()["token"]), claims(q.json()["token"])
                strip = lambda d: {k: v for k, v in d.items() if k != "exp"}
                if strip(cp) != strip(cq) or abs(cp["exp"] - cq["exp"]) > 5 \
                        or not signed_by(q.json()["token"], secret_c):
                    bad.append(f"{label} канал {channel.split(':')[0]}: поля или подпись разошлись")
    lite.close()

    checked = max(0, len(found) - 1)
    print(f"пар {checked}, запросов {total}, расхождений {len(bad)}, "
          f"комнат по нашему коду пустил PocketBase: {room_ok} из {checked}")
    for line in bad[:30]:
        print("  " + line)
    sys.exit(1 if bad or (checked and room_ok == 0) else 0)


if __name__ == "__main__":
    main()
