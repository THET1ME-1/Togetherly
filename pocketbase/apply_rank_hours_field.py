# -*- coding: utf-8 -*-
"""Заводит в `app_config` поле `rank_hours` — пороги званий за часы в
приложении (05.11.2026, план 2026-11-05-ranks-by-hours).

Значение — json-массив из 14 чисел, часы от нуля по возрастанию: Искра,
Знакомство, …, Навсегда. Приложение принимает его в каждом чтении конфига
(`parseRankHours` в lib/models/rank.dart); кривой массив или пустое поле —
запасные пороги `kRankHours`. Так пороги правятся без релиза.

Идемпотентно. Запускать с самого сервера: снаружи API суперюзера закрыт.

Запуск: PB_URL=http://127.0.0.1:8090 PB_EMAIL=.. PB_PW=.. \\
        python3 pocketbase/apply_rank_hours_field.py [--set 0,1,3,6,10,15,25,40,60,90,130,180,250,365]
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

FIELD = {"name": "rank_hours", "type": "json", "maxSize": 2000}
STEPS = 14


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


def hours_from(text):
    """Пороги из строки «0,1,3,…»: ровно 14, с нуля, строго по возрастанию."""
    try:
        values = [float(v) if "." in v else int(v) for v in text.split(",")]
    except ValueError:
        raise SystemExit("пороги — числа через запятую")
    if len(values) != STEPS or values[0] != 0 or any(b <= a for a, b in zip(values, values[1:])):
        raise SystemExit(f"нужно {STEPS} порогов с нуля по возрастанию")
    return values


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
    if "--set" in argv:
        try:
            text = argv[argv.index("--set") + 1]
        except IndexError:
            raise SystemExit("после --set нужны пороги")
        api("PATCH", f"/api/collections/app_config/records/{row['id']}", token, {FIELD["name"]: hours_from(text)})
    now = api("GET", f"/api/collections/app_config/records/{row['id']}", token).get(FIELD["name"])
    print("сейчас:", json.dumps(now, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
