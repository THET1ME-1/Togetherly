#!/usr/bin/env python3
"""Снежки темы «Новый год» на проде, тестовой парой (27.11.2026).

    python3 pocketbase/snowball.test.py

Пара и пароль — ~/keys/togetherly-test-pair.txt. Пуш тестовой паре не
приходит (живых токенов у неё нет), проверяется маршрут: бросок, предел
2 с, непросмотренные у партнёра один раз, свои не считаются, чужая пара.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("BASE", "https://togetherly.day")
ok = True


def check(name, cond, detail=""):
    global ok
    print(("✓ " if cond else "✗ ") + name + (f" — {detail}" if detail and not cond else ""))
    ok = ok and bool(cond)


def api(path, data=None, token=None):
    req = urllib.request.Request(BASE + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json", "User-Agent": "togetherly-test",
                                          **({"Authorization": token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def main():
    keys = open(os.path.expanduser("~/keys/togetherly-test-pair.txt"), encoding="utf-8").read()
    (a_mail, pw), (b_mail, _) = re.findall(r"^[AB]: (\S+) / (\S+)", keys, re.M)
    pair = re.search(r"Пара: (\S+)", keys).group(1)
    tok = {}
    for who, mail in (("a", a_mail), ("b", b_mail)):
        st, r = api("/api/collections/users/auth-with-password", {"identity": mail, "password": pw})
        check(f"вход {who}", st == 200, str(r)[:120])
        tok[who] = r.get("token")

    # Остатки прошлых прогонов у B — забрать, чтобы счёт был с нуля.
    api("/api/group/snowball", {"groupId": pair, "pending": True}, tok["b"])
    time.sleep(2.2)

    st, r = api("/api/group/snowball", {"groupId": pair}, tok["a"])
    check("бросок принят", st == 200 and r.get("ok") is True, f"{st} {r}")
    st, r = api("/api/group/snowball", {"groupId": pair}, tok["a"])
    check("второй бросок сразу — 429", st == 429, f"{st} {r}")

    st, r = api("/api/group/snowball", {"groupId": pair, "pending": True}, tok["a"])
    check("свои снежки себе не прилетают", st == 200 and r.get("count") == 0, f"{st} {r}")
    st, r = api("/api/group/snowball", {"groupId": pair, "pending": True}, tok["b"])
    check("партнёру прилетел один", st == 200 and r.get("count") == 1 and r.get("from"), f"{st} {r}")
    st, r = api("/api/group/snowball", {"groupId": pair, "pending": True}, tok["b"])
    check("второй раз уже не прилетает", st == 200 and r.get("count") == 0, f"{st} {r}")

    st, r = api("/api/group/snowball", {"groupId": "r0000000000000"}, tok["a"])
    check("в чужую пару нельзя", st == 403, f"{st} {r}")
    st, r = api("/api/group/snowball", {"groupId": pair})
    check("без входа нельзя", st == 401, f"{st} {r}")

    print("ИТОГ:", "всё хорошо" if ok else "есть ошибки")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
