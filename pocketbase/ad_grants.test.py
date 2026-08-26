#!/usr/bin/env python3
"""Живой регресс временных наград за рекламу.

Гонять НА VPS: наружу API суперюзера закрыт. За собой убирает — тестовый
аккаунт удаляется в конце.

    PB_EMAIL=... PB_PASSWORD=... python3 ad_grants.test.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8090"
EMAIL = os.environ.get("PB_EMAIL")
PASSWORD = os.environ.get("PB_PASSWORD")
TEST_EMAIL = "adgrant.test@togetherly.local"
TEST_PASS = "AdGrant123456!"

ok = fail = 0


def call(method, path, body=None, token=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else {})


def check(name, cond):
    global ok, fail
    if cond:
        ok += 1
        print("  ok  ", name)
    else:
        fail += 1
        print("  FAIL", name)


if not EMAIL or not PASSWORD:
    print("нужны PB_EMAIL и PB_PASSWORD суперюзера")
    sys.exit(2)

su = call("POST", "/api/collections/_superusers/auth-with-password",
          {"identity": EMAIL, "password": PASSWORD})[1].get("token")
if not su:
    print("не вышло войти суперюзером")
    sys.exit(2)

st, user = call("POST", "/api/collections/users/records", {
    "email": TEST_EMAIL, "password": TEST_PASS, "passwordConfirm": TEST_PASS,
    "name": "adgrant"}, su)
uid = user.get("id")
token = call("POST", "/api/collections/users/auth-with-password",
             {"identity": TEST_EMAIL, "password": TEST_PASS})[1].get("token")

try:
    print("1. Проба витринной темы")
    st, r = call("POST", "/api/coins/ad-grant", {"kind": "theme", "id": "16"}, token)
    check("ответ 200 и ok", st == 200 and r.get("ok") is True)
    check("списаны два просмотра", r.get("viewsToday") == 2)
    check("срок выставлен", r.get("grants", {}).get("theme", {}).get("until", 0) > 0)
    check("осталось шесть просмотров", r.get("viewsLeft") == 6)

    print("2. Повтор упирается в кулдаун четырнадцати дней")
    st, r = call("POST", "/api/coins/ad-grant", {"kind": "theme", "id": "9"}, token)
    check("отказ по кулдауну", r.get("cooldown") is True)
    check("назван срок следующей пробы", r.get("nextAt", 0) > 0)

    print("3. Тема вне витрины не даётся")
    st, r = call("POST", "/api/coins/ad-grant", {"kind": "theme", "id": "0"}, token)
    check("400 на невитринную тему", st == 400)

    print("4. Фон холста: не больше трёх в сутки")
    got = 0
    for _ in range(4):
        st, r = call("POST", "/api/coins/ad-grant",
                     {"kind": "canvas_bg", "id": "rain"}, token)
        if r.get("ok"):
            got += 1
    check("выдано ровно три", got == 3)
    check("четвёртый отбит", r.get("rateLimited") is True)

    print("5. Общий потолок восьми просмотров")
    st, r = call("POST", "/api/coins/ad-grant",
                 {"kind": "widget_photo", "id": "days_widget_photos"}, token)
    check("восьмой просмотр прошёл", r.get("ok") is True and r.get("viewsToday") == 8)
    st, r = call("POST", "/api/coins/ad-grant",
                 {"kind": "widget_photo", "id": "days_widget_photos"}, token)
    check("девятый отбит потолком", r.get("rateLimited") is True)
    st, r = call("POST", "/api/coins/ad-reward", None, token)
    check("монетная награда тоже упёрлась в общий потолок",
          r.get("rateLimited") is True)

    print("6. Мусорные запросы")
    st, r = call("POST", "/api/coins/ad-grant", {"kind": "plus", "id": "1"}, token)
    check("400 на неизвестный вид", st == 400)
    st, r = call("POST", "/api/coins/ad-grant", {"kind": "theme", "id": ""}, token)
    check("400 на пустой id", st == 400)

    print("7. Плюс за рекламу не выдаётся")
    st, prof = call("GET", f"/api/collections/users/records/{uid}", None, su)
    check("флаг plus не тронут", not prof.get("plus"))
    check("владение темами пусто", not (prof.get("owned_themes") or []))
finally:
    if uid:
        call("DELETE", f"/api/collections/users/records/{uid}", None, su)

print(f"\nитого: {ok} ok, {fail} fail")
sys.exit(1 if fail else 0)
