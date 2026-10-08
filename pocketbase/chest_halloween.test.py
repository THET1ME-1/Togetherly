#!/usr/bin/env python3
"""Живой регресс сезонных сундуков (chest.pb.js, `chest=<ключ>`).

Проверяем то, что ломается молча: вещи набора «13» не выпадают из обычного
сундука (старые сборки их не покажут), у хэллоуинского свои три открытия и
свой потолок, повтор `openId` возвращает тот же приз, веса вещей набора —
20 / 8 / 3 из тысячи, сумма таблицы — тысяча.

Гонять НА VPS против копии PocketBase (refresh_probe.sh, порт 8191), в
/dev/shm/pb_probe/pb_hooks лежат только chest.pb.js и pair_jar.js:
    PB_BASE=http://127.0.0.1:8191 PB_DB=/dev/shm/pb_probe/pb_data/data.db \\
      PB_SU=<почта> PB_SUPW=<пароль> python3 chest_halloween.test.py
Пару скрипт берёт сам из копии, пароли ставит в КОПИИ, прод не трогает.
Тестовые вещи каталога и открытия за собой убирает.
"""
import json
import os
import random
import string
import subprocess
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8191")
DB = os.environ["PB_DB"]
SU, SUPW = os.environ["PB_SU"], os.environ["PB_SUPW"]
OK, FAIL = [], []
# Свой набор и свой сундук, чтобы не задеть настоящие: сезонный сундук целиком
# живёт записью вида `chest`, второй — с прошедшими датами (сезон кончился).
TEST_ITEMS = [
    ("frame_hwtestc", "frame", {"key": "hwtestc", "rarity": "common", "set": "t13"}),
    ("badge_hwtestr", "badge", {"key": "HwTestR", "rarity": "rare", "chest": True, "set": "t13"}),
    ("gift_hwtestl", "gift", {"key": "hwtestl", "rarity": "legendary", "set": "t13"}),
    ("chest_hwtest", "chest", {"key": "hwtest", "set": "t13", "from": "2026-01-01", "until": "2099-01-01",
                               "perDay": 3, "each": {"common": 20, "rare": 8, "legendary": 3}}),
    ("chest_hwgone", "chest", {"key": "hwgone", "set": "t13", "from": "2020-01-01", "until": "2020-02-01"}),
]
CHEST = "hwtest"


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    print(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""), flush=True)


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body, method=method or ("POST" if body else "GET"))
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


def sql(q):
    return subprocess.run(["sqlite3", DB, q], capture_output=True, text=True).stdout.strip()


def oid():
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=15))


