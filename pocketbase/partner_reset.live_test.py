# -*- coding: utf-8 -*-
"""Живая проверка сброса пароля через партнёра и способов входа на проде.

Ходит тестовой парой (`~/keys/togetherly-test-pair.txt`, аккаунты
claude-test-231a/b). Пароль аккаунта А в конце ставится тот же, что был.
Партнёру Б уходит пуш, но телефона у него нет.

Запуск: python3 pocketbase/partner_reset.live_test.py [--deny]
  --deny  ещё и отказ партнёра (ждёт две минуты между запросами).
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

BASE = "https://togetherly.day"
KEYS = os.path.expanduser("~/keys/togetherly-test-pair.txt")

ok = True


def check(name, cond):
    global ok
    print(("  ✓ " if cond else "  ✗ ") + name)
    if not cond:
        ok = False


def call(method, path, body=None, token=None):
    headers = {"Content-Type": "application/json", "User-Agent": "togetherly-live-test"}
    if token:
        headers["Authorization"] = token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except ValueError:
            return e.code, {}


def login(email, password):
    st, js = call("POST", "/api/collections/users/auth-with-password", {"identity": email, "password": password})
    return js.get("token") if st == 200 else None


def main():
    text = open(KEYS, encoding="utf-8").read()
    pairs = re.findall(r"^([AB]): (\S+) / (\S+)", text, re.M)
    acc = {k: (e, p) for k, e, p in pairs}
    a_email, a_pass = acc["A"]
    b_email, b_pass = acc["B"]

    print("вход и способы входа")
    a_tok = login(a_email, a_pass)
    b_tok = login(b_email, b_pass)
    check("оба вошли по паролю", bool(a_tok and b_tok))
    st, js = call("GET", "/api/auth/methods", token=a_tok)
    check("способы входа: пароль есть", st == 200 and js.get("password") is True)
    st, js = call("POST", "/api/auth/set-password", {"password": "x" * 10}, token=a_tok)
    check("задать пароль поверх известного нельзя", st == 409 and js.get("code") == "has_password")
    st, js = call("POST", "/api/auth/unlink", {"provider": "google"}, token=a_tok)
    check("отвязать непривязанный — без ошибки", st == 200)

    print("код через партнёра")
    st, js = call("POST", "/api/auth/partner-reset/request", {"email": a_email.upper()})
    check("запрос по почте большими буквами ушёл партнёру", st == 200 and js.get("via") == "partner")
    st, js = call("POST", "/api/auth/partner-reset/request", {"email": a_email})
    check("повтор сразу — рано", st == 429 and js.get("code") == "gap")
    st, js = call("POST", "/api/auth/partner-reset/request", {"email": "nobody-%d@example.com" % time.time()})
    check("чужая почта — пары нет", st == 200 and js.get("via") == "none")

    st, js = call("GET", "/api/auth/partner-reset/pending", token=b_tok)
    pending = js.get("pending") or {}
    code = pending.get("code", "")
    check("партнёр видит код", st == 200 and len(code) == 6 and code.isdigit())
    st, js = call("GET", "/api/auth/partner-reset/pending", token=a_tok)
    check("сам человек кода не видит", st == 200 and js.get("pending") is None)

    wrong = "000000" if code != "000000" else "111111"
    st, js = call("POST", "/api/auth/partner-reset/verify", {"email": a_email, "code": wrong})
    check("неверный код — промах, осталось 4", st == 400 and js.get("left") == 4)
    st, js = call("POST", "/api/auth/partner-reset/verify", {"email": a_email, "code": code[:3] + " " + code[3:]})
    ticket = js.get("ticket", "")
    check("верный код даёт пропуск и имя партнёра", st == 200 and len(ticket) == 40 and js.get("partnerName"))
    st, js = call("POST", "/api/auth/partner-reset/verify", {"email": a_email, "code": code})
    check("второй раз код не годится", st == 404)

    st, js = call("POST", "/api/auth/partner-reset/complete", {"ticket": ticket, "password": "short"})
    check("короткий пароль не принят", st == 400 and js.get("code") == "short")
    st, js = call("POST", "/api/auth/partner-reset/complete", {"ticket": ticket, "password": a_pass})
    new_tok = js.get("token", "")
    check("пароль сменён, вход выдан", st == 200 and new_tok and (js.get("record") or {}).get("email", "").lower() == a_email.lower())
    st, _ = call("GET", "/api/auth/methods", token=a_tok)
    check("прежний токен больше не годится", st == 401)
    st, js = call("GET", "/api/auth/methods", token=new_tok)
    check("новый токен работает", st == 200 and js.get("password") is True)
    st, js = call("POST", "/api/auth/partner-reset/complete", {"ticket": ticket, "password": a_pass})
    check("пропуск одноразовый", st == 410)
    check("вход прежним паролем", bool(login(a_email, a_pass)))

    if "--deny" in sys.argv:
        print("отказ партнёра (ждём две минуты)")
        time.sleep(125)
        st, js = call("POST", "/api/auth/partner-reset/request", {"email": a_email})
        check("новый запрос через две минуты", st == 200 and js.get("via") == "partner")
        st, js = call("POST", "/api/auth/partner-reset/deny", token=b_tok)
        check("партнёр отказал", st == 200)
        st, js = call("GET", "/api/auth/partner-reset/pending", token=b_tok)
        check("кода у партнёра больше нет", js.get("pending") is None)
        st, js = call("POST", "/api/auth/partner-reset/verify", {"email": a_email, "code": "123456"})
        check("после отказа код не принимается", st == 404)

    print("всё верно" if ok else "ЕСТЬ ОШИБКИ")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
