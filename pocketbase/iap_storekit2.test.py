#!/usr/bin/env python3
"""Живой регресс: чек App Store целиком доезжает до записи о покупке.

Чек StoreKit 2 — это JWS длиной в несколько тысяч символов, а не короткий
токен Google Play. 30 августа 2026 на этом встала вся выдача Togetherly+ с
iPhone: подпись сходилась, `play_verify` отвечал `valid`, а `iap_purchases`
отвергал запись — поле `token` было ограничено 512 символами. Транзакция
откатывалась вместе с флагом доступа, и человек получал 500 после списания
денег.

Прошлые тесты этого не ловили: они посылали токен в два десятка символов.
Здесь чек намеренно длиной с настоящий JWS.

`store=rustore` пропускает сверку с магазином — единственный способ пройти
весь путь роута без настоящей покупки. Длина чека проверяется именно на нём:
строки записи в `iap_purchases` у всех магазинов общие.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/iap_storekit2.test.py
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
# Настоящий JWS транзакции App Store замерен по живому заказу MNMTMDQZ35:
# 5133 символа — заголовок с цепочкой сертификатов, нагрузка и подпись. Первая
# редакция теста слала 4000 и потому пропустила беду: поле держало 5000, чек не
# влезал, и выдача падала уже ПОСЛЕ починки. Берём с запасом вдвое.
JWS_LEN = 12000
# Замеренная длина настоящего чека — отдельной проверкой, чтобы запас в тесте
# нельзя было тихо срезать ниже реальности.
REAL_JWS_LEN = 5133
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


def jws(tag):
    """Чек длиной с настоящий: метка спереди, чтобы прибрать за собой."""
    head = f"probe-jws-{tag}-{rnd(10)}."
    return head + "".join(random.choice(string.ascii_letters + string.digits)
                          for _ in range(JWS_LEN - len(head)))


def signup(tag):
    email = f"jws-probe-{tag}-{rnd(6)}@example.com"
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
    buyer = signup("pok")     # покупает
    partner = signup("par")   # получает подарок
    log(f"покупатель={buyer['uid']} партнёр={partner['uid']}")

    log("=== 1. Togetherly+ себе, чек длиной с настоящий ===")
    tok = jws("plus")
    check("чек и правда длинный", len(tok) == JWS_LEN, f"{len(tok)} символов")
    check("запас больше настоящего чека App Store", JWS_LEN > REAL_JWS_LEN,
          f"{JWS_LEN} против замеренных {REAL_JWS_LEN}")
    st, buy = api("/api/coins/iap-purchase", {
        "productId": "togetherly_plus",
        "purchaseToken": tok,
        "store": "rustore",
    }, buyer["token"])
    check("покупка принята, а не 500", st == 200 and buy.get("ok") is True,
          f"{st} {buy}")
    row = sql(f"SELECT plus || '|' || plus_platform FROM users WHERE id = '{buyer['uid']}'")
    check("Плюс открылся", row.startswith("1|"), row)
    check("источник помечен магазином, из которого платили",
          row.endswith("|rustore"), row)

    stored = sql("SELECT length(token) FROM iap_purchases WHERE user_uid = "
                 f"'{buyer['uid']}'")
    check("чек сохранён целиком", stored == str(JWS_LEN), f"в базе {stored} символов")

    st, again = api("/api/coins/iap-purchase", {
        "productId": "togetherly_plus",
        "purchaseToken": tok,
        "store": "rustore",
    }, buyer["token"])
    check("повторный чек ничего не задваивает",
          st == 200 and again.get("alreadyGranted") is True, f"{st} {again}")

    log("=== 2. подарок партнёру тем же длинным чеком ===")
    st, res = api("/api/waiting/create",
                  {"name": "Партнёр", "returnDate": "2027-05-15 00:00:00.000Z"},
                  buyer["token"])
    pair = (res or {}).get("pairId", "")
    code = (res or {}).get("code", "")
    if not pair:
        log(f"!! пара не создалась: {st} {res}")
        sys.exit(1)
    api("/api/waiting/claim", {"code": code}, partner["token"])
    api("/api/waiting/approve", {"groupId": pair, "approve": True}, buyer["token"])

    st, gift = api("/api/coins/iap-purchase", {
        "productId": "togetherly_plus_gift",
        "purchaseToken": jws("gift"),
        "groupId": pair,
        "store": "rustore",
    }, buyer["token"])
    check("подарок принят, а не 500",
          st == 200 and gift.get("ok") is True and gift.get("gift") is True,
          f"{st} {gift}")
    row2 = sql(f"SELECT plus || '|' || plus_platform FROM users WHERE id = '{partner['uid']}'")
    check("Плюс открылся получателю", row2.startswith("1|"), row2)
    check("источник помечен подарком", row2.endswith("|gift"), row2)

    log("=== 3. монеты тем же длинным чеком ===")
    st, coins = api("/api/coins/iap-purchase", {
        "productId": "coins_50",
        "purchaseToken": jws("coins"),
        "store": "rustore",
    }, partner["token"])
    check("пачка монет принята, а не 500",
          st == 200 and coins.get("ok") is True and coins.get("awarded") == 50,
          f"{st} {coins}")

    log("=== уборка ===")
    sql("DELETE FROM iap_purchases WHERE token LIKE 'probe-jws-%'")
    api(f"/api/collections/groups/records/{pair}", None, buyer["token"], method="DELETE")
    for who in (buyer, partner):
        api(f"/api/collections/users/records/{who['uid']}", None,
            who["token"], method="DELETE")
    left = sql("SELECT count(*) FROM users WHERE email LIKE 'jws-probe-%'")
    check("пробные аккаунты убраны", left == "0", f"осталось {left}")

    log(f"=== итог: {len(OK)} сошлось, {len(FAIL)} нет ===")
    for f in FAIL:
        log(f"  ✗ {f}")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
