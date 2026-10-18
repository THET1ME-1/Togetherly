#!/usr/bin/env python3
"""Сверка чтения из SQLite: hotpath против PocketBase на живых данных.

Для каждой коллекции из SQLITE_READ hotpath.py берёт свежие пары, выписывает
их участникам токены тем же ключом, что PocketBase (только чтение, ничего не
пишет), и шлёт одни и те же запросы в PocketBase (127.0.0.1:8090) и в hotpath
(127.0.0.1:8120): список пары, дельту по `updated`, число записей, запись по
id, чужую запись по id; у каталога — список без входа. Ответы обязаны
совпасть до поля. Содержимое не печатается, только где разошлось.

    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python hp_parity_read.py [--groups 8] [коллекция ...]
"""

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import os
import sqlite3
import sys
import time

import asyncpg
import httpx

PB = "http://127.0.0.1:8090"
HP = "http://127.0.0.1:8120"
DB = "/opt/pocketbase/pb_data/data.db"
GROUP_COLLECTIONS = ["gifts", "watch_history", "canvas_catalogue", "memory_comments",
                     "watch_videos", "custom_moods"]
PUBLIC_COLLECTIONS = ["catalog_items"]


def b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def token(uid: str, token_key: str, secret: str) -> str:
    head = b64u(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    body = b64u(json.dumps({"collectionId": "_pb_users_auth_", "id": uid, "type": "auth",
                            "refreshable": False, "exp": int(time.time()) + 900}).encode())
    sig = b64u(hmac.new((token_key + secret).encode(), f"{head}.{body}".encode(),
                        hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def diff(a, b, sorted_query: bool = True) -> tuple[str, bool]:
    """(где разошлось, только порядок равных) для двух ответов.

    Без `sort` порядок не задан ни у PocketBase, ни у SQLite: разный набор
    на странице при равном totalItems — это порядок, а не ошибка."""
    if a.status_code != b.status_code:
        return f"код {a.status_code} против {b.status_code}", False
    if a.status_code >= 400:
        return "", False  # тело ошибки у hotpath своё, приложение смотрит на код
    ja, jb = a.json(), b.json()
    if "items" not in ja:
        keys = sorted(k for k in set(ja) | set(jb) if ja.get(k) != jb.get(k))
        return (f"поля {keys}" if keys else ""), False
    if ja.get("totalItems") != jb.get("totalItems"):
        return f"totalItems {ja.get('totalItems')} против {jb.get('totalItems')}", False
    ia, ib = ja["items"], jb["items"]
    if [x["id"] for x in ia] != [x["id"] for x in ib]:
        if sorted(x["id"] for x in ia) == sorted(x["id"] for x in ib):
            return "тот же набор, другой порядок", True
        if not sorted_query and len(ia) == len(ib):
            return "без sort: другая страница при том же числе", True
        return f"записи {len(ia)} против {len(ib)}", False
    for x, y in zip(ia, ib):
        keys = sorted(k for k in set(x) | set(y) if x.get(k) != y.get(k))
        if keys:
            types = {k: (type(x.get(k)).__name__, type(y.get(k)).__name__) for k in keys}
            return f"поля {types}", False
    return "", False


async def members_of(groups: list) -> dict:
    conn = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    try:
        rows = await conn.fetch("SELECT id, members FROM groups WHERE id = ANY($1)", groups)
    finally:
        await conn.close()
    out = {}
    for r in rows:
        m = r["members"]
        m = json.loads(m) if isinstance(m, str) else (m or [])
        if m:
            out[r["id"]] = str(m[0])
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("collections", nargs="*")
    ap.add_argument("--groups", type=int, default=8)
    args = ap.parse_args()
    wanted = args.collections or GROUP_COLLECTIONS + PUBLIC_COLLECTIONS

    lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
    secret = json.loads(lite.execute(
        "SELECT options FROM _collections WHERE name='users'").fetchone()[0])["authToken"]["secret"]
    client = httpx.Client(timeout=60)
    bad, order_only, total = [], [], 0

    def compare(label, path, h, params=None):
        nonlocal total
        a = client.get(f"{PB}{path}", headers=h, params=params)
        b = client.get(f"{HP}{path}", headers=h, params=params)
        total += 1
        why, only_order = diff(a, b, sorted_query=bool((params or {}).get("sort")))
        if why:
            (order_only if only_order else bad).append(f"{label}: {why}")

    for col in wanted:
        url = f"/api/collections/{col}/records"
        if col in PUBLIC_COLLECTIONS:
            compare(f"{col} без входа", url, {}, {"perPage": 500})
            first = lite.execute(f"SELECT id FROM {col} LIMIT 1").fetchone()
            if first:
                compare(f"{col} по id", f"{url}/{first[0]}", {})
            continue
        columns = {r[1] for r in lite.execute(f"PRAGMA table_info({col})")}
        # У каталога холстов времени правки `updated` нет, есть `updated_at`.
        stamp = "updated" if "updated" in columns else "updated_at"
        groups = [r[0] for r in lite.execute(
            f"SELECT group_id FROM {col} GROUP BY group_id ORDER BY max({stamp}) DESC LIMIT ?",
            (args.groups,))]
        owners = asyncio.run(members_of(groups))
        foreign = lite.execute(f"SELECT id FROM {col} ORDER BY {stamp} LIMIT 1").fetchone()[0]
        has_memory = "memory_id" in columns
        for gid, uid in owners.items():
            row = lite.execute("SELECT tokenKey FROM users WHERE id = ?", (uid,)).fetchone()
            if not row:
                continue
            h = {"Authorization": token(uid, row[0], secret)}
            label = f"{col} {gid[:6]}…"
            compare(f"{label} список", url, h,
                    {"perPage": 200, "sort": f"-{stamp}", "filter": f'group_id = "{gid}"'})
            compare(f"{label} дельта", url, h,
                    {"perPage": 200, "sort": stamp,
                     "filter": f"group_id = '{gid}' && {stamp} > '2026-10-01 00:00:00'"})
            compare(f"{label} число", url, h,
                    {"perPage": 1, "filter": f'group_id = "{gid}"'})
            one = lite.execute(f"SELECT id FROM {col} WHERE group_id = ? LIMIT 1",
                               (gid,)).fetchone()
            if one:
                compare(f"{label} по id", f"{url}/{one[0]}", h)
            compare(f"{label} чужая по id", f"{url}/{foreign}", h)
            if has_memory:
                mem = lite.execute(f"SELECT memory_id FROM {col} WHERE group_id = ? LIMIT 1",
                                   (gid,)).fetchone()
                if mem:
                    compare(f"{label} по записи", url, h,
                            {"perPage": 200, "sort": "created_at",
                             "filter": f'memory_id = "{mem[0]}"'})
                    compare(f"{label} сортировка по чужому полю", url, h,
                            {"perPage": 200, "sort": "created",
                             "filter": f'memory_id = "{mem[0]}"'})
    lite.close()

    print(f"коллекций {len(wanted)}, запросов {total}, расхождений {len(bad)}, "
          f"только порядок равных {len(order_only)}")
    for line in (bad + order_only)[:30]:
        print("  " + line)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
