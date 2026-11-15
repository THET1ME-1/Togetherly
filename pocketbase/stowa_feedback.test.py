#!/usr/bin/env python3
"""Обращение из Stowa: `POST /api/stowa/feedback` принимает, отбивает и считает пределы.

Stowa без аккаунтов, маршрут открытый (`pb_hooks/stowa_feedback.pb.js`).
Гонять против стенда или сервера:
    BASE=http://127.0.0.1:8797 python3 stowa_feedback.test.py
На проде (`BASE=http://127.0.0.1:8090`) с `--live` шлёт одно настоящее обращение:
оно дойдёт до Gmail владельца, после прогона убрать его оттуда.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("BASE", "http://127.0.0.1:8797").rstrip("/")
LIVE = "--live" in sys.argv
passed = failed = 0


def post(body, ip):
    req = urllib.request.Request(BASE + "/api/stowa/feedback", data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    # на стенде и на сервере без прокси realIP берётся отсюда только при доверенном адресе;
    # иначе все запросы с одного адреса — это и проверяет предел
    req.add_header("X-Forwarded-For", ip)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def check(name, ok, got=None):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}: {got}")


good = {"kind": "bug", "text": "Проверка приёма обращений Stowa, можно удалить.", "app": "0.1.3", "platform": "android", "lang": "ru",
        "device": "Stowa 0.1.3 · стенд · Android 16"}

if LIVE:
    status, body = post({**good, "email": "stgroup.dev@gmail.com"}, "203.0.113.7")
    check("живое обращение принято", status == 200 and body.get("ok"), (status, body))
    sys.exit(1 if failed else 0)

check("чужой вид отбит", post({**good, "kind": "spam"}, "203.0.113.1") == (400, {"ok": False, "error": "bad_kind"}))
check("короткий текст отбит", post({**good, "text": "коротко"}, "203.0.113.1")[0] == 400)
check("кривая почта отбита", post({**good, "email": "не почта"}, "203.0.113.1") == (400, {"ok": False, "error": "bad_email"}))
status, body = post(good, "203.0.113.1")
check("обращение принято и записано", status == 200 and body.get("ok") and body.get("id"), (status, body))
status, body = post({**good, "kind": "idea", "email": "person@example.com"}, "203.0.113.1")
check("с почтой для ответа тоже принято", status == 200 and body.get("ok"), (status, body))
codes = [post(good, "203.0.113.1")[0] for _ in range(5)]
check("шестое за сутки с одного адреса — 429", codes[-1] == 429 and codes.count(200) == 3, codes)
print(f"{passed} из {passed + failed}")
sys.exit(1 if failed else 0)
