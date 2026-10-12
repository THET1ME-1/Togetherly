# -*- coding: utf-8 -*-
"""Заводит в `app_config` поле `room_native_ios` — долю людей на iPhone
(проценты 0…100), которым комната совместного просмотра открывается нативным
окном браузера, а не встроенным в экран приложения.

Встроенный браузер на iPhone терял касания у каждого четвёртого (замер
06–11.10.2026), и три правки этого механизма долю не сдвинули. Нативное окно
убирает Flutter с пути пальца. Доля нужна, чтобы сравнить два окна на живых
людях (страница получает метку `nb=1`, замер касаний делится по ней) и
выключить новое без релиза.

Новое числовое поле у записи равно нулю — то есть «никому», прежнее окно.
Правило в приложении — `roomOpensNatively` (lib/models/room_window.dart).
Идемпотентно. Запускать с самого сервера: снаружи API суперюзера закрыт.

Запуск: PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. \
        python3 pocketbase/apply_room_native_field.py

Сменить долю (без релиза, действует со следующего захода на главную):
    python3 pocketbase/apply_room_native_field.py --share 20
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

FIELD = {"name": "room_native_ios", "type": "number", "min": 0, "max": 100, "onlyInt": True}


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


def wanted_share(argv):
    """Доля из `--share N`; None — долю не трогаем."""
    if "--share" not in argv:
        return None
    try:
        value = int(argv[argv.index("--share") + 1])
    except (IndexError, ValueError):
        raise SystemExit("после --share нужно целое число 0…100")
    if not 0 <= value <= 100:
        raise SystemExit("доля — от 0 до 100")
    return value


def main(argv):
    share = wanted_share(argv)
    if not PB_EMAIL or not PB_PW:
        print("нужны PB_EMAIL и PB_PW")
        return 2

    auth = api("POST", "/api/collections/_superusers/auth-with-password",
               body={"identity": PB_EMAIL, "password": PB_PW})
    token = auth.get("token", "")
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
        again = api("GET", "/api/collections/app_config", token)
        if not any(f.get("name") == FIELD["name"] for f in (again.get("fields") or [])):
            print("поле НЕ создалось")
            return 1
        print("добавлено:", FIELD["name"])

    rows = api("GET", "/api/collections/app_config/records?perPage=1", token).get("items") or []
    if not rows:
        print("в app_config нет записи — долю ставить некуда")
        return 1
    row = rows[0]
    print("доля сейчас:", row.get(FIELD["name"], 0))
    if share is None:
        return 0
    api("PATCH", f"/api/collections/app_config/records/{row['id']}", token, {FIELD["name"]: share})
    now = api("GET", f"/api/collections/app_config/records/{row['id']}", token).get(FIELD["name"])
    print("доля теперь:", now)
    return 0 if now == share else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
