#!/usr/bin/env python3
"""Живой регресс: приём кода не бросает своё пространство принимающего.

Обращение 597, 07.11.2026: «заполнила все воспоминания, все таймеры выставила…
а после подключения к партнёру всё обнулилось». До пары человек живёт в своей
группе из одного участника; приём кода заводил новую пустую пару, и прежняя
оставалась невидимой. Правило — `порядок_основы` в hotpath.

Что проверяем:
  1. У неё своя группа с воспоминанием, у него ничего → пара строится на её группе
  2. У него своя пустая, у неё своя с воспоминанием  → пара на её группе
  3. У него своя пустая, у неё ничего                → она входит к нему, как раньше
  4. Приглашающему, вошедшему в её группу, приходит воспоминание

Гоняется по живому серверу, заводит временные аккаунты
(`solo-probe-*@example.com`) и убирает за собой:
    python3 pocketbase/pair_accept_solo.test.py
"""
import datetime
import json
import random
import string
import sys
import time
import urllib.error
import urllib.request

BASE = "https://togetherly.day"
T0 = time.time()
OK, FAIL = [], []


def log(*a):
    print(f"[{time.time() - T0:6.2f}s]", *a, flush=True)


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    log(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""))


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body, method=method or ("POST" if body else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def rnd(n=8, alphabet=string.ascii_lowercase + string.digits):
    return "".join(random.choice(alphabet) for _ in range(n))


def signup(tag):
    email = f"solo-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}"); sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password", {"identity": email, "password": pwd})
    log(f"{tag}: uid={auth['record']['id']}")
    return {"uid": auth["record"]["id"], "token": auth["token"], "groups": [], "memories": []}


def solo(u):
    st, r = api("/api/waiting/create", {"name": "Ждём", "returnDate": ""}, u["token"])
    gid = (r or {}).get("pairId", "")
    if gid:
        u["groups"].append(gid)
    return gid


def memory(u, gid):
    mid = rnd(15)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.000Z")
    st, r = api("/api/collections/memories/records", {
        "id": mid, "group_id": gid, "author_uid": u["uid"], "author_name": "Probe",
        "type": "note", "data": {"text": "проба своего пространства"}, "created_at": now,
        "added_at": now, "deleted": False,
    }, u["token"])
    if st in (200, 201):
        u["memories"].append(mid)
    return st


def code_of(u):
    code = rnd(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    api("/api/collections/invite_codes/records", {"code": code, "owner_uid": u["uid"]}, u["token"])
    return code


def accept(u, code):
    st, r = api("/api/invite/accept", {"code": code}, u["token"])
    pid = (r or {}).get("pairId", "")
    if pid and pid not in u["groups"]:
        u["groups"].append(pid)
    return st, r


def main():
    people = []

    log("=== 1. у неё своя с воспоминанием, у него ничего ===")
    her, him = signup("she1"), signup("he1")
    people += [her, him]
    s1 = solo(her)
    check("её пространство заведено и в нём воспоминание", bool(s1) and memory(her, s1) in (200, 201))
    st, r = accept(her, code_of(him))
    check("пара построена на её группе, а не новой", st == 200 and r.get("pairId") == s1, f"{st} {r}")
    st, g = api(f"/api/collections/groups/records/{s1}", None, him["token"])
    check("он в составе её группы", st == 200 and him["uid"] in (g.get("members") or []), f"{st} {g.get('members')}")
    check("ожидание партнёра погасло", g.get("waiting_mode") is not True and not g.get("claim_token"),
          f"waiting={g.get('waiting_mode')}")
    flt = urllib.parse.quote(f"group_id='{s1}'")
    st, lst = api(f"/api/collections/memories/records?filter=({flt})", None, him["token"])
    check("ему видно её воспоминание", st == 200 and len(lst.get("items") or []) == 1, f"{st} {len(lst.get('items') or [])}")

    log("=== 2. у него своя пустая, у неё своя с воспоминанием ===")
    her2, him2 = signup("she2"), signup("he2")
    people += [her2, him2]
    h2, s2 = solo(him2), solo(her2)
    memory(her2, s2)
    st, r = accept(her2, code_of(him2))
    check("пара на её группе, где есть воспоминание", st == 200 and r.get("pairId") == s2, f"{st} {r} его={h2}")

    log("=== 3. у него своя пустая, у неё ничего ===")
    her3, him3 = signup("she3"), signup("he3")
    people += [her3, him3]
    h3 = solo(him3)
    st, r = accept(her3, code_of(him3))
    check("как раньше: она вошла в его группу", st == 200 and r.get("pairId") == h3, f"{st} {r}")

    log("=== уборка ===")
    for u in people:
        for mid in u["memories"]:
            api(f"/api/collections/memories/records/{mid}", None, u["token"], method="DELETE")
    for u in people:
        for gid in u["groups"]:
            api(f"/api/collections/groups/records/{gid}", None, u["token"], method="DELETE")
        st, lst = api(f"/api/collections/invite_codes/records?filter=(owner_uid='{u['uid']}')", None, u["token"])
        for it in (lst.get("items") or []):
            api(f"/api/collections/invite_codes/records/{it['id']}", None, u["token"], method="DELETE")
    for u in people:
        st, _ = api(f"/api/collections/users/records/{u['uid']}", None, u["token"], method="DELETE")
        log(f"аккаунт {u['uid']} удалён → {st}")

    log(f"ИТОГ: пройдено {len(OK)}, провалено {len(FAIL)}" + (f" → {FAIL}" if FAIL else ""))
    sys.exit(1 if FAIL else 0)


import urllib.parse  # noqa: E402

main()
