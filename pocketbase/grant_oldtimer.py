# -*- coding: utf-8 -*-
"""Значок «Старожил» всем, кто был в Togetherly до званий за часы (план
2026-11-05-ranks-by-hours, задача 1, шаг выдачи). Запускать в день выхода
версии со званиями.

Что делает:
  * `users.granted_badges` += "Old-timer" у аккаунтов с `created` раньше даты;
  * `users.badge` = "Old-timer", если у имени значка нет;
  * включает `catalog_items.badge_old_timer` (`enabled = 1`).

Без `--apply` только считает. Пишет пачками по 2000 строк с ожиданием
занятой базы: PocketBase в это время работает, долгий замок положил бы запись
у всех. Перед `--apply` снять копию:
  sqlite3 /opt/pocketbase/pb_data/data.db "VACUUM INTO '/opt/pb_backups/users_before_oldtimer_<дата>.db'"

Запуск на сервере:
  python3 grant_oldtimer.py --before 2026-11-20T00:00:00Z [--apply]
"""
import argparse
import sqlite3
import time

DB = "/opt/pocketbase/pb_data/data.db"
KEY = "Old-timer"
BATCH = 2000

# granted_badges — json-массив текстом; пустое или кривое считаем пустым.
ARR = "CASE WHEN json_valid(granted_badges) AND json_type(granted_badges) = 'array' THEN granted_badges ELSE '[]' END"
LACKS = f"NOT EXISTS (SELECT 1 FROM json_each({ARR}) WHERE value = ?)"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True, help="дата выхода версии, ISO, как в users.created")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--db", default=DB)
    a = ap.parse_args()
    before = a.before.replace("T", " ")

    db = sqlite3.connect(a.db, timeout=30)
    todo = db.execute(f"SELECT count(*) FROM users WHERE created < ? AND {LACKS}", (before, KEY)).fetchone()[0]
    bare = db.execute("SELECT count(*) FROM users WHERE created < ? AND (badge IS NULL OR badge = '')", (before,)).fetchone()[0]
    print(f"выдать значок: {todo}, поставить у имени: {bare}")
    if not a.apply:
        print("сухой прогон: ничего не записано, для записи — --apply")
        return

    done = 0
    while True:
        ids = [r[0] for r in db.execute(
            f"SELECT id FROM users WHERE created < ? AND {LACKS} LIMIT {BATCH}", (before, KEY))]
        if not ids:
            break
        marks = ",".join("?" * len(ids))
        with db:
            db.execute(f"UPDATE users SET granted_badges = json_insert({ARR}, '$[#]', ?) WHERE id IN ({marks})", (KEY, *ids))
            db.execute(f"UPDATE users SET badge = ? WHERE id IN ({marks}) AND (badge IS NULL OR badge = '')", (KEY, *ids))
        done += len(ids)
        print(f"  {done}/{todo}")
        time.sleep(0.2)
    with db:
        db.execute("UPDATE catalog_items SET enabled = 1 WHERE id = 'badge_old_timer'")
    print(f"готово: {done}, значок в каталоге включён")


if __name__ == "__main__":
    main()
