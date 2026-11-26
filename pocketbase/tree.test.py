#!/usr/bin/env python3
"""Живой регресс ёлки пары (tree.pb.js, 26.11.2026).

Правила — docs/superpowers/specs/2026-11-26-xmas-tree-design.md: коробка у
каждого своя, стартовый набор, моих игрушек вида X на ёлке не больше, чем X в
коробке, снять может любой из пары, стиль «Под снегом» только своим, коробку
и коллекции ёлки клиент напрямую не пишет, покупка только за монеты.

Заводит временные аккаунты (`tree-probe-*@example.com`) и пару, убирает за
собой аккаунты, пару и игрушки (строка `pair_trees` распущенной пары остаётся):
    python3 pocketbase/tree.test.py
"""
import json
import random
import string
import sys
import threading
import time
import urllib.error
import urllib.request

BASE = "https://togetherly.day"
T0 = time.time()
OK, FAIL = [], []
S = 2026


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
    email = f"tree-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {"email": email, "password": pwd, "passwordConfirm": pwd,
                                                    "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password", {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"]}


WS = "wss://rt.togetherly.day:8443/connection/websocket"


def listen_pair(who, pair, action, wait=4.0):
    """Подписаться на `pair:<группа>` как телефон, выполнить [action] и вернуть
    пойманные события за [wait] секунд. Нужен `pip install websockets`."""
    import asyncio
    import ssl
    import websockets

    async def run():
        got = []
        st, ct = api("/api/centrifugo/connection-token", {}, who["token"])
        st2, sub = api("/api/centrifugo/subscription-token", {"channel": f"pair:{pair}"}, who["token"])
        async with websockets.connect(WS, ssl=ssl.create_default_context(), ping_interval=None) as ws:
            await ws.send(json.dumps({"id": 1, "connect": {"token": ct["token"], "name": "probe"}}))
            await ws.send(json.dumps({"id": 2, "subscribe": {"channel": f"pair:{pair}", "token": sub["token"]}}))
            await asyncio.sleep(0.8)
            await asyncio.get_running_loop().run_in_executor(None, action)
            end = time.time() + wait
            while time.time() < end:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                for line in str(raw).splitlines():
                    if not line.strip():
                        continue
                    m = json.loads(line)
                    if m == {}:
                        await ws.send("{}")
                    elif "push" in m:
                        got.append(m["push"].get("pub", {}).get("data", {}))
        return got

    return asyncio.run(run())


def main():
    her, him, other = signup("ona"), signup("on"), signup("chuzhoy")
    log(f"она={her['uid']} он={him['uid']} чужой={other['uid']}")
    pair, hung = "", []
    try:
        log("=== 0. пара ===")
        st, res = api("/api/waiting/create", {"name": "Он", "returnDate": "2027-05-15 00:00:00.000Z"}, her["token"])
        pair = (res or {}).get("pairId", "")
        if not pair:
            log(f"!! пара не создалась: {st} {res}")
            sys.exit(1)
        api("/api/waiting/claim", {"code": res.get("code", "")}, him["token"])
        api("/api/waiting/approve", {"groupId": pair, "approve": True}, her["token"])
        # пропуск с новым group_ids
        for who in (her, him):
            st, a = api("/api/collections/users/auth-refresh", {}, who["token"])
            who["token"] = a.get("token", who["token"])

        log("=== 1. состояние и стартовый набор ===")
        st, s = api(f"/api/tree/state?group={pair}&season={S}", None, her["token"])
        check("state отвечает", st == 200 and s.get("ok"), f"{st} {s}")
        check("стартовый набор: два красных шара", (s.get("owned") or {}).get("red") == 2, str(s.get("owned")))
        check("ёлка по умолчанию — ель со звездой и гирляндой", s.get("tree") == {"kind": "fir", "star": True, "garland": True}, str(s.get("tree")))
        st, s2 = api(f"/api/tree/state?group={pair}&season={S}", None, her["token"])
        check("стартовый набор не выдаётся второй раз", (s2.get("owned") or {}).get("red") == 2, str(s2.get("owned")))
        st, _ = api(f"/api/tree/state?group={pair}&season={S}", None, other["token"])
        check("чужому ёлка закрыта", st == 403, str(st))

        log("=== 2. вешаем ===")
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 50, "y": 40}, her["token"])
        check("первый красный шар", st == 200 and r.get("ok"), f"{st} {r}")
        hung.append(r.get("toy", {}).get("id"))
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 40, "y": 55}, her["token"])
        check("второй красный шар", st == 200, f"{st} {r}")
        hung.append(r.get("toy", {}).get("id"))
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 60, "y": 55}, her["token"])
        check("третьего красного нет в коробке", st == 409 and r.get("error") == "not_owned", f"{st} {r}")
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 200, "y": 55}, her["token"])
        check("точка за холстом отвергнута", st == 400, f"{st} {r}")
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 50, "y": 50}, other["token"])
        check("чужой не вешает", st == 403, f"{st} {r}")
        st, s = api(f"/api/tree/state?group={pair}&season={S}", None, him["token"])
        check("партнёр видит обе игрушки", len(s.get("toys") or []) == 2, str(len(s.get("toys") or [])))
        st, r = api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 45, "y": 62}, him["token"])
        check("у партнёра свои красные шары", st == 200, f"{st} {r}")
        hung.append(r.get("toy", {}).get("id"))

        log("=== 3. двигаем и снимаем ===")
        st, r = api("/api/tree/move", {"id": hung[0], "x": 33.3, "y": 44.4}, him["token"])
        check("партнёр двигает её игрушку", st == 200, f"{st} {r}")
        st, s = api(f"/api/tree/state?group={pair}&season={S}", None, her["token"])
        moved = [t for t in s.get("toys", []) if t["id"] == hung[0]]
        check("новая точка сохранилась", moved and moved[0]["x"] == 33.3 and moved[0]["y"] == 44.4, str(moved))
        st, r = api("/api/tree/remove", {"id": hung[0]}, him["token"])
        check("партнёр снимает её игрушку", st == 200, f"{st} {r}")
        st, r = api("/api/tree/remove", {"id": hung[0]}, her["token"])
        check("снятая уже игрушка — тоже успех", st == 200 and r.get("gone"), f"{st} {r}")
        st, r = api("/api/tree/remove", {"id": hung[1]}, other["token"])
        check("чужой не снимает", st == 403, f"{st} {r}")

        log("=== 4. гонка: одна свободная штука, два запроса разом ===")
        res = []
        def go():
            res.append(api("/api/tree/hang", {"group": pair, "season": S, "toy": "red", "x": 52, "y": 66}, her["token"]))
        ts = [threading.Thread(target=go) for _ in range(2)]
        [t.start() for t in ts]; [t.join() for t in ts]
        oks = [r for st, r in res if st == 200]
        check("из двух одновременных прошёл один", len(oks) == 1, str([st for st, _ in res]))
        hung += [r["toy"]["id"] for r in oks]

        log("=== 5. ёлка: стиль, звезда, гирлянда ===")
        st, r = api("/api/tree/set", {"group": pair, "season": S, "kind": "snowy"}, her["token"])
        check("«Под снегом» без сундука не ставится", st == 409, f"{st} {r}")
        st, r = api("/api/tree/set", {"group": pair, "season": S, "garland": False}, her["token"])
        check("гирлянда выключается", st == 200 and r["tree"]["garland"] is False, f"{st} {r}")
        st, s = api(f"/api/tree/state?group={pair}&season={S}", None, him["token"])
        check("партнёр видит выключенную гирлянду", s.get("tree", {}).get("garland") is False, str(s.get("tree")))
        check("сезон в списке ёлок пары", S in (s.get("seasons") or []), str(s.get("seasons")))

        log("=== 5б. партнёр слышит правки каналом пары ===")
        got = listen_pair(him, pair, lambda: (
            api("/api/tree/hang", {"group": pair, "season": S, "toy": "gold", "x": 47, "y": 58}, her["token"]),
        ))
        made = [d for d in got if d.get("collection") == "tree_toys" and d.get("event") == "create"]
        check("повешенная игрушка пришла партнёру", bool(made), str([(d.get("event"), d.get("collection")) for d in got]))
        rec = made[0]["record"] if made else {}
        check("в событии пара и сезон числом", rec.get("group_id") == pair and rec.get("season") == S, str(rec))
        if rec.get("id"):
            hung.append(rec["id"])
            got = listen_pair(him, pair, lambda: (
                api("/api/tree/move", {"id": rec["id"], "x": 46, "y": 59}, her["token"]),
                api("/api/tree/set", {"group": pair, "season": S, "star": False}, her["token"]),
                api("/api/tree/remove", {"id": rec["id"]}, her["token"]),
            ))
            ev = [(d.get("event"), d.get("collection")) for d in got]
            check("сдвиг, звезда и снятие пришли партнёру", ("update", "tree_toys") in ev and ("update", "pair_trees") in ev and ("delete", "tree_toys") in ev, str(ev))

        log("=== 6. покупка и закрытые поля ===")
        st, r = api("/api/toys/buy", {"key": "disco"}, her["token"])
        check("без монет не купить", st == 402 and r.get("error") == "insufficient", f"{st} {r}")
        st, r = api("/api/toys/buy", {"key": "tupair"}, her["token"])
        check("игрушка из сундука не продаётся", st == 400, f"{st} {r}")
        st, r = api(f"/api/collections/users/records/{her['uid']}", {"owned_toys": json.dumps({"red": 99})}, her["token"], method="PATCH")
        st2, s = api(f"/api/tree/state?group={pair}&season={S}", None, her["token"])
        check("коробку не вписать себе правкой профиля", (s.get("owned") or {}).get("red") == 2, f"{st} {s.get('owned')}")
        st, r = api("/api/collections/tree_toys/records", {"group_id": pair, "season": S, "toy": "red", "x": 1, "y": 1, "author": her["uid"]}, her["token"])
        check("игрушку не создать мимо сервера", st in (400, 403), f"{st} {r}")
    finally:
        log("=== уборка ===")
        for tid in hung:
            if tid:
                api("/api/tree/remove", {"id": tid}, her["token"])
        if pair:
            api(f"/api/collections/groups/records/{pair}", None, her["token"], method="DELETE")
        codes = [api(f"/api/collections/users/records/{w['uid']}", None, w["token"], method="DELETE")[0] for w in (her, him, other)]
        check("тестовые аккаунты убраны", all(c in (204, 404) for c in codes), str(codes))

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
