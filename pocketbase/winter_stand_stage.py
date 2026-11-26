#!/usr/bin/env python3
"""Зимний стенд сундука снежнеет по неделям декабря (26.11.2026).

Владелец: «фон становится всё снежнее каждый день до Нового года». Карточка
сезонного сундука `chest_winter` — два файла (`card_back`, `card_front`), их
адреса лежат в `data.files`. Мастерская (bake_season_winter.py) запекает
четыре стадии снега: `card_back_1…4`, `card_front_1…4`. Эта команда раз в
сутки ставит в `card_back`/`card_front` адреса стадии по дате:
1–7 декабря — первая, 8–14 — вторая, 15–21 — третья, с 22-го и в январе —
четвёртая. Приложение возьмёт новую карточку при следующем заходе на экран
сундука, сборка не нужна.

Запускать НА VPS (API суперюзера снаружи закрыт), крон раз в сутки:
    5 0 * * * python3 /opt/pocketbase/tools/winter_stand_stage.py >> /var/log/winter_stand_stage.log 2>&1
    python3 winter_stand_stage.py --date 2026-12-15   проверить, что поставит
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import urllib.request

sys.path.insert(0, "/opt/pocketbase/tools")
from upload_badges import PB, drop_superuser, multipart, send, superuser_token  # noqa: E402

ITEM = "/api/collections/catalog_items/records/chest_winter"


def stage_for(day: dt.date) -> int:
    """Неделя декабря → стадия снега 1…4; до декабря первая, после — последняя."""
    if day.month == 12:
        return min(4, (day.day - 1) // 7 + 1)
    return 4 if day.month == 1 else 1


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", help="день ГГГГ-ММ-ДД вместо сегодняшнего (по Москве)")
    args = ap.parse_args()
    # день по Москве: крон сервера идёт по его часам, а сервер в Москве
    today = dt.date.fromisoformat(args.date) if args.date else (dt.datetime.utcnow() + dt.timedelta(hours=3)).date()
    stage = stage_for(today)
    email, token = superuser_token()
    try:
        req = urllib.request.Request(PB + ITEM, headers={"Authorization": token})
        with urllib.request.urlopen(req) as r:
            rec = json.load(r)
        data = rec.get("data") or {}
        files = data.get("files") or {}
        want = {name: files.get(f"{name}_{stage}") for name in ("card_back", "card_front")}
        if not all(want.values()):
            sys.exit(f"{today}: нет файлов стадии {stage} в chest_winter")
        if all(files.get(k) == v for k, v in want.items()):
            print(f"{today}: стадия {stage} уже стоит")
            return
        files.update(want)
        data["files"] = files
        body, ctype = multipart({"data": json.dumps(data, ensure_ascii=False)}, [])
        send("PATCH", PB + ITEM, token, body, ctype)
        print(f"{today}: стенд — стадия {stage}")
    finally:
        drop_superuser(email)


if __name__ == "__main__":
    main()
