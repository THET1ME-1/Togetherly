#!/usr/bin/env python3
"""Живой регресс копилки пары (pair_jar.js, coins.pb.js, chest.pb.js).

Каплю кладёт роут награды за ролик, десять капель дают обоим по открытию
сундука без рекламы и вне дневного счёта. Проверяем то, что ломается молча:
пара без groupId (старые сборки), защиту от частых капель, наполнение,
открытие из копилки, дневной предел копилок.

Гонять НА VPS против копии PocketBase с новыми хуками (порт 8191):
    PB_BASE=http://127.0.0.1:8191 PB_DB=/dev/shm/pb_probe/pb_data/data.db \
      PB_GROUP=<живая пара> python3 pair_jar.test.py
Скрипт ставит двум участникам пары пароль В КОПИИ базы, прод не трогает.
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
GROUP = os.environ["PB_GROUP"]
SU, SUPW = os.environ["PB_SU"], os.environ["PB_SUPW"]
OK, FAIL = [], []


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


def main():
    st, su = api("/api/collections/_superusers/auth-with-password", {"identity": SU, "password": SUPW})
    stok = su["token"]
    st, g = api(f"/api/collections/groups/records/{GROUP}", token=stok)
    members = json.loads(sql(f"SELECT members FROM groups WHERE id='{GROUP}'") or "[]")
    check("пара из двоих", len(members) == 2, str(members))
    toks = []
    for uid in members:
        pw = "Probe" + "".join(random.choices(string.ascii_letters, k=12)) + "1!"
        api(f"/api/collections/users/records/{uid}", {"password": pw, "passwordConfirm": pw}, stok, "PATCH")
        email = sql(f"SELECT email FROM users WHERE id='{uid}'")
        st, a = api("/api/collections/users/auth-with-password", {"identity": email, "password": pw})
        toks.append(a.get("token"))
    me, mate = toks
    check("вход обоих в копии", all(toks))
    sql(f"DELETE FROM pair_jars WHERE group_id='{GROUP}'")

    st, s = api(f"/api/chest/state?tz=180&platform=android&frames=1&group={GROUP}", token=me)
    jar = (s or {}).get("jar") or {}
    check("state отдаёт пустую копилку", st == 200 and jar.get("size") == 10 and jar.get("mine") == 0, str(jar))

    st, r = api("/api/coins/ad-reward", {"groupId": GROUP}, me)
    jar = r.get("jar") or {}
    check("ролик кладёт каплю", st == 200 and jar.get("added") and jar.get("mine") == 1, f"{st} {r}")
    check("монеты за ролик на месте", "coins" in r, str(r))
    st, r = api("/api/coins/ad-reward", {"groupId": GROUP}, me)
    check("вторая капля сразу не падает", not (r.get("jar") or {}).get("added"), str(r.get("jar")))

    sql(f"UPDATE pair_jars SET last='{{}}' WHERE group_id='{GROUP}'")
    st, r = api("/api/coins/ad-reward", {}, mate)
    jar = r.get("jar") or {}
    check("старая сборка без groupId кладёт в свою пару", jar.get("added") and jar.get("mine") == 1 and jar.get("partner") == 1, str(jar))

    filled = None
    for i in range(8):
        sql(f"UPDATE pair_jars SET last='{{}}' WHERE group_id='{GROUP}'")
        st, r = api("/api/coins/ad-reward", {"groupId": GROUP}, [me, mate][i % 2])
        filled = r.get("jar") or {}
    check("десятая капля наполняет копилку", filled.get("filled") and filled.get("mine") + filled.get("partner") == 0, str(filled))
    st, s = api(f"/api/chest/state?tz=180&platform=android&frames=1&group={GROUP}", token=me)
    check("обоим по открытию", (s.get("jar") or {}).get("bonus") == 1, str(s.get("jar")))
    left0 = s.get("left")

    oid = "".join(random.choices(string.ascii_lowercase + string.digits, k=15))
    st, op = api("/api/chest/open", {"openId": oid, "groupId": GROUP, "tz": 180, "platform": "android",
                                     "frames": True, "bonus": True}, me)
    check("открытие из копилки", st == 200 and op.get("jarBonus") == 0, f"{st} {op}")
    check("день помечен b и не входит в счёт", sql(f"SELECT day FROM chest_opens WHERE id='{oid}'").startswith("b"))
    st, s = api(f"/api/chest/state?tz=180&platform=android&frames=1&group={GROUP}", token=me)
    check("дневной остаток не тронут", s.get("left") == left0, f"{left0} → {s.get('left')}")
    oid2 = "".join(random.choices(string.ascii_lowercase + string.digits, k=15))
    st, op = api("/api/chest/open", {"openId": oid2, "groupId": GROUP, "tz": 180, "platform": "android",
                                     "frames": True, "bonus": True}, me)
    check("без открытий в копилке — отказ", st == 409 and op.get("error") == "no_bonus", f"{st} {op}")
    st, s = api(f"/api/chest/state?tz=180&platform=android&frames=1&group={GROUP}", token=mate)
    check("у партнёра открытие ждёт", (s.get("jar") or {}).get("bonus") == 1, str(s.get("jar")))

    sql(f"UPDATE pair_jars SET jars_today=2, last='{{}}' WHERE group_id='{GROUP}'")
    st, r = api("/api/coins/ad-reward", {"groupId": GROUP}, me)
    jar = r.get("jar") or {}
    check("после двух копилок за день капли не падают", not jar.get("added") and jar.get("capped"), str(jar))

    st, r = api("/api/coins/ad-reward", {"groupId": "nosuchgroup0000"}, me)
    check("чужая пара — без копилки, монеты идут", st == 200 and "jar" not in r, str(r))

    print(f"ИТОГ: {len(OK)} прошло, {len(FAIL)} упало")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
