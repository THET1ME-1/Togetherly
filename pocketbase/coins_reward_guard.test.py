"""Награды за партнёра и за серию настроений платят только за свою пару.

До 10.11.2026 сервер верил номеру из запроса: выдуманный `partnerUid` давал
50 монет, выдуманный `groupId` — 10, и так сколько угодно раз. Живой прогон на
боевом сервере: заводит свою пробную пару и постороннего, убирает за собой.

    python3 pocketbase/coins_reward_guard.test.py
"""
import json
import random
import string
import sys
import time
import urllib.error
import urllib.request

BASE = "https://togetherly.day"
passed = failed = 0


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        BASE + path, data=body,
        method=method or ("POST" if body is not None else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"raw": raw[:200]}


def check(name, good, got=""):
    global passed, failed
    if good:
        passed += 1
        print("  ок  ", name)
    else:
        failed += 1
        print("  МИМО", name, "|", got)


def rnd(n):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"coins-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    assert st in (200, 201), (st, r)
    st, a = api("/api/collections/users/auth-with-password",
                {"identity": email, "password": pwd})
    return {"uid": a["record"]["id"], "token": a["token"]}


def coins(who):
    st, r = api(f"/api/collections/users/records/{who['uid']}", None, who["token"])
    return int(r.get("coins") or 0)


me, partner, stranger = signup("a"), signup("b"), signup("c")
group = ""
try:
    st, res = api("/api/waiting/create",
                  {"name": "X", "returnDate": "2027-05-15 00:00:00.000Z"}, me["token"])
    group = res["pairId"]
    api("/api/waiting/claim", {"code": res["code"]}, partner["token"])
    api("/api/waiting/approve", {"groupId": group, "approve": True}, me["token"])
    time.sleep(3)

    print("награда за партнёра")
    start = coins(me)
    for _ in range(2):
        st, r = api("/api/coins/partner-invite", {"partnerUid": "nobody" + rnd(9)}, me["token"])
        check("выдуманный партнёр монет не даёт", r.get("ok") is not True, (st, r))
    st, r = api("/api/coins/partner-invite", {"partnerUid": stranger["uid"]}, me["token"])
    check("посторонний человек монет не даёт", r.get("ok") is not True, (st, r))
    st, r = api("/api/coins/partner-invite", {"partnerUid": me["uid"]}, me["token"])
    check("сам себе партнёром не засчитывается", r.get("ok") is not True, (st, r))
    check("баланс после отказов прежний", coins(me) == start, coins(me) - start)
    st, r = api("/api/coins/partner-invite", {"partnerUid": partner["uid"]}, me["token"])
    check("свой партнёр даёт 50", r.get("ok") is True and r.get("awarded") == 50, (st, r))
    st, r = api("/api/coins/partner-invite", {"partnerUid": partner["uid"]}, me["token"])
    check("второй раз за того же партнёра не платят", r.get("alreadyGranted") is True, (st, r))
    check("итого прибавилось ровно 50", coins(me) == start + 50, coins(me) - start)

    print("награда за серию настроений")
    start = coins(me)
    for _ in range(2):
        st, r = api("/api/coins/mood-streak", {"groupId": "nogroup" + rnd(8)}, me["token"])
        check("выдуманная пара монет не даёт", r.get("ok") is not True, (st, r))
    st, r = api("/api/coins/mood-streak", {"groupId": group}, stranger["token"])
    check("чужая пара монет не даёт", r.get("ok") is not True, (st, r))
    check("баланс после отказов прежний", coins(me) == start, coins(me) - start)
    st, r = api("/api/coins/mood-streak", {"groupId": group}, me["token"])
    check("своя пара даёт 10", r.get("ok") is True and r.get("awarded") == 10, (st, r))
    st, r = api("/api/coins/mood-streak", {"groupId": group}, me["token"])
    check("второй раз за неделю не платят", r.get("cooldown") is True, (st, r))
    check("итого прибавилось ровно 10", coins(me) == start + 10, coins(me) - start)
finally:
    if group:
        api(f"/api/collections/groups/records/{group}", None, me["token"], method="DELETE")
    gone = [api(f"/api/collections/users/records/{w['uid']}", None, w["token"], method="DELETE")[0]
            for w in (me, partner, stranger)]
    print("уборка:", gone)

print(f"\nпрошло {passed}, мимо {failed}")
sys.exit(1 if failed else 0)
