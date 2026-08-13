#!/usr/bin/env python3
"""Нагрузочный стенд для PocketBase Togetherly.

Запускать НА VPS: он ходит на 127.0.0.1:8090, поэтому меряет сервер, а не
канал до него. Заводит собственную тестовую пару, гоняет по ней те же запросы,
что шлёт приложение, и печатает распределение времён ответа.

Смысл в повторяемости: правку на сервере видно не по жалобам, а по тому, как
сдвинулись p50/p90/p99 на одной и той же нагрузке.

    python3 load_probe.py --users 20 --seconds 60          # обычный прогон
    python3 load_probe.py --users 20 --seconds 60 --only widget
    python3 load_probe.py --cleanup                        # убрать за собой

Тестовые записи живут в своей группе и удаляются в конце (или ключом
--cleanup, если прогон оборвали).
"""
import argparse
import json
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8090"
TAG = "loadprobe"
PASSWORD = "LoadProbe12345!"


def call(method, path, body=None, token=None, timeout=90):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    started = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode() or "{}"), time.time() - started
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw), time.time() - started
        except Exception:
            return e.code, {"raw": raw[:200]}, time.time() - started
    except Exception as e:
        return 0, {"exc": repr(e)}, time.time() - started


def superuser(email, password):
    st, res, _ = call("POST", "/api/collections/_superusers/auth-with-password",
                      {"identity": email, "password": password})
    if st != 200:
        print("не вошёл суперюзером:", st, res)
        sys.exit(1)
    return res["token"]


def setup(token, n):
    """Тестовые люди и одна пара на всех: так ближе к жизни, чем n одиночек."""
    uids, tokens = [], []
    for i in range(n):
        email = "%s-%02d@probe.local" % (TAG, i)
        st, u, _ = call("POST", "/api/collections/users/records", {
            "email": email, "password": PASSWORD, "passwordConfirm": PASSWORD,
            "display_name": "probe%02d" % i,
        }, token)
        if st != 200 and "unique" not in json.dumps(u):
            print("не завёл человека %d: %s %s" % (i, st, u))
            continue
        st, a, _ = call("POST", "/api/collections/users/auth-with-password",
                        {"identity": email, "password": PASSWORD})
        if st != 200:
            print("не вошёл человеком %d: %s" % (i, st))
            continue
        uids.append(a["record"]["id"])
        tokens.append(a["token"])

    groups = []
    for i in range(0, len(uids) - 1, 2):
        st, g, _ = call("POST", "/api/collections/groups/records",
                        {"members": [uids[i], uids[i + 1]], "name": TAG}, token)
        if st == 200:
            groups.append((g["id"], (uids[i], tokens[i]), (uids[i + 1], tokens[i + 1])))
    return groups


def scenarios(group, who):
    """Что именно шлёт приложение в обычную минуту."""
    gid, (uid, token) = group, who
    now = int(time.time() * 1000)
    return {
        # Данные виджета: статус, музыка, фото. Составной уникальный ключ.
        "widget": ("POST", "/api/collections/widget_data/records",
                   {"group_id": gid, "user_uid": uid, "status": "проба %d" % now}),
        # Сообщение в чате — запись с явным id.
        "chat": ("POST", "/api/collections/chat_messages/records",
                 {"id": "lp%013d%s" % (now % 10**13, uid[:2]),
                  "group_id": gid, "user_uid": uid, "text": "проба"}),
        # Присутствие: самый частый эфемерный запрос.
        "presence": ("POST", "/api/collections/user_presence/records",
                     {"user_uid": uid, "seen_at": now}),
        # «Печатает»: эфемерное, живёт секунды.
        "typing": ("POST", "/api/collections/chat_typing/records",
                   {"group_id": gid, "user_uid": uid, "typing_at": now}),
        # Чтение ленты — самый частый запрос на чтение.
        "read": ("GET", "/api/collections/memories/records?perPage=20&filter="
                 + "group_id%3D%22" + gid + "%22", None),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--email", default="")
    ap.add_argument("--password", default="")
    ap.add_argument("--users", type=int, default=20)
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--pause", type=float, default=1.0, help="пауза между кругами, с")
    ap.add_argument("--only", default="", help="widget|chat|presence|typing|read")
    ap.add_argument("--cleanup", action="store_true")
    args = ap.parse_args()

    token = superuser(args.email, args.password)

    if args.cleanup:
        removed = 0
        for coll, field in (("groups", "name"), ("users", "email")):
            while True:
                needle = TAG if coll == "groups" else TAG + "-"
                st, res, _ = call("GET", "/api/collections/%s/records?perPage=200&filter=%s~'%s'"
                                  % (coll, field, needle), None, token)
                items = (res or {}).get("items") or []
                if st != 200 or not items:
                    break
                for it in items:
                    call("DELETE", "/api/collections/%s/records/%s" % (coll, it["id"]), None, token)
                    removed += 1
        print("убрано записей:", removed)
        return 0

    groups = setup(token, args.users)
    if not groups:
        print("не с кем нагружать: пары не завелись")
        return 1
    print("пар в прогоне: %d, длительность: %d с" % (len(groups), args.seconds))

    times = {}
    codes = {}
    lock = threading.Lock()
    stop_at = time.time() + args.seconds

    def worker(gid, who):
        while time.time() < stop_at:
            for name, (method, path, body) in scenarios(gid, who).items():
                if args.only and name != args.only:
                    continue
                st, _, dt = call(method, path, body, who[1])
                with lock:
                    times.setdefault(name, []).append(dt)
                    codes.setdefault(name, []).append(st)
            time.sleep(args.pause)

    threads = []
    for gid, a, b in groups:
        for who in (a, b):
            t = threading.Thread(target=worker, args=(gid, who), daemon=True)
            t.start()
            threads.append(t)
    for t in threads:
        t.join()

    print()
    print("%-10s %7s %8s %8s %8s %8s   ответы" % ("что", "запросов", "медиана", "p90", "p99", "макс"))
    for name in sorted(times):
        xs = sorted(times[name])
        if not xs:
            continue
        cc = {}
        for c in codes[name]:
            cc[c] = cc.get(c, 0) + 1
        print("%-10s %7d %8.2f %8.2f %8.2f %8.2f   %s"
              % (name, len(xs), statistics.median(xs), xs[int(len(xs) * 0.9)],
                 xs[int(len(xs) * 0.99)], xs[-1], cc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
