#!/usr/bin/env python3
"""Живой регресс подарка Togetherly+.

Проверяем то, что ломается молча: кому уходит доступ, чья почта попадает в счёт
и кто записан получателем в `lava_invoices`. Ошибка здесь стоит дорого — крон
выдаёт Плюс по этой записи, и с плательщиком в поле `user_uid` подарок открылся
бы не тому, кто его получил.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/plus_gift.test.py

Один прогон заводит один настоящий счёт в lava.top. Он остаётся неоплаченным и
ни к чему не обязывает, но в кабинете продавца будет виден.
"""
import json
import os
import random
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8090")
DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
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
        with urllib.request.urlopen(req, timeout=25) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def sql(query):
    out = subprocess.run(["sqlite3", DB, query], capture_output=True, text=True)
    return out.stdout.strip()


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"gift-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"], "email": email}


def main():
    her = signup("dar")     # дарит
    him = signup("pol")     # получает
    stranger = signup("chu")  # ни при чём
    log(f"даритель={her['uid']} получатель={him['uid']} чужой={stranger['uid']}")

    log("=== 0. пара собирается ===")
    st, res = api("/api/waiting/create",
                  {"name": "Получатель", "returnDate": "2027-05-15 00:00:00.000Z"},
                  her["token"])
    pair = (res or {}).get("pairId", "")
    code = (res or {}).get("code", "")
    if not pair:
        log(f"!! пара не создалась: {st} {res}")
        sys.exit(1)
    api("/api/waiting/claim", {"code": code}, him["token"])
    api("/api/waiting/approve", {"groupId": pair, "approve": True}, her["token"])
    st, g = api(f"/api/collections/groups/records/{pair}", None, him["token"])
    check("пара собрана", st == 200 and him["uid"] in (g.get("members") or []), f"{st}")

    log("=== 1. витрина подарка ===")
    st, gift = api("/api/lava/gift?currency=RUB", None, her["token"])
    partners = (gift or {}).get("partners") or []
    check("роут отвечает дарителю", st == 200 and gift.get("ok") is True, f"{st} {gift}")
    check("в списке ровно получатель, а не он сам",
          [p.get("uid") for p in partners] == [him["uid"]],
          str([p.get("uid") for p in partners]))
    check("у получателя Плюса ещё нет",
          bool(partners) and partners[0].get("already") is False)
    check("цена подарка названа", (gift.get("price") or 0) > 0,
          f"price={gift.get('price')}")
    check("цена самой покупки названа", (gift.get("plusPrice") or 0) > 0,
          f"plusPrice={gift.get('plusPrice')}")
    check("скидка — целое число процентов",
          isinstance(gift.get("discount"), int) and 0 <= gift["discount"] < 100,
          f"discount={gift.get('discount')}")

    st, eur = api("/api/lava/gift?currency=EUR", None, her["token"])
    check("в евро приходит своя цена, а не рублёвая",
          st == 200 and eur.get("currency") == "EUR"
          and (eur.get("price") or 0) > 0 and eur["price"] != gift.get("price"),
          f"{st} {eur.get('currency')} {eur.get('price')} против {gift.get('price')}")

    st, mine = api("/api/lava/gift?currency=RUB", None, stranger["token"])
    check("одиночке дарить некому",
          st == 200 and not (mine.get("partners") or []), f"{st} {mine}")

    log("=== 2. чужую пару подарком не тронуть ===")
    st, r = api("/api/lava/checkout",
                {"gift": True, "groupId": pair}, stranger["token"])
    check("посторонний получает отказ по членству",
          st == 403 and r.get("error") == "not_member", f"{st} {r}")

    log("=== 3. счёт заводится на почту ПОЛУЧАТЕЛЯ ===")
    st, buy = api("/api/lava/checkout",
                  {"gift": True, "groupId": pair, "currency": "RUB"}, her["token"])
    check("счёт создан", st == 200 and buy.get("ok") is True and bool(buy.get("url")),
          f"{st} {buy}")
    check("ответ помечен подарком", buy.get("gift") is True, str(buy.get("gift")))
    contract = buy.get("contractId", "")

    row = sql("SELECT user_uid || '|' || email || '|' || gifted_by "
              f"FROM lava_invoices WHERE contract_id = '{contract}'") if contract else ""
    parts = row.split("|") if row else []
    check("получателем записан партнёр, а не плательщик",
          len(parts) == 3 and parts[0] == him["uid"], row)
    check("в счёте почта партнёра", len(parts) == 3 and parts[1] == him["email"], row)
    check("даритель записан", len(parts) == 3 and parts[2] == her["uid"], row)

    log("=== 4. у кого Плюс уже есть, тому не продаём второй раз ===")
    sql(f"UPDATE users SET plus = 1 WHERE id = '{him['uid']}'")
    st, again = api("/api/lava/checkout",
                    {"gift": True, "groupId": pair, "currency": "RUB"}, her["token"])
    check("повторный подарок отвергнут", st == 200 and again.get("already") is True,
          f"{st} {again}")
    st, gift2 = api("/api/lava/gift?currency=RUB", None, her["token"])
    p2 = (gift2 or {}).get("partners") or []
    check("витрина показывает, что доступ уже есть",
          bool(p2) and p2[0].get("already") is True, str(p2))

    log("=== уборка ===")
    if contract:
        sql(f"DELETE FROM lava_invoices WHERE contract_id = '{contract}'")
    api(f"/api/collections/groups/records/{pair}", None, her["token"], method="DELETE")
    for who in (her, him, stranger):
        api(f"/api/collections/users/records/{who['uid']}", None, who["token"],
            method="DELETE")
    left = sql("SELECT count(*) FROM users WHERE email LIKE 'gift-probe-%'")
    check("тестовые аккаунты убраны", left == "0", f"осталось {left}")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
