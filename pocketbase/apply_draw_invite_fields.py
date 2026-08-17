# -*- coding: utf-8 -*-
"""Заводит в `users` два поля для зова «пойдём порисовать».

* `notif_draw` (bool) — выключатель этого вида уведомлений. Читает его общая
  рассылка (`pb_hooks/apns_push.js`, карта NOTIF_FIELD), пишет приложение вместе
  с остальными `notif_*`.
* `draw_invite_ms` (number) — когда человек звал в последний раз. Без отметки
  каждый вход в раскраску превращается в пуш партнёру.

Коллекция `users` системная и в `collections_schema.json` не выгружается,
поэтому правим только сервер — файл схемы трогать нечего. Поля добавляются
поштучно PATCH-ем: полная заливка схемы затирает правки, сделанные руками.

Идемпотентно: поле, которое уже есть, не трогаем.

Запуск: PB_EMAIL=.. PB_PW=.. python3 pocketbase/apply_draw_invite_fields.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "https://togetherly.day").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

WANTED = [
    {"name": "notif_draw", "type": "bool"},
    {"name": "draw_invite_ms", "type": "number"},
    # Комментарии под воспоминанием — свой выключатель. Пока они делили строку
    # с лентой, выключенная лента забирала и разговор под снимком.
    {"name": "notif_comments", "type": "bool"},
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

    users = api("GET", "/api/collections/users", token)
    fields = users.get("fields") or users.get("schema") or []
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

    # Сверяем по факту: PATCH мог пройти, а поле не создаться (тип, конфликт имён).
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
