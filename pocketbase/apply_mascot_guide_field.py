# -*- coding: utf-8 -*-
"""Заводит в `app_config` поле `mascot_guide` — кому показывать облачко-гида
(приветствие, регистрация, подсказки на главной).

Значение — json `{"uids": ["<id>", …], "new_since": "<ISO-дата>"}`. Сначала
гид включается одному владельцу: остальные не видят ничего, даже обновившись.
После проверки ставится дата — и гид получают все, кто зарегистрировался с
этого дня. Правило в приложении — `mascotGuideOn` (lib/models/mascot_guide.dart).

Идемпотентно. Запускать с самого сервера: снаружи API суперюзера закрыт.

Запуск: PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. \\
        python3 pocketbase/apply_mascot_guide_field.py [--add-uid ID] [--new-since 2026-11-05]

    --add-uid ID        добавить человека в список
    --remove-uid ID     убрать человека из списка
    --new-since ДАТА    гид всем, кто зарегистрировался с этой даты (UTC)
    --new-since off     снять дату: новым гид не показывается
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

FIELD = {"name": "mascot_guide", "type": "json", "maxSize": 20000}


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


def arg(argv, name):
    if name not in argv:
        return None
    try:
        return argv[argv.index(name) + 1]
    except IndexError:
        raise SystemExit(f"после {name} нужно значение")


def main(argv):
    if not PB_EMAIL or not PB_PW:
        print("нужны PB_EMAIL и PB_PW")
        return 2
    token = api("POST", "/api/collections/_superusers/auth-with-password",
                body={"identity": PB_EMAIL, "password": PB_PW}).get("token", "")
    if not token:
        print("не вышло войти суперюзером")
        return 1

    col = api("GET", "/api/collections/app_config", token)
    fields = col.get("fields") or []
    if any(f.get("name") == FIELD["name"] for f in fields):
        print(f"  = {FIELD['name']} уже есть")
    else:
        fields.append(dict(FIELD))
        api("PATCH", f"/api/collections/{col['id']}", token, {"fields": fields})
        print("добавлено:", FIELD["name"])

    row = (api("GET", "/api/collections/app_config/records?perPage=1", token).get("items") or [None])[0]
    if row is None:
        print("в app_config нет записи")
        return 1
    value = row.get(FIELD["name"]) or {}
    if not isinstance(value, dict):
        value = {}
    uids = list(value.get("uids") or [])
    add, remove, since = arg(argv, "--add-uid"), arg(argv, "--remove-uid"), arg(argv, "--new-since")
    if add and add not in uids:
        uids.append(add)
    if remove:
        uids = [u for u in uids if u != remove]
    value["uids"] = uids
    if since == "off":
        value.pop("new_since", None)
    elif since:
        value["new_since"] = since if "T" in since else since + "T00:00:00Z"
    if add or remove or since:
        api("PATCH", f"/api/collections/app_config/records/{row['id']}", token, {FIELD["name"]: value})
    now = api("GET", f"/api/collections/app_config/records/{row['id']}", token).get(FIELD["name"])
    print("сейчас:", json.dumps(now, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
