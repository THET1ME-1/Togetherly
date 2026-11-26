#!/usr/bin/env python3
"""Живая проверка предпросмотра сезона (26.11.2026), гонять НА VPS:

    python3 /root/season_preview.test.py

Предпросмотр — список аккаунтов в /opt/pocketbase/pb_data/.season_preview.json
(`{"<uid>": "ГГГГ-ММ-ДД"}`): для них сервер живёт в этот день. Тест заводит
пробную пару, кладёт первого в список на 2026-12-01 и проверяет: маршрут
`/api/season/preview` отдаёт день и спрятанные наборы; в состоянии сундука
есть зимний сезон; в таблице зимнего сундука вещи спрятанного набора;
спрятанная рамка из магазина покупается; второй (не в списке) ничего этого
не видит. После себя убирает пару, аккаунты и запись в списке.
"""
import json
import os
import random
import secrets
import string
import sys
import urllib.error
import urllib.request

sys.path.insert(0, "/opt/pocketbase/tools")
from upload_badges import drop_superuser, superuser_token  # noqa: E402

B = "http://127.0.0.1:8090"
LIST = "/opt/pocketbase/pb_data/.season_preview.json"
ok = fail = 0


def api(p, d=None, t=None, m=None):
    r = urllib.request.Request(B + p, data=json.dumps(d).encode() if d is not None else None, method=m or ("POST" if d is not None else "GET"))
    r.add_header("Content-Type", "application/json")
    if t:
        r.add_header("Authorization", t)
    try:
        with urllib.request.urlopen(r, timeout=20) as x:
            return x.status, json.loads(x.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  ✓ {name}")
    else:
        fail += 1
        print(f"  ✗ {name} — {detail}")


def user(tag):
    s = "".join(random.choice(string.ascii_lowercase) for _ in range(6))
    em, pw = f"preview-probe-{tag}-{s}@example.com", "Probe" + s + "123!"
    api("/api/collections/users/records", {"email": em, "password": pw, "passwordConfirm": pw, "name": "Probe"})
    _, a = api("/api/collections/users/auth-with-password", {"identity": em, "password": pw})
    return a["token"], a["record"]["id"]


def main():
    email, su = superuser_token()
    before = open(LIST).read() if os.path.exists(LIST) else None
    made = []
    try:
        (ta, ua), (tb, ub) = user("a"), user("b")
        made = [(ta, ua), (tb, ub)]
        _, res = api("/api/waiting/create", {"name": "Он", "returnDate": "2027-05-15 00:00:00.000Z"}, ta)
        g = res.get("pairId")
        api("/api/waiting/claim", {"code": res.get("code", "")}, tb)
        api("/api/waiting/approve", {"groupId": g, "approve": True}, ta)
        lst = json.loads(before) if before else {}
        lst[ua] = "2026-12-01"
        open(LIST, "w").write(json.dumps(lst))
        api(f"/api/collections/users/records/{ua}", {"coins": 300}, su, "PATCH")

        st, r = api("/api/season/preview", None, ta)
        check("предпросмотр отдаёт день", st == 200 and r.get("day") == "2026-12-01", f"{st} {r}")
        check("и спрятанный зимний набор", "winter" in (r.get("sets") or []), f"{r}")
        st, r = api("/api/season/preview", None, tb)
        check("второму предпросмотра нет", st == 200 and not r.get("day"), f"{st} {r}")

        _, r = api("/api/chest/state?tz=180&frames=1&wear=1&outfits=1", None, ta)
        keys = [s.get("key") for s in r.get("seasons", [])]
        check("в сундуке зимний сезон, осеннего нет", "winter" in keys and "autumn" not in keys, f"{keys}")
        _, r = api("/api/chest/state?tz=180&frames=1&wear=1&outfits=1", None, tb)
        keys = [s.get("key") for s in r.get("seasons", [])]
        check("у второго по-прежнему ноябрь", "winter" not in keys, f"{keys}")

        _, r = api("/api/chest/state?tz=180&frames=1&wear=1&outfits=1&chest=winter", None, ta)
        kinds = {}
        for o in r.get("odds", []):
            kinds[o.get("kind")] = kinds.get(o.get("kind"), 0) + 1
        check("в зимнем сундуке спрятанные рамки и значки", kinds.get("frame", 0) >= 10 and kinds.get("badge", 0) >= 6, f"{kinds}")
        st, o = api("/api/chest/open", {"openId": secrets.token_hex(8)[:15], "groupId": g, "tz": 180, "platform": "android",
                                         "frames": True, "wear": True, "outfits": True, "chest": "winter"}, ta)
        check("зимний сундук открывается", st == 200 and (o.get("prize") or {}).get("key"), f"{st} {o.get('error')}")

        st, r = api("/api/coins/purchase-feature", {"featureId": "frame:frame_ny_lights"}, ta)
        check("спрятанная рамка из магазина покупается", st == 200 and "frame:frame_ny_lights" in (r.get("ownedFeatures") or []), f"{st} {r.get('error')}")
        st, r = api("/api/coins/purchase-icon", {"iconId": "Winter Cocoa"}, ta)
        check("спрятанный значок покупается", st == 200, f"{st} {r.get('error')}")
        st, r = api("/api/wear/buy", {"key": "wf_beanie"}, ta)
        check("спрятанная бини покупается", st == 200, f"{st} {r.get('error')}")
        api(f"/api/collections/users/records/{ub}", {"coins": 300}, su, "PATCH")
        st, r = api("/api/coins/purchase-feature", {"featureId": "frame:frame_ny_star_wreath"}, tb)
        check("второму спрятанная рамка не продаётся", st == 400, f"{st} {r}")
        api(f"/api/collections/groups/records/{g}", None, ta, "DELETE")
    finally:
        if before is None:
            if os.path.exists(LIST):
                os.remove(LIST)
        else:
            open(LIST, "w").write(before)
        for t, u in made:
            api(f"/api/collections/users/records/{u}", None, t, "DELETE")
        drop_superuser(email)
    print(f"ИТОГ: {ok} прошло, {fail} упало")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
