# -*- coding: utf-8 -*-
"""Заводит в `users` поле `lang` — язык приложения человека.

Пуши пишет сервер, а языка, выбранного в приложении, он не знал: уведомления
уходили всем по-русски (отзыв в App Store 19.08.2026: «The notification and
widgets are in Russian though the app I have set to English»). Поле пишет
приложение (`lib/services/lang_tag.dart`), читают hotpath и хуки. Пустое
значение — сборка старше поля, ей пуши по-прежнему по-русски.

Коллекция `users` системная и в `collections_schema.json` не выгружается,
поэтому правим только сервер (объявлено и в `USERS_CUSTOM` apply_schema.py).
Идемпотентно. Суперюзер через домен закрыт — запускать на сервере:

    PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. python3 apply_lang_field.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

WANTED = [
    {"name": "lang", "type": "text", "max": 8},
]


def api(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PB_URL + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"  !! {method} {path} → {e.code} {e.read().decode()[:300]}")
        raise


def main():
    if not PB_EMAIL or not PB_PW:
        print("нужны PB_EMAIL и PB_PW")
        return 2

    auth = api("POST", "/api/collections/_superusers/auth-with-password",
               body={"identity": PB_EMAIL, "password": PB_PW})
    token = auth.get("token", "")
    if not token:
        print("не вышло войти суперюзером")
        return 1

    users = api("GET", "/api/collections/users", token)
    fields = users.get("fields") or []
    have = {f.get("name") for f in fields}

    added = []
    for want in WANTED:
        if want["name"] in have:
            print(f"  = {want['name']} уже есть")
            continue
        fields.append(dict(want))
        added.append(want["name"])

    if not added:
        print("нечего добавлять")
        return 0

    api("PATCH", f"/api/collections/{users['id']}", token, {"fields": fields})
    print("добавлено:", ", ".join(added))

    again = api("GET", "/api/collections/users", token)
    now_have = {f.get("name") for f in (again.get("fields") or [])}
    missing = [n for n in added if n not in now_have]
    if missing:
        print("НЕ создались:", ", ".join(missing))
        return 1
    print("проверено: поля на месте")
    return 0


if __name__ == "__main__":
    sys.exit(main())
