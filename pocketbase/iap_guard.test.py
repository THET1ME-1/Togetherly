#!/usr/bin/env python3
"""Живой регресс: монеты и Togetherly+ не выдаются без настоящего чека.

Две дыры, найденные 10.11.2026:

1. Пометка `store=rustore` пропускала сверку чека целиком. Её писали под кассу
   RuStore, которая так и не заработала: приложение из RuStore платит через
   lava и чек сюда не шлёт никогда. Запрос, собранный руками, с выдуманным
   токеном получал Плюс и монеты.
2. Запись в `iap_purchases` человек мог стереть сам (правило коллекции пускало
   хозяина). От повторной выдачи защищает только эта запись: стёр её, прислал
   тот же настоящий чек — монеты начислились заново.

Теперь сверку пропускает только прогон с ключом сервера (заголовок
`X-Iap-Test-Key`, файл `pb_data/.iap_test_key`), а пишет в `iap_purchases`
только сервер.

Гонять НА VPS (читает базу PocketBase напрямую), за собой убирает:
    python3 /opt/pocketbase/iap_guard.test.py
"""
import hashlib
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
KEY_FILE = os.environ.get("IAP_TEST_KEY_FILE", "/opt/pocketbase/pb_data/.iap_test_key")
T0 = time.time()
OK, FAIL = [], []


def log(*a):
    print(f"[{time.time() - T0:6.2f}s]", *a, flush=True)


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    log(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""))


def test_key():
    try:
        return open(KEY_FILE, encoding="utf-8").read().strip()
    except OSError:
        return ""


def api(path, data=None, token=None, method=None, key=""):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body,
                                 method=method or ("POST" if body else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    if key:
        req.add_header("X-Iap-Test-Key", key)
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
    out = subprocess.run(["sqlite3", "-cmd", ".timeout 8000", DB, query],
                         capture_output=True, text=True)
    return out.stdout.strip()


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"iapguard-probe-{tag}-{rnd(6)}@example.com"
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


def account(uid):
    """Монеты и Плюс человека строкой `монеты|плюс`."""
    return sql(f"SELECT coins || '|' || plus FROM users WHERE id = '{uid}'")


def cleanup():
    sql("DELETE FROM iap_purchases WHERE token LIKE 'probe-guard-%'")
    sql("DELETE FROM users WHERE email LIKE 'iapguard-probe-%'")


def main():
    key = test_key()
    who = signup("pok")
    other = signup("chu")
    log(f"покупатель={who['uid']} чужой={other['uid']}")
    before = account(who["uid"])

    try:
        log("=== 1. выдуманный чек с пометкой rustore не проходит ===")
        for product in ("coins_300", "togetherly_plus"):
            fake = "probe-guard-" + rnd(24)
            st, res = api("/api/coins/iap-purchase", {
                "productId": product, "purchaseToken": fake, "store": "rustore",
            }, who["token"])
            check(f"{product}: отказ без ключа сервера",
                  st == 403 and res.get("error") == "purchase_not_verified",
                  f"{st} {res}")
            rows = sql(f"SELECT count(*) FROM iap_purchases WHERE token = '{fake}'")
            check(f"{product}: записи о покупке нет", rows == "0", rows)
        check("ни монет, ни Плюса не прибавилось", account(who["uid"]) == before,
              f"было {before}, стало {account(who['uid'])}")

        st, res = api("/api/coins/iap-purchase", {
            "productId": "coins_300", "purchaseToken": "probe-guard-" + rnd(24),
            "store": "rustore",
        }, who["token"], key="wrong-key")
        check("чужой ключ тоже не пускает", st == 403, f"{st} {res}")

        # Обычный путь магазинов жив: выдуманный чек доходит до сверки, и
        # отказывает именно она (а не «служба не ответила, начисляю так»).
        for shop in ("play", "appstore"):
            st, res = api("/api/coins/iap-purchase", {
                "productId": "togetherly_plus",
                "purchaseToken": "probe-guard-" + rnd(24), "store": shop,
            }, who["token"])
            check(f"{shop}: выдуманный чек отвергает сверка магазина",
                  st == 403 and res.get("error") == "purchase_not_verified",
                  f"{st} {res}")
        check("после всех отказов счёт прежний", account(who["uid"]) == before,
              account(who["uid"]))

        log("=== 2. проверочный прогон с ключом сервера работает ===")
        check("ключ сервера на месте", key != "", KEY_FILE)
        real = "probe-guard-" + rnd(24)
        st, res = api("/api/coins/iap-purchase", {
            "productId": "coins_50", "purchaseToken": real, "store": "rustore",
        }, who["token"], key=key)
        check("с ключом покупка принята",
              st == 200 and res.get("ok") is True and res.get("awarded") == 50,
              f"{st} {res}")
        row_id = hashlib.sha256(real.encode()).hexdigest()
        check("запись о покупке появилась",
              sql(f"SELECT count(*) FROM iap_purchases WHERE id = '{row_id}'") == "1")
        coins_after = account(who["uid"])

        log("=== 3. запись о покупке человек не стирает и не правит ===")
        st, _ = api(f"/api/collections/iap_purchases/records/{row_id}", None,
                    who["token"], method="DELETE")
        check("удаление своей записи отвергнуто", st in (403, 404), f"{st}")
        check("запись осталась",
              sql(f"SELECT count(*) FROM iap_purchases WHERE id = '{row_id}'") == "1")
        st, _ = api(f"/api/collections/iap_purchases/records/{row_id}",
                    {"product_id": "togetherly_plus"}, who["token"], method="PATCH")
        check("правка своей записи отвергнута", st in (403, 404), f"{st}")
        check("товар в записи прежний",
              sql(f"SELECT product_id FROM iap_purchases WHERE id = '{row_id}'") == "coins_50")
        st, made = api("/api/collections/iap_purchases/records", {
            "id": hashlib.sha256(b"probe-guard-made-by-hand").hexdigest(),
            "user_uid": who["uid"], "product_id": "coins_300", "amount": 300,
            "token": "probe-guard-made-by-hand",
        }, who["token"])
        check("свою запись руками не завести", st in (400, 403), f"{st} {made}")

        log("=== 4. тот же чек второй раз ничего не даёт ===")
        st, res = api("/api/coins/iap-purchase", {
            "productId": "coins_50", "purchaseToken": real, "store": "rustore",
        }, who["token"], key=key)
        check("повтор отвечает «уже выдано»",
              st == 200 and res.get("alreadyGranted") is True, f"{st} {res}")
        check("монет не прибавилось", account(who["uid"]) == coins_after,
              f"было {coins_after}, стало {account(who['uid'])}")

        log("=== 5. свои покупки человек по-прежнему видит, чужие нет ===")
        st, mine = api(f"/api/collections/iap_purchases/records/{row_id}", None,
                       who["token"])
        check("свою запись читает", st == 200 and mine.get("id") == row_id, f"{st}")
        st, _ = api(f"/api/collections/iap_purchases/records/{row_id}", None,
                    other["token"])
        check("чужую не читает", st == 404, f"{st}")
    finally:
        log("=== уборка ===")
        cleanup()
        left = sql("SELECT count(*) FROM users WHERE email LIKE 'iapguard-probe-%'")
        check("тестовые аккаунты убраны", left == "0", f"осталось {left}")

    log(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    if FAIL:
        for f in FAIL:
            log("  ✗", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
