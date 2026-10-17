# -*- coding: utf-8 -*-
"""Заводит в `gifts` поля звука к «Песне»: `sound` и `sound_meta`.

`sound` — ссылка `pb://media/<id>/<файл>` на кусок песни или голос в
хранилище пары, `sound_meta` — json с длительностью, волной, видом и тегами.
Проверяет их `gifts.pb.js` при отправке. Без полей PocketBase молча выбросит
значения, и звук не дойдёт до партнёра. Идемпотентно.

Запуск с самого сервера (API суперюзера снаружи закрыт):
PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. python3 apply_gift_sound_fields.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

COLLECTION = "gifts"
WANTED = [
    {"name": "sound", "type": "text", "max": 300},
    {"name": "sound_meta", "type": "text", "max": 600},
]


def api(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PB_URL + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
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

    col = api("GET", f"/api/collections/{COLLECTION}", token)
    fields = col.get("fields") or []
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

    api("PATCH", f"/api/collections/{col['id']}", token, {"fields": fields})
    print("добавлено:", ", ".join(added))

    # Сверяем по факту: PATCH мог пройти, а поле не создаться
    again = api("GET", f"/api/collections/{COLLECTION}", token)
    now_have = {f.get("name") for f in (again.get("fields") or [])}
    missing = [n for n in added if n not in now_have]
    if missing:
        print("НЕ создались:", ", ".join(missing))
        return 1
    print("проверено: поля на месте")
    return 0


if __name__ == "__main__":
    sys.exit(main())
