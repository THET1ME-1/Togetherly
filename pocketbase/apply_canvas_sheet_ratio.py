# -*- coding: utf-8 -*-
"""Заводит в `canvas_catalogue` поле `sheet_ratio`.

Пропорция листа (ширина/высота) задаётся при создании холста и хранилась
ТОЛЬКО на телефоне автора: в каталог на сервер уезжали лишь `pixel_w` и
`pixel_h`. Поэтому у партнёра — и у самого автора после переустановки, когда
каталог приезжает с сервера, — холст открывался без листа и рисовался во всю
свободную область. Точки штрихов лежат в долях 0..1 от холста, так что рисунок
при этом плющит: круг становится овалом (жалоба в Google Play 06.09.2026,
«когда делаю рисунок там одно соотношение сторон, а когда открываешь другое»).

Поле числовое и необязательное: у старых холстов его нет, и они по-прежнему
рисуются во всю область — их штрихи посчитаны в прежней геометрии, и лист им
задавать нельзя, иначе поедут уже нарисованные.

Идемпотентно: поле, которое уже есть, не трогаем.

Запуск: PB_EMAIL=.. PB_PW=.. python3 pocketbase/apply_canvas_sheet_ratio.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

PB_URL = os.environ.get("PB_URL", "https://togetherly.day").rstrip("/")
PB_EMAIL = os.environ.get("PB_EMAIL", "")
PB_PW = os.environ.get("PB_PW", "")

COLLECTION = "canvas_catalogue"
WANTED = [
    {"name": "sheet_ratio", "type": "number"},
]


def api(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(PB_URL + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        print(f"  ✗ {method} {path} → {e.code}: {e.read().decode()[:400]}")
        raise


def main():
    if not PB_EMAIL or not PB_PW:
        print("Нужны PB_EMAIL и PB_PW суперюзера")
        return 1

    token = api(
        "POST",
        "/api/collections/_superusers/auth-with-password",
        body={"identity": PB_EMAIL, "password": PB_PW},
    )["token"]

    col = api("GET", f"/api/collections/{COLLECTION}", token)
    поля = col.get("fields") or col.get("schema") or []
    есть = {f["name"] for f in поля}

    новые = [f for f in WANTED if f["name"] not in есть]
    if not новые:
        print(f"  {COLLECTION}: всё на месте, {sorted(есть)}")
        return 0

    for f in новые:
        поля.append(f)
        print(f"  + {f['name']} ({f['type']})")

    api("PATCH", f"/api/collections/{col['id']}", token, {"fields": поля})

    свежая = api("GET", f"/api/collections/{COLLECTION}", token)
    имена = {f["name"] for f in (свежая.get("fields") or свежая.get("schema") or [])}
    пропало = [f["name"] for f in WANTED if f["name"] not in имена]
    if пропало:
        print(f"  ✗ поле не появилось: {пропало}")
        return 1
    print(f"  {COLLECTION}: теперь {sorted(имена)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
