#!/usr/bin/env python3
"""Живой регресс приёма инвайт-кода: `python3 pocketbase/invite_accept.test.py`.

Стережёт разбор 2 августа 2026, когда пара собиралась, но не показывалась:
события коллекции `groups` не доходили до канала `user:<uid>` (в
`centrifugo.pb.js` состав читался через `rec.get("members")`, а этот JSVM
отдаёт по json-полю ни строку, ни массив), и приглашающий видел пару только
после перезапуска приложения. Оба тогда принимались вводить код заново и
получали «Код не найден» — код удалялся при первом же успешном приёме.

Что проверяем:
  1. Обычный приём чужого кода                  → успех, пара создана
  2. Повтор того же кода тем же человеком        → успех с тем же pairId
  3. Три одновременных приёма (двойной тап)      → все успешны, пара одна
  4. Третий человек с тем же кодом               → «Группа заполнена»
  5. Свой собственный код                        → отказ
  6. Приглашающему приезжает `create groups` в его канал `user:<uid>`

Гоняется по ЖИВОМУ серверу: заводит четыре временных аккаунта
(`invite-probe-*@example.com`) и удаляет за собой аккаунты, группы и коды.
Нужен `pip install websockets`. Код возврата 1, если хоть один шаг провален.
"""
import asyncio
import json
import random
import ssl
import string
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

BASE = "https://togetherly.day"
WS = "wss://rt.togetherly.day:8443/connection/websocket"
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


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"invite-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}"); sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password", {"identity": email, "password": pwd})
    log(f"{tag}: uid={auth['record']['id']}")
    return {"uid": auth["record"]["id"], "token": auth["token"]}


def new_code(owner):
    code = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
    api("/api/collections/invite_codes/records", {"code": code, "owner_uid": owner["uid"]}, owner["token"])
    return code


async def sock_watch(a, got, ready, stop):
    import websockets
    st, ct = api("/api/centrifugo/connection-token", {}, a["token"])
    st2, sub = api("/api/centrifugo/subscription-token", {"channel": f"user:{a['uid']}"}, a["token"])
    async with websockets.connect(WS, ssl=ssl.create_default_context(), ping_interval=None) as ws:
        await ws.send(json.dumps({"id": 1, "connect": {"token": ct["token"], "name": "probe"}}))
        await ws.send(json.dumps({"id": 2, "subscribe": {"channel": f"user:{a['uid']}", "token": sub["token"]}}))
        ready.set()
        while not stop.is_set():
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=1)
            except asyncio.TimeoutError:
                continue
            for line in str(raw).splitlines():
                if not line.strip():
                    continue
                m = json.loads(line)
                if m == {}:
                    await ws.send("{}")
                elif "push" in m:
                    d = m["push"].get("pub", {}).get("data", {})
                    got.append(d)
                    log(f"    ← ПУШ приглашающему: {d.get('event')} {d.get('collection')}")


async def main():
    a, b, c = signup("A"), signup("B"), signup("C")
    got, ready, stop = [], asyncio.Event(), asyncio.Event()
    task = asyncio.create_task(sock_watch(a, got, ready, stop))
    await asyncio.wait_for(ready.wait(), timeout=25)
    await asyncio.sleep(1.5)

    log("=== 1. обычный приём ===")
    code = new_code(a)
    st, r1 = api("/api/invite/accept", {"code": code}, b["token"])
    pair = (r1 or {}).get("pairId", "")
    check("приём чужого кода даёт пару", st == 200 and bool(pair), f"{st} {r1}")

    log("=== 2. повтор того же кода тем же человеком ===")
    st, r2 = api("/api/invite/accept", {"code": code}, b["token"])
    check("повтор отвечает успехом, а не «Код не найден»",
          st == 200 and r2.get("pairId") == pair, f"{st} {r2}")

    log("=== 3. двойной тап: два запроса разом ===")
    code2 = new_code(a)
    st, _ = api(f"/api/collections/groups/records/{pair}", None, b["token"], method="DELETE")
    d, e2 = signup("D"), None
    with ThreadPoolExecutor(max_workers=3) as ex:
        futs = [ex.submit(api, "/api/invite/accept", {"code": code2}, d["token"]) for _ in range(3)]
        res = [f.result() for f in futs]
    pair2 = next((rr.get("pairId") for stt, rr in res if stt == 200 and rr.get("pairId")), "")
    check("три одновременных приёма — все успешны",
          all(stt == 200 for stt, _ in res), "; ".join(f"{stt} {rr.get('message')}" for stt, rr in res))
    check("все вернули одну и ту же пару",
          len({rr.get("pairId") for stt, rr in res if stt == 200}) == 1, str(pair2))

    log("=== 4. третий человек с тем же кодом ===")
    st, r4 = api("/api/invite/accept", {"code": code2}, c["token"])
    check("третьего в занятую пару не пускает", st != 200, f"{st} {r4.get('message')}")

    log("=== 5. свой собственный код ===")
    code3 = new_code(c)
    st, r5 = api("/api/invite/accept", {"code": code3}, c["token"])
    check("свой код отвергается", st != 200, f"{st} {r5.get('message')}")

    await asyncio.sleep(2)
    check("приглашающему пришло событие о новой паре",
          any(x.get("collection") == "groups" and x.get("event") == "create" for x in got),
          f"пушей: {len(got)}")

    stop.set()
    try:
        await asyncio.wait_for(task, timeout=8)
    except asyncio.TimeoutError:
        pass

    log("=== уборка ===")
    for gid, who in ((pair, b), (pair2, d)):
        if gid:
            api(f"/api/collections/groups/records/{gid}", None, who["token"], method="DELETE")
    for u in (a, c):
        st, lst = api(f"/api/collections/invite_codes/records?filter=(owner_uid='{u['uid']}')", None, u["token"])
        for it in (lst.get("items") or []):
            api(f"/api/collections/invite_codes/records/{it['id']}", None, u["token"], method="DELETE")
    for name, u in (("A", a), ("B", b), ("C", c), ("D", d)):
        st, _ = api(f"/api/collections/users/records/{u['uid']}", None, u["token"], method="DELETE")
        log(f"аккаунт {name} удалён → {st}")

    log(f"ИТОГ: пройдено {len(OK)}, провалено {len(FAIL)}" + (f" → {FAIL}" if FAIL else ""))
    sys.exit(1 if FAIL else 0)


asyncio.run(main())
