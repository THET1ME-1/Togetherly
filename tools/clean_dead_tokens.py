#!/usr/bin/env python3
"""Вычистить из профилей токены, которые Apple и Google объявили мёртвыми.

Раньше это делал сам хук: релей отвечал `gone: true`, и `apns_push.js` стирал
токен у пользователя. С 13 августа 2026 релеи отправляют пуши в фоне и отвечают
сразу — ждать чужой сервер внутри пользовательского запроса нельзя, из-за этого
сохранение статуса висело по тридцать секунд. Отвечать про мёртвый токен стало
некому, поэтому релей складывает находки в `.dead_tokens.jsonl`, а разбирает их
этот скрипт.

Крон на VPS: */10 * * * * python3 /opt/pocketbase/clean_dead_tokens.py >> /var/log/clean_dead_tokens.log 2>&1
"""
import json
import os
import sqlite3
import sys
import time

DB = "/opt/pocketbase/pb_data/data.db"
FEED = "/opt/pocketbase/pb_data/.dead_tokens.jsonl"
FIELDS = {"apns": "apns_token", "fcm": "fcm_token"}


def main() -> int:
    if not os.path.exists(FEED) or os.path.getsize(FEED) == 0:
        return 0

    # Забираем накопленное и сразу освобождаем файл: релей продолжает писать в
    # новый, а мы спокойно разбираем свой срез.
    work = FEED + ".work"
    try:
        os.rename(FEED, work)
    except OSError as e:
        print("не смог забрать файл:", e)
        return 1

    dead = {}
    with open(work, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            token = str(rec.get("token") or "")
            kind = str(rec.get("kind") or "apns")
            if token and kind in FIELDS:
                dead[(kind, token)] = rec.get("reason", "")

    if not dead:
        os.remove(work)
        return 0

    con = sqlite3.connect(DB, timeout=45)
    con.execute("PRAGMA busy_timeout = 45000")
    cleaned = 0
    for (kind, token), reason in dead.items():
        field = FIELDS[kind]
        try:
            cur = con.execute(
                "UPDATE users SET %s = '' WHERE %s = ?" % (field, field), (token,))
            con.commit()
            if cur.rowcount:
                cleaned += cur.rowcount
        except Exception as e:
            print("не вышло вычистить %s: %s" % (kind, e))
    con.close()
    os.remove(work)

    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print("%s мёртвых токенов в разборе: %d, вычищено профилей: %d"
          % (stamp, len(dead), cleaned))
    return 0


if __name__ == "__main__":
    sys.exit(main())
