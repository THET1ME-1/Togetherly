# -*- coding: utf-8 -*-
"""Заводит в `users` поле `notif_v` (уведомления «А», 28.11.2026).

`notif_v` — версия уведомлений, которые сборка рисует сама. С `1` сервер
шлёт на Android пуш только данными, с обложкой (`push_cover.py`), и
приложение рисует его своим `NotifCover`. У выпущенных раньше сборок поля
нет (ноль): им уходит прежний пуш с `notification`, иначе пуш данными они
не показали бы вовсе. Ставит его только сборка, где есть отрисовка, — в той
же сборке, не раньше.

Читают: hotpath (`_push_candidates`, колонка проверяется раз в минуту, без
неё пуши идут по-старому), `apns_push.js` (`getInt("notif_v")`), кроны
`evening_reminder_push.py` и `chest_morning_push.py`.

Коллекция `users` системная и в `collections_schema.json` не выгружается,
поэтому правим только сервер (объявлено и в `USERS_CUSTOM` apply_schema.py).
Идемпотентно.

Запуск: PB_EMAIL=.. PB_PW=.. python3 pocketbase/apply_notif_v_field.py
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
    {"name": "notif_v", "type": "number", "onlyInt": True},
    # Токен FCM, за который ручается сборка с отрисовкой: метка стоит на
    # человеке, а токен у него один, и старая сборка на втором телефоне
    # переписывает `fcm_token`. Данными шлём, только когда они совпали
    # (`push_cover.android_draws_itself`).
    {"name": "notif_v_token", "type": "text", "max": 512},
]


def api(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PB_URL + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", "togetherly-schema/1.0")
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
