#!/usr/bin/env python3
"""Мягкая контрольная точка WAL у базы PocketBase.

WAL растёт, пока идут чтения: у нас их всегда много (живые подписки), и
контрольная точка сама не проходит. За сорок минут после перезапуска файл
раздулся с 23 до 116 МБ, а в прошлые разы доходил до 191. Чем длиннее WAL, тем
дороже каждое чтение — база просматривает лог поверх основного файла.

PASSIVE делает ровно то, что может прямо сейчас, и не ждёт освобождения:
активные читатели не блокируются, писатель не встаёт. Это не «сжать любой
ценой», а «не давать расти без предела» — TRUNCATE под живой нагрузкой всё
равно вернёт busy.

Крон: */10 * * * * python3 /opt/pocketbase/wal_checkpoint.py >> /var/log/wal_checkpoint.log 2>&1
"""
import os
import sqlite3
import sys
import time

DB = "/opt/pocketbase/pb_data/data.db"
AUX = "/opt/pocketbase/pb_data/auxiliary.db"


def size_mb(path):
    try:
        return os.path.getsize(path) / 1048576
    except OSError:
        return 0.0


def checkpoint(db):
    wal = db + "-wal"
    before = size_mb(wal)
    if before < 32:
        return None  # мелкий лог трогать незачем
    con = sqlite3.connect(db, timeout=20)
    con.execute("PRAGMA busy_timeout = 20000")
    try:
        busy, written, moved = con.execute(
            "PRAGMA wal_checkpoint(PASSIVE)").fetchone()
    except Exception as e:
        con.close()
        return "%s: не вышло — %s" % (os.path.basename(db), e)
    con.close()
    after = size_mb(wal)
    return ("%s: WAL %.1f → %.1f МБ (страниц в логе %s, перенесено %s%s)"
            % (os.path.basename(db), before, after, written, moved,
               ", база была занята" if busy else ""))


def main():
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    lines = [x for x in (checkpoint(DB), checkpoint(AUX)) if x]
    if lines:
        print(stamp, "|", "; ".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
