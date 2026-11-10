#!/usr/bin/env python3
"""Живой регресс: одновременные приёмы одного кода не заводят две пары.

Найдено 10.11.2026 на `invite_accept.test.py`: проверка «три одновременных
приёма вернули одну пару» падала через раз. Приём кода (`/internal/pair-accept`
в hotpath) запирает строку пары, но у новой пары строки ещё нет: запросы,
пришедшие разом, каждый видит «общей пары нет» и каждый заводит свою. Так
появлялись пары-дубли — две живые группы с одним составом, где каждый телефон
остаётся на своей и партнёра не видит (диплинк шлёт код дважды, кнопку жмут
два раза).

Каждый круг: общей пары у двоих нет, шесть приёмов одного кода разом, после
них живая пара на двоих обязана быть одна.

Гоняется по живому серверу, заводит временные аккаунты
(`race-probe-*@example.com`) и убирает за собой:
    python3 pocketbase/pair_accept_race.test.py
"""
import json
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = "https://togetherly.day"
ROUNDS = 5
TAPS = 6
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
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"race-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"]}


def new_code(owner):
    code = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
    api("/api/collections/invite_codes/records",
        {"code": code, "owner_uid": owner["uid"]}, owner["token"])
    return code


def shared_groups(who, other):
    """Живые группы, где есть оба."""
    flt = urllib.parse.quote(f"(members ~ '{who['uid']}' && disbanded = false)")
    st, lst = api(f"/api/collections/groups/records?perPage=100&filter={flt}",
                  None, who["token"])
    return [g["id"] for g in (lst.get("items") or [])
            if other["uid"] in (g.get("members") or [])]


def drop_groups(who):
    flt = urllib.parse.quote(f"(members ~ '{who['uid']}')")
    st, lst = api(f"/api/collections/groups/records?perPage=100&filter={flt}",
                  None, who["token"])
    for g in lst.get("items") or []:
        api(f"/api/collections/groups/records/{g['id']}", None, who["token"], method="DELETE")


def drop_codes(who):
    flt = urllib.parse.quote(f"(owner_uid='{who['uid']}')")
    st, lst = api(f"/api/collections/invite_codes/records?filter={flt}", None, who["token"])
    for it in lst.get("items") or []:
        api(f"/api/collections/invite_codes/records/{it['id']}", None,
            who["token"], method="DELETE")


def main():
    owner, guest = signup("zov"), signup("gost")
    log(f"зовёт={owner['uid']} принимает={guest['uid']}")
    try:
        for круг in range(1, ROUNDS + 1):
            drop_groups(owner)
            drop_groups(guest)
            drop_codes(owner)
            time.sleep(1.0)
            code = new_code(owner)
            with ThreadPoolExecutor(max_workers=TAPS) as ex:
                futs = [ex.submit(api, "/api/invite/accept", {"code": code}, guest["token"])
                        for _ in range(TAPS)]
                res = [f.result() for f in futs]
            ids = {r.get("pairId") for st, r in res if st == 200 and r.get("pairId")}
            check(f"круг {круг}: все приёмы успешны",
                  all(st == 200 for st, _ in res),
                  "; ".join(f"{st} {r.get('message')}" for st, r in res))
            check(f"круг {круг}: все вернули одну пару", len(ids) == 1, str(sorted(ids)))
            time.sleep(1.5)
            живые = shared_groups(guest, owner)
            check(f"круг {круг}: живая пара на двоих одна", len(живые) == 1, str(живые))
    finally:
        log("=== уборка ===")
        drop_groups(owner)
        drop_groups(guest)
        drop_codes(owner)
        codes = []
        for who in (owner, guest):
            st, _ = api(f"/api/collections/users/records/{who['uid']}", None,
                        who["token"], method="DELETE")
            codes.append(st)
        check("тестовые аккаунты убраны", all(c in (204, 404) for c in codes), str(codes))

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
