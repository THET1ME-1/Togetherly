#!/usr/bin/env python3
"""Включить или спрятать все вещи сезонного набора разом (26.11.2026).

Вещи набора — записи каталога с `data.set = <набор>`: рамки, значки, подарки,
вещи Ту. Выключенные приложение не видит (каталог грузится по
`enabled = true`; вещь Ту приходит и выключенной, но считается снятой и не
продаётся), сундук их не разыгрывает, магазин не продаёт. Так набор лежит
на сервере заранее и появляется у людей в нужный час сам.

Зимний набор `winter` залит 26.11.2026 и спрятан до старта сезона: крон
включает его 30.11.2026 в 13:00 по Москве — это полночь 1 декабря в самом
восточном поясе (UTC+14), с которого человек может открыть зимний сундук.

Запускать НА VPS (API суперюзера снаружи закрыт):
    python3 season_items.py winter            что в наборе и включено ли
    python3 season_items.py winter --off      спрятать
    python3 season_items.py winter --on       показать
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, "/opt/pocketbase/tools")
from upload_badges import PB, drop_superuser, multipart, send, superuser_token  # noqa: E402

KINDS = ("frame", "badge", "gift", "wear")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set", help="набор (winter)")
    ap.add_argument("--on", action="store_true", help="показать")
    ap.add_argument("--off", action="store_true", help="спрятать")
    args = ap.parse_args()
    email, token = superuser_token()
    try:
        flt = urllib.parse.quote(f"data.set = '{args.set}' && (" + " || ".join(f"kind = '{k}'" for k in KINDS) + ")")
        req = urllib.request.Request(f"{PB}/api/collections/catalog_items/records?perPage=500&filter={flt}", headers={"Authorization": token})
        with urllib.request.urlopen(req) as r:
            items = json.load(r).get("items", [])
        if not args.on and not args.off:
            for it in items:
                print(f"{it['kind']:6} {it['id']:28} {'вкл ' if it.get('enabled') else 'выкл'}  цена {it.get('price', 0)}")
            print(f"всего {len(items)}")
            return
        want = bool(args.on)
        changed = 0
        for it in items:
            if bool(it.get("enabled")) == want:
                continue
            body, ctype = multipart({"enabled": "true" if want else "false"}, [])
            send("PATCH", f"{PB}/api/collections/catalog_items/records/{it['id']}", token, body, ctype)
            changed += 1
        print(f"набор {args.set}: {'показан' if want else 'спрятан'}, изменено {changed} из {len(items)}")
    finally:
        drop_superuser(email)


if __name__ == "__main__":
    main()
