#!/usr/bin/env python3
"""Ролики за сундук, после которых сундук так и не открылся.

Роут награды за ролик пишет в журнал строку «chest ad» с номером открытия
(`coins.pb.js`), а само открытие ложится в `chest_opens` с тем же номером
как id. Номер есть в журнале, а записи нет — человек досмотрел ролик, а
открытие потерялось по дороге (обращение 211, 29.09.2026).

Запуск на сервере, только чтение:
    python3 /opt/pocketbase/tools/chest_lost_ads.py            # за сутки
    python3 /opt/pocketbase/tools/chest_lost_ads.py --hours 72
    python3 /opt/pocketbase/tools/chest_lost_ads.py --uid <id>

Свежие ролики (моложе --grace минут) не считаются: открытие ещё может
прийти, приложение повторяет его само.
"""
import argparse
import datetime as dt
import json
import sqlite3
from collections import defaultdict

PB_DATA = "/opt/pocketbase/pb_data"


def ro(name):
    return sqlite3.connect(f"file:{PB_DATA}/{name}?mode=ro", uri=True, timeout=30)


def stamp(delta):
    return (dt.datetime.utcnow() - delta).strftime("%Y-%m-%d %H:%M:%S")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=24)
    ap.add_argument("--grace", type=float, default=10, help="минут на повтор открытия")
    ap.add_argument("--uid")
    args = ap.parse_args()

    # Даты в журнале PocketBase пишутся с пробелом, а не через «T».
    since = stamp(dt.timedelta(hours=args.hours))
    until = stamp(dt.timedelta(minutes=args.grace))
    ads = []
    with ro("auxiliary.db") as db:
        for created, data in db.execute(
            "select created, data from _logs where message = 'chest ad' and created >= ? and created <= ?",
            (since, until),
        ):
            try:
                d = json.loads(data or "{}")
            except ValueError:
                continue
            open_id, uid = str(d.get("open_id", "")), str(d.get("uid", ""))
            if open_id and uid and (not args.uid or uid == args.uid):
                ads.append((created, uid, open_id))

    if not ads:
        print("роликов за сундук в журнале нет")
        return

    ids = sorted({a[2] for a in ads})
    opened = set()
    with ro("data.db") as db:
        for i in range(0, len(ids), 500):
            part = ids[i:i + 500]
            marks = ",".join("?" * len(part))
            opened.update(r[0] for r in db.execute(f"select id from chest_opens where id in ({marks})", part))

    lost = defaultdict(list)
    for created, uid, open_id in ads:
        if open_id not in opened:
            lost[uid].append((created, open_id))

    total = sum(len(v) for v in lost.values())
    print(f"роликов за сундук: {len(ads)}, без открытия: {total}, людей: {len(lost)}")
    for uid, rows in sorted(lost.items(), key=lambda kv: -len(kv[1])):
        print(f"  {uid}: {len(rows)} — " + ", ".join(f"{c[11:16]} {o}" for c, o in rows[:6]))


if __name__ == "__main__":
    main()
