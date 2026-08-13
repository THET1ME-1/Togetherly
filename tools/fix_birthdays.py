#!/usr/bin/env python3
"""Перевести дни рождения из моментов времени в календарные даты.

Жалоба пары 14 августа 2026: «перепутались именно дни, месяцы и годы те же.
Было 18.07.2001 и 17.01.2003, стало 17.07.2001 и 18.01.2003». На сервере такие
даты лежат моментами вида `2004-10-25T20:54:00.000Z`, где 20:54 — минута
сохранения, а не время рождения. Момент у самой полуночи в соседнем часовом
поясе оказывается другим днём, и дата гуляет туда-сюда.

Скрипт приводит их к строке `ГГГГ-ММ-ДД`. День берётся по московскому времени
(UTC+3): подавляющее большинство пар живёт в этом поясе, и именно его человек
видел, когда заводил дату. Клиенты старых сборок такую строку читают без
изменений — `DateTime.tryParse('2001-07-18')` даёт ту же дату.

Исходные значения сохраняются рядом, до единой правки:
`/opt/pb_backups/member_birthdays_before_fix.json`.

    python3 fix_birthdays.py           # проба, ничего не пишет
    python3 fix_birthdays.py --apply   # правка
"""
import json
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

DB = "/opt/pocketbase/pb_data/data.db"
BACKUP = "/opt/pb_backups/member_birthdays_before_fix.json"
LOCAL = timezone(timedelta(hours=3))  # пояс, в котором заводили даты


def as_day(value):
    """Календарный день из того, что лежит в базе, или None."""
    if value is None:
        return None
    if isinstance(value, dict):
        sec = value.get("_seconds", value.get("seconds"))
        if not isinstance(sec, (int, float)):
            return None
        return datetime.fromtimestamp(sec, LOCAL).strftime("%Y-%m-%d")
    s = str(value).strip()
    if not s:
        return None
    if len(s) == 10 and s[4] == "-" and s[7] == "-":
        return s  # уже календарная дата
    try:
        iso = s.replace("Z", "+00:00")
        dt = datetime.fromisoformat(iso)
    except ValueError:
        return None
    if dt.tzinfo is None:
        # Локальные часы без зоны: день берём как есть.
        return dt.strftime("%Y-%m-%d")
    return dt.astimezone(LOCAL).strftime("%Y-%m-%d")


def main():
    apply = "--apply" in sys.argv
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    rows = con.execute(
        "SELECT id, member_birthdays FROM `groups` "
        "WHERE member_birthdays IS NOT NULL AND member_birthdays != '' "
        "AND member_birthdays != '{}'"
    ).fetchall()
    con.close()

    changes = {}
    untouched = skipped = 0
    for gid, raw in rows:
        try:
            data = json.loads(raw)
        except Exception:
            skipped += 1
            continue
        if not isinstance(data, dict):
            skipped += 1
            continue
        fixed = {}
        moved = False
        for uid, value in data.items():
            day = as_day(value)
            fixed[uid] = day
            if day != value:
                moved = True
        if moved:
            changes[gid] = {"before": data, "after": fixed}
        else:
            untouched += 1

    print("групп с датами: %d" % len(rows))
    print("  уже в порядке: %d" % untouched)
    print("  к правке: %d" % len(changes))
    print("  не разобрано: %d" % skipped)

    sample = list(changes.items())[:5]
    for gid, pair in sample:
        for uid in pair["before"]:
            print("   %s: %r → %r" % (uid[:10], pair["before"][uid], pair["after"][uid]))

    if not apply:
        print("\n(проба; для записи добавить --apply)")
        return 0
    if not changes:
        print("править нечего")
        return 0

    os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
    with open(BACKUP, "w", encoding="utf-8") as f:
        json.dump({g: v["before"] for g, v in changes.items()}, f, ensure_ascii=False)
    print("\nисходные значения сохранены в %s" % BACKUP)

    con = sqlite3.connect(DB, timeout=45)
    con.execute("PRAGMA busy_timeout = 45000")
    done = 0
    for gid, pair in changes.items():
        try:
            con.execute("UPDATE `groups` SET member_birthdays = ? WHERE id = ?",
                        (json.dumps(pair["after"], ensure_ascii=False), gid))
            con.commit()
            done += 1
        except Exception as e:
            print("  не вышло %s: %s" % (gid, e))
    con.close()
    print("поправлено групп: %d" % done)
    return 0


if __name__ == "__main__":
    sys.exit(main())
