#!/usr/bin/env python3
"""Сезонные сундуки: когда показывать, без обновления приложения.

Сундук целиком лежит записью каталога `chest_<ключ>` (файлы и описание
кладёт upload_badges.py из папки bake_season.py). Эта команда меняет только
даты и включённость — приложение увидит изменение при следующем заходе на
экран сундука.

Запускать НА VPS (API суперюзера снаружи закрыт):
    python3 season_chest.py                          список сундуков и даты
    python3 season_chest.py hw --from 2027-10-10 --until 2027-11-01
    python3 season_chest.py hw --off                 спрятать сейчас
    python3 season_chest.py hw --on                  вернуть

Сезонный фон главной (призрак за стеклом, запись `backdrop_<ключ>`) — тем же
путём с `--kind backdrop`:
    python3 season_chest.py --kind backdrop
    python3 season_chest.py hw --kind backdrop --until 2026-11-01
    python3 season_chest.py hw --kind backdrop --off
Фон приложение видит при следующем открытии (каталог приходит при запуске).

Даты — по часам человека, `until` не включая: --until 2026-11-01 значит, что
31 октября сундук ещё есть, 1 ноября его уже нет. Открытия, вещи и всё
выпавшее у людей остаются при любом выключении.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request

sys.path.insert(0, "/opt/pocketbase/tools")
from upload_badges import PB, drop_superuser, multipart, send, superuser_token  # noqa: E402

DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def get(path: str, token: str) -> dict:
    req = urllib.request.Request(PB + path, headers={"Authorization": token})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("key", nargs="?", help="ключ сундука (hw)")
    ap.add_argument("--from", dest="start", help="первый день, ГГГГ-ММ-ДД")
    ap.add_argument("--until", help="день, с которого сундука уже нет, ГГГГ-ММ-ДД")
    ap.add_argument("--on", action="store_true", help="включить")
    ap.add_argument("--off", action="store_true", help="выключить")
    ap.add_argument("--kind", choices=("chest", "backdrop"), default="chest", help="сундук или фон главной")
    args = ap.parse_args()
    for d in (args.start, args.until):
        if d and not DAY.match(d):
            sys.exit(f"дата {d}: нужен вид ГГГГ-ММ-ДД")
    if args.start and args.until and args.start >= args.until:
        sys.exit("--from должен быть раньше --until")

    email, token = superuser_token()
    try:
        if not args.key:
            res = get(f"/api/collections/catalog_items/records?perPage=50&filter=kind%3D'{args.kind}'", token)
            for r in res.get("items", []):
                d = r.get("data") or {}
                extra = f"  набор {d.get('set')}" if args.kind == "chest" else ""
                print(f"{d.get('key'):8} {'вкл ' if r.get('enabled') else 'выкл'}  {d.get('from')} — {d.get('until')}{extra}")
            return
        item = f"/api/collections/catalog_items/records/{args.kind}_{args.key}"
        rec = get(item, token)
        data = rec.get("data") or {}
        if args.start:
            data["from"] = args.start
        if args.until:
            data["until"] = args.until
        fields = {"data": json.dumps(data, ensure_ascii=False)}
        if args.on or args.off:
            fields["enabled"] = "true" if args.on else "false"
        body, ctype = multipart(fields, [])
        send("PATCH", PB + item, token, body, ctype)
        on = args.on or (not args.off and rec.get("enabled"))
        print(f"{args.key}: {'включён' if on else 'выключен'}, {data.get('from')} — {data.get('until')} (не включая)")
    finally:
        drop_superuser(email)


if __name__ == "__main__":
    main()
