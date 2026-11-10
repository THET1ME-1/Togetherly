#!/usr/bin/env python3
"""Живой регресс: что участник пары не может сделать с записью пары и каналами.

Две находки проверки 10.11.2026:

1. Купленное парой (`groups.owned_features`: паки настроений, маскоты) участник
   мог вписать себе обычной правкой записи пары — страж закрывал состав и поля
   заявки, а это поле нет. Пишет его только сервер (покупка за монеты, чек
   магазина, вебхук lava).
2. Пропуск в личный канал `user:<uid>` выдавался по любой общей группе, включая
   распущенную: роспуск ставит флаг, а состав не чистит. Бывший партнёр видел,
   когда человек в сети, и получал запись его новой пары.

Обычные правки пары (тип отношений вместе с числом мест) должны проходить, как
раньше: их шлёт приложение.

Гоняется по живому серверу, заводит временные аккаунты
(`privacy-probe-*@example.com`) и убирает за собой:
    python3 pocketbase/pair_privacy.test.py
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
    email = f"privacy-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    if st not in (200, 201):
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password",
                   {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"]}


def pass_to(channel, who):
    """Код ответа на просьбу о пропуске в канал."""
    st, _ = api("/api/centrifugo/subscription-token", {"channel": channel}, who["token"])
    return st


def main():
    her = signup("ona")
    him = signup("on")
    log(f"она={her['uid']} он={him['uid']}")
    pair = ""
    try:
        log("=== 0. пара собирается ===")
        st, res = api("/api/waiting/create",
                      {"name": "Он", "returnDate": "2027-05-15 00:00:00.000Z"},
                      her["token"])
        pair = (res or {}).get("pairId", "")
        if not pair:
            log(f"!! пара не создалась: {st} {res}")
            sys.exit(1)
        api("/api/waiting/claim", {"code": res.get("code", "")}, him["token"])
        api("/api/waiting/approve", {"groupId": pair, "approve": True}, her["token"])
        st, g = api(f"/api/collections/groups/records/{pair}", None, him["token"])
        check("пара собрана", st == 200 and him["uid"] in (g.get("members") or []), f"{st}")

        log("=== 1. купленное парой участник себе не вписывает ===")
        st, res = api(f"/api/collections/groups/records/{pair}",
                      {"owned_features": ["mood_pack:moti"]}, her["token"], method="PATCH")
        check("правка owned_features отвергнута", st == 403, f"{st} {res}")
        st, g = api(f"/api/collections/groups/records/{pair}", None, her["token"])
        check("в записи пары купленного не прибавилось",
              "mood_pack:moti" not in (g.get("owned_features") or []),
              str(g.get("owned_features")))

        log("=== 2. обычные правки пары проходят, как раньше ===")
        st, g = api(f"/api/collections/groups/records/{pair}", {
            "relationship_type": "friends", "max_members": 2,
            "custom_relationship_label": "", "custom_relationship_emoji": "",
        }, her["token"], method="PATCH")
        check("тип отношений меняется", st == 200 and g.get("relationship_type") == "friends",
              f"{st}")
        st, g = api(f"/api/collections/groups/records/{pair}",
                    {"current_status": {"text": "проба"}}, him["token"], method="PATCH")
        check("статус пары меняется", st == 200, f"{st}")

        log("=== 3. в живой паре партнёра слышно ===")
        check("пропуск в канал партнёра выдан", pass_to(f"user:{him['uid']}", her) == 200)
        check("пропуск в свой канал выдан", pass_to(f"user:{her['uid']}", her) == 200)
        check("пропуск в канал пары выдан", pass_to(f"pair:{pair}", her) == 200)

        log("=== 4. после роспуска бывшего партнёра не слышно ===")
        st, g = api(f"/api/collections/groups/records/{pair}", {
            "disbanded": True, "disbanded_at": "2026-11-10 10:00:00.000Z",
        }, her["token"], method="PATCH")
        check("пара распущена", st == 200 and g.get("disbanded") is True, f"{st}")
        check("пропуск в канал бывшего партнёра не выдан",
              pass_to(f"user:{him['uid']}", her) == 403)
        check("и ему в её канал тоже", pass_to(f"user:{her['uid']}", him) == 403)
        check("свой канал по-прежнему открыт", pass_to(f"user:{her['uid']}", her) == 200)
        check("канал распущенной пары открыт (по нему приходит роспуск)",
              pass_to(f"pair:{pair}", him) == 200)
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
