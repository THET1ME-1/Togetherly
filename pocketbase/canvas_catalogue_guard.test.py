# -*- coding: utf-8 -*-
"""Удалённый холст не воскресает (TOG-12, 22.10.2026) — проверка хука
`canvas_catalogue_guard.pb.js`.

Галерея прежних сборок при первом открытии за запуск шлёт в каталог ВСЕ свои
холсты, и холст, удалённый партнёром, заводился на сервере снова — у обоих
(повторено на эмуляторе: «Canvas 3» вернулся сразу после открытия галереи).
Сборки уже у людей, поэтому сервер помнит удалённые холсты и не даёт завести
их снова.

Запуск (суперюзер нужен: каталог пишется от его имени, без пары):
    PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. \\
        python3 pocketbase/canvas_catalogue_guard.test.py

Запись в журнале удалённых и тестовые холсты убирает за собой.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

GROUP = f"tog12guard{int(time.time()) % 100000}"
OTHER_GROUP = GROUP + "b"
CANVAS = "canvas_1792630961924"
fails = []


def api(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PB_URL + path, data=data, method=method)
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
            return e.code, raw


def check(name, cond, detail=""):
    print(("  ✓ " if cond else "  ✗ ") + name + ("" if cond else f"  [{detail}]"))
    if not cond:
        fails.append(name)


def create(token, group, canvas):
    return api("POST", "/api/collections/canvas_catalogue/records", token, {
        "group_id": group,
        "canvas_id": canvas,
        "name": "Canvas 3",
        "created_at": 1792489699356,
        "updated_at": 1792489699356,
    })


def find(token, col, flt):
    q = urllib.parse.urlencode({"filter": flt, "perPage": 50})
    st, js = api("GET", f"/api/collections/{col}/records?{q}", token)
    return js.get("items", []) if st == 200 else []


def main():
    if not PB_EMAIL or not PB_PW:
        print("Нужны PB_EMAIL и PB_PW суперюзера")
        return 2
    st, auth = api("POST", "/api/collections/_superusers/auth-with-password",
                   body={"identity": PB_EMAIL, "password": PB_PW})
    if st != 200:
        print("вход суперюзера не прошёл:", st, auth)
        return 2
    t = auth["token"]
    made = []
    try:
        st, rec = create(t, GROUP, CANVAS)
        check("холст заводится", st == 200, (st, rec))
        if st == 200:
            made.append(rec["id"])

        st, _ = api("DELETE", f"/api/collections/canvas_catalogue/records/{rec['id']}", t)
        check("холст удаляется", st == 204, st)
        if st == 204:
            made.remove(rec["id"])

        log = find(t, "canvas_catalogue_deleted",
                   f"group_id = '{GROUP}' && canvas_id = '{CANVAS}'")
        check("удаление записано в журнал", len(log) == 1, log)

        st, again = create(t, GROUP, CANVAS)
        check("удалённый холст снова не заводится", st == 400, (st, again))
        if st == 200:
            made.append(again["id"])

        st, other = create(t, GROUP, CANVAS + "1")
        check("другой холст той же пары заводится", st == 200, (st, other))
        if st == 200:
            made.append(other["id"])

        st, foreign = create(t, OTHER_GROUP, CANVAS)
        check("тот же номер холста в другой паре заводится", st == 200, (st, foreign))
        if st == 200:
            made.append(foreign["id"])
    finally:
        for rid in made:
            api("DELETE", f"/api/collections/canvas_catalogue/records/{rid}", t)
        for g in (GROUP, OTHER_GROUP):
            for r in find(t, "canvas_catalogue_deleted", f"group_id = '{g}'"):
                api("DELETE", f"/api/collections/canvas_catalogue_deleted/records/{r['id']}", t)

    print("ПРОВАЛЫ: " + ", ".join(fails) if fails else "ВСЁ ЗЕЛЁНОЕ")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
