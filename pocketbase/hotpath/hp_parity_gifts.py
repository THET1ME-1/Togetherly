#!/usr/bin/env python3
"""Сверка подарков: hotpath против PocketBase на живых данных (19.10.2026).

Берёт людей, которым дарили подарки, выписывает им токены тем же ключом, что
PocketBase (только чтение, ничего не пишет), и шлёт одни и те же запросы в
PocketBase (127.0.0.1:8090) и в hotpath (127.0.0.1:8120): все запросы,
которыми приложение читает подарки, плюс чтение по id и чужая пара. Ответы
обязаны совпасть до поля. Содержимое подарков не печатается, только имена
расходящихся полей.

    /opt/hotpath/venv/bin/python hp_parity_gifts.py [--people 40]
"""

import argparse
import base64
import hashlib
import hmac
import json
import sqlite3
import sys
import time

import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def token(uid: str, token_key: str, secret: str) -> str:
    head = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                            "refreshable": False, "exp": int(time.time()) + 900}).encode())
    sig = b64u(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                        hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def diff(a, b, sorted_query: bool = True) -> str:
    """Где разошлись два ответа: число записей, порядок или поля.

    Без `sort` порядок не задан ни у PocketBase, ни у SQLite: другая запись
    на странице при том же totalItems — не расхождение."""
    if a.status_code != b.status_code:
        return f"код {a.status_code} против {b.status_code}"
    if a.status_code >= 400:
        # Тело ошибки у hotpath своё (`code` против `status` у PocketBase),
        # приложение смотрит только на код ответа.
        return ""
    ja, jb = a.json(), b.json()
    if "items" not in ja:
        keys = sorted(k for k in set(ja) | set(jb) if ja.get(k) != jb.get(k))
        return f"поля {keys}" if keys else ""
    if ja.get("totalItems") != jb.get("totalItems"):
        return f"totalItems {ja.get('totalItems')} против {jb.get('totalItems')}"
    ia, ib = ja["items"], jb["items"]
    if [x["id"] for x in ia] != [x["id"] for x in ib]:
        if sorted(x["id"] for x in ia) == sorted(x["id"] for x in ib):
            return "тот же набор, другой порядок"
        if not sorted_query and len(ia) == len(ib):
            return ""
        return f"записи {len(ia)} против {len(ib)}"
    for x, y in zip(ia, ib):
        keys = sorted(k for k in set(x) | set(y) if x.get(k) != y.get(k))
        if keys:
            types = {k: (type(x.get(k)).__name__, type(y.get(k)).__name__) for k in keys}
            return f"поля {types}"
    return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--people", type=int, default=40)
    args = ap.parse_args()

    lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
    secret = json.loads(lite.execute(
        "SELECT options FROM _collections WHERE name='users'").fetchone()[0])["authToken"]["secret"]
    people = lite.execute(
        "SELECT g.recipient_uid, g.group_id, u.tokenKey FROM gifts g "
        "JOIN users u ON u.id = g.recipient_uid "
        "GROUP BY g.recipient_uid ORDER BY max(g.created) DESC LIMIT ?",
        (args.people,)).fetchall()
    foreign = lite.execute("SELECT id FROM gifts ORDER BY created DESC LIMIT 1").fetchone()[0]
    lite.close()

    client = httpx.Client(timeout=60)
    bad, total = [], 0
    for uid, gid, token_key in people:
        h = {"Authorization": token(uid, token_key, secret)}
        now_ms = int(time.time() * 1000)
        queries = [
            ("все подарки", {"perPage": 200, "sort": "-created",
                             "filter": f'recipient_uid = "{uid}"'}),
            ("подарки в паре", {"perPage": 200, "sort": "-created",
                                "filter": f'group_id = "{gid}" && recipient_uid = "{uid}"'}),
            ("число подарков", {"page": 1, "perPage": 1,
                                "filter": f'recipient_uid = "{uid}"'}),
            ("входящие", {"perPage": 20, "sort": "-created",
                          "filter": f'group_id = "{gid}" && recipient_uid = "{uid}" && '
                                    f'state = "sent" && deliver_at <= {now_ms}'}),
        ]
        for name, params in queries:
            a = client.get(f"{PB}/api/collections/gifts/records", headers=h, params=params)
            b = client.get(f"{HP}/api/collections/gifts/records", headers=h, params=params)
            total += 1
            why = diff(a, b, sorted_query=bool(params.get("sort")))
            if why:
                bad.append(f"{uid[:6]}… {name}: {why}")
        first = client.get(f"{PB}/api/collections/gifts/records", headers=h,
                           params={"perPage": 1, "filter": f'recipient_uid = "{uid}"'}).json()
        for rid, name in ((first["items"][0]["id"] if first.get("items") else None, "по id"),
                          (foreign, "чужой по id")):
            if not rid:
                continue
            a = client.get(f"{PB}/api/collections/gifts/records/{rid}", headers=h)
            b = client.get(f"{HP}/api/collections/gifts/records/{rid}", headers=h)
            total += 1
            why = diff(a, b)
            if why:
                bad.append(f"{uid[:6]}… {name}: {why}")

    print(f"людей {len(people)}, запросов {total}, расхождений {len(bad)}")
    for line in bad[:25]:
        print("  " + line)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
