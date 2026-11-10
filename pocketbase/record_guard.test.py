"""Запись принадлежит автору и своей паре; чужих людей не перечислить.

Три дыры, найденные 10.11.2026 на живом сервере:
1. При переезде чата, настроений и «Скучаю» из PocketBase в hotpath потерялась
   проверка автора: участник пары создавал запись от имени партнёра.
2. Правка записи принимала любой `group_id`: свою запись можно было перенести
   в чужую пару, и та видела её у себя.
3. Список «кто в сети» и список аватарок отдавались любому вошедшему целиком.

Живой прогон на боевом сервере: две пробные пары и посторонний, убирает за
собой.

    python3 pocketbase/record_guard.test.py
"""
import json
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://togetherly.day"
passed = failed = 0

# Картинка 1×1, PNG.
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d49444154789c6360606060000000050001a5f645400000000049454e44ae426082")


def api(path, data=None, token=None, method=None, raw=None, ctype="application/json"):
    body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
    req = urllib.request.Request(
        BASE + path, data=body,
        method=method or ("POST" if body is not None else "GET"))
    req.add_header("Content-Type", ctype)
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            text = r.read()
            try:
                return r.status, (json.loads(text) if text else {})
            except ValueError:
                return r.status, {"bytes": len(text)}
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(text)
        except ValueError:
            return e.code, {"raw": text[:200]}
    except Exception as e:  # срок вышел, обрыв: код 0, тест решает сам
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
    email = f"guard-probe-{tag}-{rnd(6)}@example.com"
    pwd = "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd,
        "display_name": f"Probe {tag}", "name": f"Probe {tag}"})
    assert st in (200, 201), (st, r)
    st, a = api("/api/collections/users/auth-with-password",
                {"identity": email, "password": pwd})
    return {"uid": a["record"]["id"], "token": a["token"], "tag": tag}


def pair(first, second):
    st, res = api("/api/waiting/create",
                  {"name": "X", "returnDate": "2027-05-15 00:00:00.000Z"}, first["token"])
    group = res["pairId"]
    api("/api/waiting/claim", {"code": res["code"]}, second["token"])
    api("/api/waiting/approve", {"groupId": group, "approve": True}, first["token"])
    return group


def rows(col, flt, who):
    st, r = api(f"/api/collections/{col}/records?perPage=200&filter=" + urllib.parse.quote(flt),
                None, who["token"])
    return r.get("items", []) if st == 200 else []


def upload_avatar(who):
    edge = "----probe" + rnd(12)
    parts = []
    for name, value in (("uid", who["uid"]), ("kind", "avatar")):
        parts.append(f'--{edge}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{edge}\r\nContent-Disposition: form-data; name="file"; filename="a.png"\r\n'
                 f'Content-Type: image/png\r\n\r\n'.encode() + PNG + b"\r\n")
    parts.append(f"--{edge}--\r\n".encode())
    return api("/api/collections/media/records", token=who["token"], raw=b"".join(parts),
               ctype=f"multipart/form-data; boundary={edge}")


