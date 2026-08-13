#!/usr/bin/env python3
"""Добор users.group_ids для тех, кого пропустил хук членства.

Правила доступа парных коллекций читают членство из `users.group_ids`, и пустой
список означает отказ на запись: «не удалось сохранить» у человека, который
состоит в живой паре. Список ведёт `pb_hooks/groups_membership.pb.js`, но его
событие теряется, когда PocketBase в этот момент перезапускают: в журнале
остаётся `groups_membership create resync failed … sql: database is closed`.
Каждый перезапуск так роняет одну-две свежие пары.

Скрипт добирает отставших: читает два простых списка (тяжёлый SQL по живой базе
вешает PocketBase) и правит только тех, у кого членство есть, а группы в списке
нет. Обычно правит ноль записей.

Крон на VPS: */10 * * * * python3 /opt/pocketbase/sweep_group_ids.py >> /var/log/sweep_group_ids.log 2>&1
"""
import json
import sqlite3
import sys
import time

DB = "/opt/pocketbase/pb_data/data.db"
APPLY = "--dry-run" not in sys.argv


def stamp():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def missing():
    """Пары «человек → группа», которых не хватает в его списке."""
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    cur = con.cursor()
    cur.execute("SELECT id, group_ids FROM users")
    lists = {}
    for uid, raw in cur.fetchall():
        try:
            lists[uid] = json.loads(raw) if raw else []
        except Exception:
            lists[uid] = []
    cur.execute("SELECT id, members FROM `groups`")
    rows = cur.fetchall()
    con.close()

    need = {}
    for gid, members in rows:
        try:
            mem = json.loads(members) if members else []
        except Exception:
            continue
        for uid in mem:
            if uid in lists and gid not in lists[uid]:
                need.setdefault(uid, set(lists[uid])).add(gid)
    return need


def main():
    need = missing()
    if not need:
        return 0
    print("%s отставших: %d" % (stamp(), len(need)))
    if not APPLY:
        for uid, gids in sorted(need.items()):
            print("   %s -> %s" % (uid, sorted(gids)))
        return 0

    con = sqlite3.connect(DB, timeout=45)
    con.execute("PRAGMA busy_timeout = 45000")
    done = 0
    for uid, gids in sorted(need.items()):
        try:
            con.execute("UPDATE users SET group_ids = ? WHERE id = ?",
                        (json.dumps(sorted(gids)), uid))
            con.commit()
            done += 1
            print("   %s: %d групп" % (uid, len(gids)))
        except Exception as e:
            print("   %s: не вышло — %s" % (uid, e))
        time.sleep(0.1)
    con.close()
    print("%s заполнено: %d" % (stamp(), done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
