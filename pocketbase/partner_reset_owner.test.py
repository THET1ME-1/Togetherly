#!/usr/bin/env python3
"""Живой регресс: хозяин аккаунта видит и отменяет смену своего пароля.

Сброс через партнёра (partner_reset.pb.js) отдаёт код партнёру. Попросить код
на чужую почту может и сам партнёр: код придёт ему же, и он поставит новый
пароль. До 10.11.2026 хозяин аккаунта об этом не узнавал вовсе — его просто
выкидывало из приложения.

Теперь хозяину уходит уведомление, приложение спрашивает
`GET /api/auth/partner-reset/own` и показывает лист с кнопкой «Это не я»
(`POST /api/auth/partner-reset/cancel`). Отмена гасит и код, и уже выданный
пропуск на новый пароль.

Гоняется по живому серверу, заводит временные аккаунты
(`resetown-probe-*@example.com`) и убирает за собой:
    python3 pocketbase/partner_reset_owner.test.py
"""
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
    req = urllib.request.Request(BASE + path, data=body,
                                 method=method or ("POST" if body is not None else "GET"))
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


def signup(tag, name):
    email = f"resetown-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": name, "name": name})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"],
            "email": email, "pwd": pwd, "name": name}


def code_for(partner):
    st, js = api("/api/auth/partner-reset/pending", None, partner["token"])
    return ((js or {}).get("pending") or {}).get("code", "")


def main():
    her = signup("ona", "Маша Проба")
    him = signup("on", "Петя Проба")
    log(f"она={her['uid']} он={him['uid']}")
    pair = ""
    try:
        st, res = api("/api/waiting/create",
                      {"name": "Он", "returnDate": "2027-05-15 00:00:00.000Z"},
                      her["token"])
        pair = (res or {}).get("pairId", "")
        if not pair:
            log(f"!! пара не создалась: {st} {res}")
            sys.exit(1)
        api("/api/waiting/claim", {"code": res.get("code", "")}, him["token"])
        api("/api/waiting/approve", {"groupId": pair, "approve": True}, her["token"])
        # `users.group_ids` догоняет состав пары не мгновенно, а сброс ищет
        # партнёра по нему.
        time.sleep(3)

        log("=== 1. пока запроса нет, хозяину показывать нечего ===")
        st, js = api("/api/auth/partner-reset/own", None, her["token"])
        check("запроса нет", st == 200 and js.get("pending") is None, f"{st} {js}")

        log("=== 2. код на её почту: она видит запрос и отменяет ===")
        st, js = api("/api/auth/partner-reset/request", {"email": her["email"]})
        check("код ушёл партнёру", st == 200 and js.get("via") == "partner", f"{st} {js}")
        code = code_for(him)
        check("партнёр видит код", len(code) == 6, code)
        st, js = api("/api/auth/partner-reset/own", None, her["token"])
        own = (js or {}).get("pending") or {}
        check("хозяйка видит запрос на свой аккаунт",
              st == 200 and own.get("stage") == "code" and own.get("expiresAt", 0) > own.get("at", 0) > 0,
              f"{st} {js}")
        check("и у кого код", own.get("partnerName") == him["name"], str(own.get("partnerName")))
        check("самого кода ей не показывают", "code" not in own, str(sorted(own)))
        st, js = api("/api/auth/partner-reset/own", None, him["token"])
        check("у партнёра своего запроса нет", st == 200 and js.get("pending") is None, f"{js}")
        st, js = api("/api/auth/partner-reset/cancel", {}, her["token"])
        check("отмена принята", st == 200 and js.get("ok") is True and js.get("cancelled") is True,
              f"{st} {js}")
        check("кода у партнёра больше нет", code_for(him) == "")
        st, js = api("/api/auth/partner-reset/verify", {"email": her["email"], "code": code})
        check("отменённый код не принимается", st == 404, f"{st} {js}")
        st, js = api("/api/auth/partner-reset/own", None, her["token"])
        check("запрос у хозяйки пропал", st == 200 and js.get("pending") is None, f"{js}")

        log("=== 3. код уже введён: отмена гасит пропуск на новый пароль ===")
        st, js = api("/api/auth/partner-reset/request", {"email": him["email"]})
        check("код на его почту ушёл ей", st == 200 and js.get("via") == "partner", f"{st} {js}")
        code = code_for(her)
        st, js = api("/api/auth/partner-reset/verify", {"email": him["email"], "code": code})
        ticket = (js or {}).get("ticket", "")
        check("верный код дал пропуск", st == 200 and len(ticket) == 40, f"{st}")
        st, js = api("/api/auth/partner-reset/own", None, him["token"])
        own = (js or {}).get("pending") or {}
        check("хозяин видит, что код уже введён", st == 200 and own.get("stage") == "ticket",
              f"{st} {js}")
        st, js = api("/api/auth/partner-reset/cancel", {}, him["token"])
        check("отмена принята", st == 200 and js.get("cancelled") is True, f"{st} {js}")
        st, js = api("/api/auth/partner-reset/complete",
                     {"ticket": ticket, "password": "Stolen" + rnd(10) + "!"})
        check("по отменённому пропуску пароль не сменить", st == 410, f"{st} {js}")
        st, _ = api("/api/collections/users/auth-with-password",
                    {"identity": him["email"], "password": him["pwd"]})
        check("его пароль прежний", st == 200, f"{st}")
        st, _ = api("/api/auth/partner-reset/own", None, him["token"])
        check("его вход не сорван", st == 200, f"{st}")

        log("=== 4. отменять нечего — тоже не ошибка ===")
        st, js = api("/api/auth/partner-reset/cancel", {}, her["token"])
        check("пустая отмена отвечает спокойно",
              st == 200 and js.get("ok") is True and js.get("cancelled") is False, f"{st} {js}")
        st, js = api("/api/auth/partner-reset/own", None)
        check("без входа запрос не отдают", st == 401, f"{st}")
    finally:
        log("=== уборка ===")
        if pair:
            api(f"/api/collections/groups/records/{pair}", None, her["token"], method="DELETE")
        codes = []
        for who in (her, him):
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
