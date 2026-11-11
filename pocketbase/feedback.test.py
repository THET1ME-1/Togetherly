#!/usr/bin/env python3
"""Обращение из приложения доходит до ящика поддержки.

Google Play отклонил 1.42 (11.11.2026): по правилам о безопасности детей
человек должен иметь возможность сообщить о проблеме, не выходя из приложения.
Форма в приложении шлёт `POST /api/feedback`; здесь проверяется серверная
половина целиком, до письма в ящике.

Гонять НА VPS (читает базу PocketBase и ящик поддержки), убирает за собой:
    MBOX=<пароль ящика support@> python3 feedback.test.py
"""
import base64
import json
import os
import random
import sqlite3
import string
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8090"
DB = "/opt/pocketbase/pb_data/data.db"
JMAP = "http://127.0.0.1:8080/jmap/"
USING = ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"]
passed = failed = 0


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body,
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


def jmap(calls=None, path=""):
    auth = base64.b64encode(("support@togetherly.day:" + os.environ["MBOX"]).encode()).decode()
    req = urllib.request.Request(
        JMAP + path, data=json.dumps({"using": USING, "methodCalls": calls}).encode() if calls else None,
        headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


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


email = f"feedback-probe-{rnd(6)}@example.com"
pwd = "Probe" + rnd(10) + "!"
st, r = api("/api/collections/users/records", {
    "email": email, "password": pwd, "passwordConfirm": pwd, "display_name": "Проба", "name": "Проба"})
assert st in (200, 201), (st, r)
st, a = api("/api/collections/users/auth-with-password", {"identity": email, "password": pwd})
uid, token = a["record"]["id"], a["token"]
account = jmap(path="session")["primaryAccounts"]["urn:ietf:params:jmap:mail"]
mark = "проба формы " + rnd(8)
made = []
db = sqlite3.connect(DB, timeout=30)
try:
    print("что сервер не принимает")
    st, r = api("/api/feedback", {"kind": "bug", "text": "Достаточно длинный текст"})
    check("без входа — отказ", st == 401, st)
    st, r = api("/api/feedback", {"kind": "bug", "text": "коротко"}, token)
    check("слишком короткий текст — отказ", st == 400 and r.get("error") == "too_short", (st, r))
    st, r = api("/api/feedback", {"kind": "выдумка", "text": "Достаточно длинный текст"}, token)
    check("незнакомый вид обращения — отказ", st == 400 and r.get("error") == "bad_kind", (st, r))

    print("обращение доходит")
    st, r = api("/api/feedback", {
        "kind": "child_safety", "text": f"Недопустимое фото в чате, {mark}",
        "app": "1.43.0 (270)", "platform": "android", "lang": "ru"}, token)
    fid = r.get("id", "")
    made.append(fid)
    check("обращение принято", st == 200 and r.get("ok") is True and fid, (st, r))
    row = db.execute("select uid, email, kind, text, app, delivered from app_feedback where id = ?", (fid,)).fetchone()
    check("запись в базе с почтой аккаунта", bool(row) and row[0] == uid and row[1] == email and row[2] == "child_safety", row)

    found = []
    for _ in range(20):
        ids = jmap([["Email/query", {"accountId": account, "filter": {"text": mark}, "limit": 5}, "q"]])["methodResponses"][0][1]["ids"]
        if ids:
            found = jmap([["Email/get", {"accountId": account, "ids": ids, "properties": [
                "subject", "from", "replyTo", "keywords", "mailboxIds", "preview"]}, "g"]])["methodResponses"][0][1]["list"]
            break
        time.sleep(1)
    check("письмо лежит в ящике поддержки", len(found) == 1, len(found))
    if found:
        mail = found[0]
        check("тема начинается с метки безопасности детей", mail["subject"].startswith("[БЕЗОПАСНОСТЬ ДЕТЕЙ] [Приложение]"), mail["subject"])
        check("отправителем стоит человек, ответ уйдёт ему",
              mail["from"][0]["email"] == email and mail["replyTo"][0]["email"] == email, (mail["from"], mail.get("replyTo")))
        check("письмо непрочитано и помечено флажком",
              "$seen" not in mail["keywords"] and mail["keywords"].get("$flagged") is True, mail["keywords"])
    row = db.execute("select delivered from app_feedback where id = ?", (fid,)).fetchone()
    check("в записи отмечено, что письмо легло", bool(row) and row[0] == 1, row)

    print("дневной предел")
    codes = []
    for n in range(6):
        st, r = api("/api/feedback", {"kind": "idea", "text": f"Предложение номер {n}, {mark}"}, token)
        codes.append(st)
        if r.get("id"):
            made.append(r["id"])
    check("после пяти обращений за сутки — отказ", codes.count(200) == 4 and codes[-2:] == [429, 429], codes)
finally:
    ids = jmap([["Email/query", {"accountId": account, "filter": {"text": mark}, "limit": 20}, "q"]])["methodResponses"][0][1]["ids"]
    if ids:
        jmap([["Email/set", {"accountId": account, "destroy": ids}, "d"]])
    with db:
        db.execute("delete from app_feedback where uid = ?", (uid,))
    gone = api(f"/api/collections/users/records/{uid}", None, token, method="DELETE")[0]
    print("уборка: писем", len(ids), "| аккаунт", gone)

print(f"\nпрошло {passed}, мимо {failed}")
sys.exit(1 if failed else 0)
