#!/usr/bin/env python3
"""Живой регресс пары с пустым местом («он в армии»).

Проверяем весь путь: она заводит пару одна, пишет в неё, он вводит код из
любого аккаунта, она подтверждает, история становится ему видна. Плюс то, что
ломать нельзя: код не гаснет сам, чужой без подтверждения внутрь не попадает,
служебные поля не переписываются через API.

Гоняется по живому серверу, за собой убирает:
    python3 pocketbase/waiting_pair.test.py
"""
import json
import random
import string
import sys
import time
import urllib.error
import urllib.request

BASE = "https://togetherly.duckdns.org"
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
    email = f"waiting-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}"); sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    log(f"{tag}: uid={auth['record']['id']}")
    return {"uid": auth["record"]["id"], "token": auth["token"]}


def main():
    her = signup("Она")
    him = signup("Он")
    stranger = signup("Чужой")

    log("=== 1. она заводит пару одна ===")
    st, res = api("/api/waiting/create", {
        "name": "Дима", "returnDate": "2027-05-15 00:00:00.000Z"}, her["token"])
    pair = (res or {}).get("pairId", "")
    code = (res or {}).get("code", "")
    check("пара с пустым местом создана", st == 200 and bool(pair) and bool(code),
          f"{st} {res}")
    if not pair:
        sys.exit(1)

    st, g = api(f"/api/collections/groups/records/{pair}", None, her["token"])
    check("она видит свою пару", st == 200 and g.get("waiting_mode") is True,
          f"{st} waiting_mode={g.get('waiting_mode')}")
    check("заглушка на месте", g.get("placeholder_name") == "Дима" and bool(g.get("return_date")),
          f"{g.get('placeholder_name')} / {g.get('return_date')}")

    log("=== 2. она пишет в пару до его прихода ===")
    st, msg = api("/api/collections/chat_messages/records", {
        "group_id": pair, "user_uid": her["uid"], "user_name": "Она",
        "text": "Жду тебя", "ts": int(time.time() * 1000)}, her["token"])
    check("сообщение легло в пару, а не в личный аккаунт", st in (200, 201),
          f"{st} {msg.get('message', '')}")

    log("=== 3. служебные поля через API не переписать ===")
    st, r = api(f"/api/collections/groups/records/{pair}",
                {"claim_token": "HACKED1"}, her["token"], method="PATCH")
    check("свой код подменить нельзя", st == 403, f"{st} {r.get('message')}")
    st, r = api(f"/api/collections/groups/records/{pair}",
                {"waiting_mode": False}, her["token"], method="PATCH")
    check("режим ожидания снимает только сервер", st == 403, f"{st} {r.get('message')}")

    log("=== 4. он вводит код тем же полем, что и обычный инвайт ===")
    st, r = api("/api/invite/accept", {"code": code}, him["token"])
    check("общий приём кода узнаёт код второго места",
          st == 200 and r.get("waiting") is True and r.get("pairId") == pair, f"{st} {r}")

    st, r = api("/api/waiting/claim", {"code": code}, him["token"])
    check("заявка принята и ждёт подтверждения",
          st == 200 and r.get("status") == "pending", f"{st} {r}")

    st, r = api(f"/api/collections/groups/records/{pair}", None, him["token"])
    check("до подтверждения переписка ему не видна", st != 200, f"{st}")

    log("=== 5. чужой с тем же кодом не должен вытеснить его ===")
    st, r = api("/api/waiting/claim", {"code": code}, stranger["token"])
    check("чужой тоже только просится, а не входит",
          st == 200 and r.get("status") == "pending", f"{st} {r}")
    st, r = api("/api/waiting/approve", {"groupId": pair, "approve": True}, stranger["token"])
    check("чужой не может подтвердить сам себя", st == 403, f"{st} {r.get('message')}")

    log("=== 6. она отклоняет заявку ===")
    st, r = api("/api/waiting/approve", {"groupId": pair, "approve": False}, her["token"])
    check("отклонение проходит", st == 200 and r.get("approved") is False, f"{st} {r}")
    st, r = api("/api/waiting/state?code=" + code, None, stranger["token"])
    check("отклонённый видит отказ", st == 200 and r.get("status") in ("rejected", "none"),
          f"{st} {r}")

    log("=== 7. он просится снова, она подтверждает ===")
    st, r = api("/api/waiting/claim", {"code": code}, him["token"])
    check("повторная заявка проходит", st == 200 and r.get("status") == "pending", f"{st} {r}")
    st, r = api("/api/waiting/approve", {"groupId": pair, "approve": True}, her["token"])
    check("подтверждение проходит", st == 200 and r.get("approved") is True, f"{st} {r}")

    st, g = api(f"/api/collections/groups/records/{pair}", None, him["token"])
    check("пара стала его", st == 200 and him["uid"] in (g.get("members") or []),
          f"{st} members={g.get('members')}")
    check("режим ожидания снят и код погашен",
          g.get("waiting_mode") is False and not g.get("claim_token"),
          f"waiting={g.get('waiting_mode')} token={g.get('claim_token')!r}")

    st, lst = api(f"/api/collections/chat_messages/records?filter=(group_id='{pair}')",
                  None, him["token"])
    check("история переписки видна ему без переноса",
          st == 200 and any(i.get("text") == "Жду тебя" for i in lst.get("items", [])),
          f"{st} писем={len(lst.get('items', []))}")

    log("=== 8. код не протухает: у второй пары он живёт как есть ===")
    her2 = signup("Она2")
    st, res2 = api("/api/waiting/create", {"name": "Ждём"}, her2["token"])
    pair2, code2 = res2.get("pairId", ""), res2.get("code", "")
    st, g2 = api(f"/api/collections/groups/records/{pair2}", None, her2["token"])
    check("код виден хозяйке в любой момент", st == 200 and g2.get("claim_token") == code2,
          f"{g2.get('claim_token')} == {code2}")
    st, r = api("/api/waiting/reset", {"groupId": pair2}, her2["token"])
    check("сброс выдаёт новый код", st == 200 and r.get("code") and r.get("code") != code2,
          f"{st} {r}")
    st, r = api("/api/waiting/claim", {"code": code2}, him["token"])
    check("прежний код после сброса не работает", st == 404, f"{st} {r.get('message')}")

    log("=== уборка ===")
    for gid, who in ((pair, her), (pair2, her2)):
        if gid:
            api(f"/api/collections/groups/records/{gid}", None, who["token"], method="DELETE")
    for name, u in (("Она", her), ("Он", him), ("Чужой", stranger), ("Она2", her2)):
        st, _ = api(f"/api/collections/users/records/{u['uid']}", None, u["token"], method="DELETE")
        log(f"аккаунт {name} удалён → {st}")

    log(f"ИТОГ: пройдено {len(OK)}, провалено {len(FAIL)}" + (f" → {FAIL}" if FAIL else ""))
    sys.exit(1 if FAIL else 0)


main()