def main():
    st, su = api("/api/collections/_superusers/auth-with-password", {"identity": SU, "password": SUPW})
    stok = su.get("token")
    check("вход суперюзера в копию", bool(stok), str(st))
    # Живая пара из копии: двое участников, не распущена.
    row = sql("SELECT id, members FROM groups WHERE disbanded = 0 AND json_array_length(members) = 2 "
              "ORDER BY updated DESC LIMIT 1")
    group, members = row.split("|", 1)
    members = json.loads(members)
    me_uid = members[0]
    pw = "Probe" + "".join(random.choices(string.ascii_letters, k=12)) + "1!"
    api(f"/api/collections/users/records/{me_uid}", {"password": pw, "passwordConfirm": pw}, stok, "PATCH")
    email = sql(f"SELECT email FROM users WHERE id='{me_uid}'")
    st, a = api("/api/collections/users/auth-with-password", {"identity": email, "password": pw})
    me = a.get("token")
    check("вход участника пары в копии", bool(me), str(st))
    sql(f"DELETE FROM chest_opens WHERE user_uid='{me_uid}'")
    sql(f"UPDATE users SET owned_features='[]', owned_icons='[]', plus=0 WHERE id='{me_uid}'")

    for item_id, kind, data in TEST_ITEMS:
        api(f"/api/collections/catalog_items/records/{item_id}", token=stok, method="DELETE")
        st, r = api("/api/collections/catalog_items/records", {
            "id": item_id, "kind": kind, "name_ru": item_id, "name_en": item_id, "price": 0,
            "is_free": False, "enabled": True, "sort": 999, "min_app": "", "data": json.dumps(data),
        }, stok)
        check(f"тестовая вещь {item_id} заведена", st == 200, f"{st} {r}")
    ids = {"hwtestc": "frame_hwtestc", "hwtestr": "badge_hwtestr", "hwtestl": "hwtestl"}

    q = f"tz=180&platform=android&frames=1&group={group}"
    st, main_s = api(f"/api/chest/state?{q}", token=me)
    keys = [o["key"] for o in main_s.get("odds", [])]
    check("обычный сундук отвечает", st == 200 and main_s.get("chest") == "main", str(st))
    season_keys = [s.get("key") for s in main_s.get("seasons") or []]
    check("активный сезонный сундук в списке", CHEST in season_keys, str(season_keys))
    check("кончившийся сезонный сундук не в списке", "hwgone" not in season_keys, str(season_keys))
    st, gone = api(f"/api/chest/state?{q}&chest=hwgone", token=me)
    check("кончившийся сезон — season_over", st == 403 and gone.get("error") == "season_over", f"{st} {gone}")
    st, gone = api("/api/chest/open", {"openId": oid(), "groupId": group, "tz": 180, "platform": "android",
                                        "frames": True, "chest": "hwgone"}, me)
    check("открыть кончившийся нельзя", st == 403 and gone.get("error") == "season_over", f"{st} {gone}")
    check("набор «13» НЕ в обычном сундуке", not any(k in keys for k in ids.values()), str([k for k in keys if 'hwtest' in k]))
    check("обычные подарки на месте", "cookieheart" in keys)
    # У обычного сундука сумма 999 и до сезона (5 монет недобирают одну
    # тысячную); проценты делятся на сумму и не врут.
    check("сумма обычной таблицы ~1000", 999 <= sum(o["weight"] for o in main_s["odds"]) <= 1000,
          str(sum(o["weight"] for o in main_s["odds"])))

    st, hw = api(f"/api/chest/state?{q}&chest={CHEST}", token=me)
    odds = {o["key"]: o for o in hw.get("odds", [])}
    check("хэллоуинский сундук отвечает", st == 200 and hw.get("chest") == CHEST and hw.get("left") == 3, f"{st} {hw.get('left')}")
    check("вещи набора в хэллоуинском с весом 20/8/3",
          odds.get("frame_hwtestc", {}).get("weight") == 20 and odds.get("badge_hwtestr", {}).get("weight") == 8
          and odds.get("hwtestl", {}).get("weight") == 3,
          str({k: odds.get(v, {}).get("weight") for k, v in ids.items()}))
    check("обычных подарков в хэллоуинском нет", "cookieheart" not in odds)
    check("монеты в хэллоуинском есть", "coins5" in odds and "coins10" in odds)
    check("сумма хэллоуинской таблицы 1000", sum(o["weight"] for o in hw["odds"]) == 1000,
          str(sum(o["weight"] for o in hw["odds"])))
    check("подарок набора — вид gift", odds.get("hwtestl", {}).get("kind") == "gift")

    first = None
    for i in range(3):
        o = oid()
        st, r = api("/api/chest/open", {"openId": o, "groupId": group, "tz": 180, "platform": "android",
                                         "frames": True, "chest": CHEST}, me)
        check(f"хэллоуинское открытие {i + 1}", st == 200 and r.get("left") == 2 - i, f"{st} {r.get('left')} {r.get('error')}")
        if first is None:
            first = (o, (r.get("prize") or {}).get("key"))
    day = sql(f"SELECT day FROM chest_opens WHERE id='{first[0]}'")
    check("день сезонного открытия с приставкой ключа", day.startswith(CHEST + "|"), day)
    st, r = api("/api/chest/open", {"openId": oid(), "groupId": group, "tz": 180, "platform": "android",
                                     "frames": True, "chest": CHEST}, me)
    check("четвёртое хэллоуинское — chest_limit", st == 429 and r.get("error") == "chest_limit", f"{st} {r}")
    st, r = api("/api/chest/open", {"openId": first[0], "groupId": group, "tz": 180, "platform": "android",
                                     "frames": True, "chest": CHEST}, me)
    check("повтор openId — тот же приз", st == 200 and r.get("repeated") and (r.get("prize") or {}).get("key") == first[1],
          f"{st} {r.get('prize')}")

    st, s = api(f"/api/chest/state?{q}", token=me)
    check("обычный сундук не тронут: 3 открытия", s.get("left") == 3, str(s.get("left")))
    st, r = api("/api/chest/open", {"openId": oid(), "groupId": group, "tz": 180, "platform": "android", "frames": True}, me)
    check("обычное открытие проходит", st == 200 and r.get("left") == 2, f"{st} {r.get('error')}")
    prize = (r.get("prize") or {}).get("key", "")
    check("из обычного не выпал набор", prize not in ids.values(), prize)
    st, s = api(f"/api/chest/state?{q}&chest={CHEST}", token=me)
    check("хэллоуинский остался на нуле", s.get("left") == 0, str(s.get("left")))

    # уборка
    sql(f"DELETE FROM chest_opens WHERE user_uid='{me_uid}'")
    sql(f"DELETE FROM gifts WHERE recipient_uid='{me_uid}' AND sender_uid='chest'")
    for item_id, _, _ in TEST_ITEMS:
        api(f"/api/collections/catalog_items/records/{item_id}", token=stok, method="DELETE")
    print(f"\nитого: {len(OK)} ✓, {len(FAIL)} ✗")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