me, partner, other, other2, loner = (signup(t) for t in "abcde")
people = (me, partner, other, other2, loner)
mine = theirs = ""
made = []          # (коллекция, id, чьим ключом убирать)
try:
    mine, theirs = pair(me, partner), pair(other, other2)
    time.sleep(3)
    now = int(time.time() * 1000)

    print("1. запись от чужого имени")
    st, r = api("/api/collections/chat_messages/records", {
        "group_id": mine, "user_uid": partner["uid"], "user_name": "Probe b",
        "text": "проба: от чужого имени", "ts": now}, me["token"])
    if r.get("id"):
        made.append(("chat_messages", r["id"], partner))
    check("сообщение от имени партнёра не принимается", st >= 400, (st, r.get("user_uid")))
    st, own = api("/api/collections/chat_messages/records", {
        "group_id": mine, "user_uid": me["uid"], "user_name": "Probe a",
        "text": "проба: своё", "ts": now}, me["token"])
    own_id = own.get("id", "")
    if own_id:
        made.append(("chat_messages", own_id, me))
    check("своё сообщение создаётся", st == 200 and own.get("user_uid") == me["uid"], (st, own))
    st, r = api("/api/collections/mood_entries/records", {
        "group_id": mine, "user_uid": partner["uid"], "mood_id": "happy", "label": "проба",
        "timestamp": "2026-11-10 12:00:00.000Z"}, me["token"])
    if r.get("id"):
        made.append(("mood_entries", r["id"], me))
    check("настроение от имени партнёра не принимается", st >= 400, (st, r.get("user_uid")))
    st, r = api("/api/collections/mood_entries/records", {
        "group_id": mine, "user_uid": me["uid"], "mood_id": "happy", "label": "проба",
        "timestamp": "2026-11-10 12:00:00.000Z"}, me["token"])
    if r.get("id"):
        made.append(("mood_entries", r["id"], me))
    check("своё настроение создаётся", st == 200, (st, r))
    st, r = api("/api/collections/miss_you/records", {
        "group_id": mine, "user_uid": partner["uid"], "count": 999}, me["token"])
    if r.get("id"):
        made.append(("miss_you", r["id"], me))
    check("«Скучаю» от имени партнёра не принимается", st >= 400, (st, r.get("user_uid")))

    # Кнопка «Скучаю» и отметка дня идут своими маршрутами, номер человека
    # там тоже приходил из запроса.
    st, r = api("/api/group/miss-you",
                {"groupId": mine, "uid": partner["uid"], "count": 1, "weekday": 2}, me["token"])
    time.sleep(0.5)
    taps = {i["user_uid"]: i.get("count") for i in rows("miss_you", f"(group_id='{mine}')", me)}
    for i in rows("miss_you", f"(group_id='{mine}')", me):
        made.append(("miss_you", i["id"], me))
    check("«Скучаю» с номером партнёра засчитано нажавшему",
          taps.get(me["uid"]) == 1 and not taps.get(partner["uid"]), (st, taps))
    today = time.strftime("%Y-%m-%d", time.gmtime())
    api("/api/group/record-activity", {"groupId": mine, "uid": me["uid"], "today": today}, me["token"])
    st, r = api("/api/group/record-activity",
                {"groupId": mine, "uid": partner["uid"], "today": today}, me["token"])
    st2, g = api(f"/api/collections/groups/records/{mine}", None, me["token"])
    check("день за партнёра отметить нельзя: серия пары не растёт в одиночку",
          not g.get("streak_days") and g.get("streak_last_opened_date") != today,
          (st, r, g.get("streak_days"), g.get("streak_last_opened_date")))

    print("2. перенос записи в чужую пару и смена автора")
    st, r = api(f"/api/collections/chat_messages/records/{own_id}",
                {"group_id": theirs}, me["token"], method="PATCH")
    check("перенос сообщения в чужую пару не принимается", st >= 400, (st, r.get("group_id")))
    check("чужая пара запись у себя не видит",
          not any(i["id"] == own_id for i in rows("chat_messages", f"(group_id='{theirs}')", other)))
    check("запись осталась в своей паре",
          any(i["id"] == own_id for i in rows("chat_messages", f"(group_id='{mine}')", me)))
    st, r = api(f"/api/collections/chat_messages/records/{own_id}",
                {"user_uid": partner["uid"]}, me["token"], method="PATCH")
    check("автора сообщения сменить нельзя", st >= 400, (st, r.get("user_uid")))
    st, r = api(f"/api/collections/chat_messages/records/{own_id}", {
        "group_id": mine, "user_uid": me["uid"], "user_name": "Probe a",
        "text": "проба: поправил", "ts": now}, me["token"], method="PATCH")
    check("обычная правка своей записи целиком проходит",
          st == 200 and r.get("text") == "проба: поправил", (st, r))
    st, r = api(f"/api/collections/chat_messages/records/{own_id}",
                {"reactions": {partner["uid"]: "❤"}}, partner["token"], method="PATCH")
    check("партнёр по-прежнему ставит реакцию", st == 200, (st, r))
    st, mem = api("/api/collections/memories/records", {
        "group_id": mine, "author_uid": me["uid"], "author_name": "Probe a", "type": "text",
        "created_at": "2026-11-10 12:00:00.000Z", "data": {"caption": "проба"}}, me["token"])
    mem_id = mem.get("id", "")
    if mem_id:
        made.append(("memories", mem_id, me))
    st, r = api(f"/api/collections/memories/records/{mem_id}",
                {"group_id": theirs}, me["token"], method="PATCH")
    check("перенос воспоминания в чужую пару не принимается", st >= 400, (st, r.get("group_id")))
    st, r = api(f"/api/collections/memories/records/{mem_id}",
                {"author_uid": partner["uid"]}, me["token"], method="PATCH")
    check("автора воспоминания сменить нельзя", st >= 400, (st, r.get("author_uid")))
    st, r = api(f"/api/collections/memories/records/{mem_id}", {
        "group_id": mine, "author_uid": me["uid"], "type": "text",
        "data": {"caption": "проба: поправил"}}, me["token"], method="PATCH")
    check("обычная правка воспоминания целиком проходит", st == 200, (st, r))

    # Правка чужого воспоминания, которого уже нет: выпущенные сборки после
    # 404 идут создавать его заново и на простой отказ повторяют без конца.
    ghost = "r" + rnd(14)
    st, r = api("/api/collections/memories/records", {
        "id": ghost, "group_id": mine, "author_uid": partner["uid"], "type": "text",
        "created_at": "2026-11-10 12:00:00.000Z", "data": {"caption": "призрак"}}, me["token"])
    check("удалённое чужое воспоминание: ответ «уже есть», очередь телефона успокоится",
          st == 400 and "Value must be unique" in json.dumps(r), (st, r))
    st, r = api(f"/api/collections/memories/records/{ghost}", None, me["token"])
    if st == 200:
        made.append(("memories", ghost, me))
    check("само воспоминание при этом не создаётся", st == 404, st)

    print("3. кто в сети")
    for who in (me, partner, other, loner):
        st, r = api("/api/collections/user_presence/records",
                    {"user_uid": who["uid"], "seen_at": now}, who["token"])
        if r.get("id"):
            made.append(("user_presence", r["id"], who))
    check("партнёра в сети видно",
          len(rows("user_presence", f"(user_uid='{partner['uid']}')", me)) == 1)
    check("себя в сети видно",
          len(rows("user_presence", f"(user_uid='{me['uid']}')", me)) == 1)
    check("постороннего в сети не видно",
          rows("user_presence", f"(user_uid='{other['uid']}')", me) == [])
    st, r = api("/api/collections/user_presence/records?perPage=1", None, me["token"])
    check("список «кто в сети» — только свои", r.get("totalItems", 10 ** 9) <= 2, r.get("totalItems"))
    st, r = api("/api/collections/user_presence/records?perPage=1", None, loner["token"])
    check("человеку без пары виден только он сам", r.get("totalItems", 10 ** 9) <= 1, r.get("totalItems"))

    print("3а. пара без согласия второго")
    # Запись пары создаётся серверными маршрутами (приём кода, ожидание).
    # Прямое создание пускало любой состав, лишь бы автор был внутри: человек
    # вписывал в «пару» постороннего и получал его «в сети» и личный канал.
    forced = "r" + rnd(14)
    st, r = api("/api/collections/groups/records", {
        "id": forced, "members": [me["uid"], loner["uid"]], "max_members": 2,
        "relationship_type": "couple"}, me["token"])
    if st == 200:
        api(f"/api/collections/groups/records/{forced}", None, me["token"], method="DELETE")
    check("пару с посторонним напрямую не создать", st >= 400, (st, r.get("members")))
    check("посторонний в сети по-прежнему не виден",
          rows("user_presence", f"(user_uid='{loner['uid']}')", me) == [])

    print("4. аватарки")
    st, av = upload_avatar(other)
    av_id, av_file = av.get("id", ""), av.get("file", "")
    if av_id:
        made.append(("media", av_id, other))
    check("аватарка загружается", st == 200 and av_file, (st, av))
    flt = urllib.parse.quote("(kind='avatar' || kind='avatars')")
    st, r = api(f"/api/collections/media/records?perPage=1&filter={flt}", None, me["token"])
    check("чужие аватарки списком не отдаются", r.get("totalItems", 10 ** 9) == 0, r.get("totalItems"))
    st, r = api(f"/api/collections/media/records?perPage=1&filter={flt}", None, other["token"])
    check("свою аватарку в списке видно", r.get("totalItems") == 1, r.get("totalItems"))
    st, tok = api("/api/files/token", {}, me["token"])
    st, r = api(f"/api/files/media/{av_id}/{av_file}?token={tok.get('token', '')}")
    if st in (0, 500, 502, 503, 504):
        # Файл лежит в хранилище, а оно временами не отвечает по минуте: к
        # правилам доступа это отношения не имеет, проверку не засчитываем.
        print("  ---  картинка по прямой ссылке: хранилище не ответило, не проверено |", st)
    else:
        check("картинка аватарки по прямой ссылке открывается", st == 200, (st, r))
finally:
    for col, rid, who in reversed(made):
        api(f"/api/collections/{col}/records/{rid}", None, who["token"], method="DELETE")
    for group, who in ((mine, me), (theirs, other)):
        if group:
            api(f"/api/collections/groups/records/{group}", None, who["token"], method="DELETE")
    gone = [api(f"/api/collections/users/records/{w['uid']}", None, w["token"], method="DELETE")[0]
            for w in people]
    print("уборка:", gone, "| пробные:", [w["uid"] for w in people], mine, theirs)

print(f"\nпрошло {passed}, мимо {failed}")
sys.exit(1 if failed else 0)
