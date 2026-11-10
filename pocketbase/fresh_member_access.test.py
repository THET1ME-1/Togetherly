"""Новый участник пары получает доступ сразу, а не через пять секунд.

hotpath помнит список пар человека пять секунд в каждом рабочем процессе.
Сразу после приёма в пару процессы с прежним списком отвечали новому участнику
пустой историей чата и отказом на его первое сообщение (найдено 10.11.2026:
`waiting_pair.test.py` падал раз из четырёх на «история переписки видна ему
без переноса»). Тест нарочно прогревает память всех процессов до приёма.

Живой прогон на боевом сервере, пробные аккаунты, убирает за собой.

    python3 pocketbase/fresh_member_access.test.py
"""
import json
import random
import string
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://togetherly.day"
ROUNDS = 3
BURST = 24
passed = failed = 0


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        BASE + path, data=body,
        method=method or ("POST" if body is not None else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, {"raw": raw[:200]}
    except Exception as e:  # обрыв сети — пусть будет виден в итогах
        return 0, {"raw": str(e)[:200]}


def check(name, good, got=""):
    global passed, failed
    if good:
        passed += 1
        print("  ок  ", name)
    else:
        failed += 1
        print("  МИМО", name, "|", got)


def rnd(n):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email = f"fresh-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    assert st in (200, 201), (st, r)
    st, a = api("/api/collections/users/auth-with-password",
                {"identity": email, "password": pwd})
    return {"uid": a["record"]["id"], "token": a["token"]}


def burst(calls):
    """Все запросы уходят разом и попадают в разные рабочие процессы."""
    gate = threading.Barrier(len(calls))
    out = [None] * len(calls)

    def one(i):
        gate.wait()
        out[i] = calls[i]()

    threads = [threading.Thread(target=one, args=(i,)) for i in range(len(calls))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return out


people, groups = [], []
try:
    for round_no in range(1, ROUNDS + 1):
        print(f"круг {round_no}")
        her, him = signup("a"), signup("b")
        people += [her, him]
        st, res = api("/api/waiting/create",
                      {"name": "X", "returnDate": "2027-05-15 00:00:00.000Z"}, her["token"])
        group = res["pairId"]
        groups.append((group, her))
        st, msg = api("/api/collections/chat_messages/records", {
            "group_id": group, "user_uid": her["uid"], "user_name": "Она",
            "text": "Жду тебя", "ts": int(time.time() * 1000)}, her["token"])
        her_msg = msg.get("id", "")
        api("/api/waiting/claim", {"code": res["code"]}, him["token"])

        flt = urllib.parse.quote(f"(group_id='{group}')")
        read = lambda: api(f"/api/collections/chat_messages/records?filter={flt}", None, him["token"])
        # Прогрев: каждый процесс запоминает, что пары у него ещё нет.
        burst([read] * BURST)
        burst([read] * BURST)
        api("/api/waiting/approve", {"groupId": group, "approve": True}, her["token"])

        got = burst([read] * BURST)
        empty = sum(1 for st, r in got if not any(i.get("text") == "Жду тебя" for i in r.get("items", [])))
        check(f"история чата видна сразу во всех {BURST} ответах", empty == 0, f"пустых {empty}")

        sent = burst([
            (lambda n=n: api("/api/collections/chat_messages/records", {
                "group_id": group, "user_uid": him["uid"], "user_name": "Он",
                "text": f"Пришёл {n}", "ts": int(time.time() * 1000)}, him["token"]))
            for n in range(8)])
        refused = [st for st, r in sent if st != 200]
        check("его первые сообщения принимаются сразу", not refused, refused)

        liked = burst([
            (lambda: api(f"/api/collections/chat_messages/records/{her_msg}",
                         {"reactions": {him["uid"]: "❤"}}, him["token"], method="PATCH"))
        ] * 8)
        refused = [st for st, r in liked if st != 200]
        check("реакция на её сообщение проходит сразу", not refused, refused)

        tap = burst([
            (lambda: api("/api/group/miss-you", {"groupId": group, "uid": him["uid"], "count": 1}, him["token"]))
        ] * 6)
        refused = [st for st, r in tap if st not in (200, 429)]
        check("«Скучаю» принимается сразу", not refused, refused)
finally:
    time.sleep(1)
    for group, who in groups:
        flt = urllib.parse.quote(f"(group_id='{group}')")
        st, lst = api(f"/api/collections/chat_messages/records?perPage=200&filter={flt}", None, who["token"])
        for it in lst.get("items", []):
            for p in people:
                if api(f"/api/collections/chat_messages/records/{it['id']}", None, p["token"], method="DELETE")[0] == 204:
                    break
        api(f"/api/collections/groups/records/{group}", None, who["token"], method="DELETE")
    gone = [api(f"/api/collections/users/records/{w['uid']}", None, w["token"], method="DELETE")[0] for w in people]
    print("уборка:", gone, "| пары:", [g for g, _ in groups])

print(f"\nпрошло {passed}, мимо {failed}")
sys.exit(1 if failed else 0)
