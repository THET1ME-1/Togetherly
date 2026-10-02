#!/usr/bin/env python3
"""Утренний пуш «Сундук снова полный».

Сундук открывают 8% активных (02.10.2026: 1379 из 17,3 тысячи), а приносит он
60% рекламного дохода. Пуш зовёт остальных: утром, по часам самого человека.

Запускается кроном раз в час (`5 * * * *`) на сервере PocketBase
(`/opt/pocketbase/tools/chest_morning_push.py`). Каждый запуск берёт тех, у
кого сейчас на часах `--hour` (по умолчанию 10), поэтому каждый пояс получает
пуш один раз в своё утро.

    python3 chest_morning_push.py --dry-run          # сколько ушло бы сейчас
    python3 chest_morning_push.py --dry-run --any-hour
    python3 chest_morning_push.py --uid <id> --any-hour   # проверить на себе

Кому:
  * был в приложении за последние 14 дней (`user_presence` в Postgres);
  * состоит в живой паре: блок сундука на главной есть только в паре;
  * есть токен устройства;
  * не выключил этот пуш (`users.notif_chest_off`; колонка перевёрнута, ноль у
    старых сборок значит «присылать») и не выключил уведомления целиком;
  * сегодня по своим часам сундук ещё не открывал;
  * сегодня этот пуш ещё не получал (`pb_data/.chest_push.db`).

Пояс берётся из последней отметки настроения (`mood_entries.tz`), без неё —
Москва: 93% показов рекламы приходятся на Россию.

Выключатель сундука (`app_config.chest_enabled = 0`) гасит и рассылку.
"""

import argparse
import json
import sqlite3
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

DB = "/opt/pocketbase/pb_data/data.db"
STATE = "/opt/pocketbase/pb_data/.chest_push.db"
APNS = "http://127.0.0.1:8096/push"
FCM = "http://127.0.0.1:8100/push"
DEAD = "/opt/pocketbase/pb_data/.dead_tokens.jsonl"

TITLE = "Сундук снова полный"
BODY = "Откройте и получите награду"

ACTIVE_DAYS = 14
DEFAULT_TZ_MIN = 180
NOTIF_FIELDS = ("notif_miss_you", "notif_new_memory", "notif_mood",
                "notif_chat", "notif_draw", "notif_comments")


def log(*parts):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(stamp, *parts, flush=True)


def tz_minutes(raw):
    """«+05:00» → 300. Кривое значение — None, тогда берётся Москва."""
    raw = (raw or "").strip()
    if len(raw) != 6 or raw[0] not in "+-" or raw[3] != ":":
        return None
    try:
        minutes = int(raw[1:3]) * 60 + int(raw[4:6])
    except ValueError:
        return None
    if minutes > 14 * 60:
        return None
    return minutes if raw[0] == "+" else -minutes


def local_now(utc_now, minutes):
    return utc_now + timedelta(minutes=minutes)


def wants_push(user, opened_today, sent_today):
    """Правило отбора, без сети и базы: его проверяет тест."""
    if not (user.get("fcm_token") or user.get("apns_token")):
        return False
    if user.get("notif_chest_off"):
        return False
    # Метка стоит — значит нули в колонках выбрал человек. Выключил всё разом —
    # не будим и сундуком.
    if user.get("notif_synced_at") and not any(user.get(f) for f in NOTIF_FIELDS):
        return False
    return not opened_today and not sent_today


def psql(query):
    out = subprocess.run(
        ["docker", "exec", "supabase-db", "psql", "-U", "postgres", "-d", "togetherly",
         "-At", "-F", "\t", "-c", "SET statement_timeout = 20000; " + query],
        capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip()[:300])
    return [line.split("\t") for line in out.stdout.splitlines() if line and line != "SET"]


def chest_enabled(con):
    try:
        row = con.execute("SELECT chest_enabled FROM app_config LIMIT 1").fetchone()
    except sqlite3.Error:
        return True
    return row is None or row[0] in (None, "", 1, "1", True)


def candidates(utc_now):
    since_ms = int((utc_now - timedelta(days=ACTIVE_DAYS)).timestamp() * 1000)
    online_ms = int((utc_now - timedelta(minutes=2)).timestamp() * 1000)
    seen = {uid: int(ms) for uid, ms in psql(
        f"SELECT user_uid, seen_at FROM user_presence WHERE seen_at > {since_ms}")}
    paired = {row[0] for row in psql(
        "SELECT DISTINCT jsonb_array_elements_text(members) FROM groups "
        "WHERE NOT disbanded AND jsonb_array_length(members) >= 2")}
    since_day = (utc_now - timedelta(days=30)).strftime("%Y-%m-%d")
    tz = {uid: tz_minutes(raw) for uid, raw in psql(
        "SELECT DISTINCT ON (user_uid) user_uid, tz FROM mood_entries "
        f"WHERE tz <> '' AND updated > '{since_day}' ORDER BY user_uid, updated DESC")}
    out = {}
    for uid, ms in seen.items():
        # Сидит в приложении прямо сейчас — сундук и так у него перед глазами.
        if uid in paired and ms < online_ms:
            out[uid] = tz.get(uid)
    return out


def load_users(con, uids):
    cols = ["id", "fcm_token", "apns_token", "apns_sandbox", "notif_chest_off",
            "notif_synced_at", *NOTIF_FIELDS]
    have = {r[1] for r in con.execute("PRAGMA table_info(users)")}
    picked = [c for c in cols if c in have]
    users = {}
    ids = list(uids)
    for i in range(0, len(ids), 500):
        part = ids[i:i + 500]
        q = (f"SELECT {', '.join(picked)} FROM users "
             f"WHERE id IN ({', '.join('?' * len(part))})")
        for row in con.execute(q, part):
            users[row[0]] = dict(zip(picked, row))
    return users


def opened_on(con, uid_days):
    """Кто уже открывал сундук в свой сегодняшний день."""
    done = set()
    items = list(uid_days.items())
    for i in range(0, len(items), 400):
        part = items[i:i + 400]
        cond = " OR ".join("(user_uid = ? AND day = ?)" for _ in part)
        args = [x for pair in part for x in pair]
        for (uid,) in con.execute(f"SELECT DISTINCT user_uid FROM chest_opens WHERE {cond}", args):
            done.add(uid)
    return done


def state_db():
    st = sqlite3.connect(STATE, timeout=15)
    st.execute("CREATE TABLE IF NOT EXISTS sent (uid TEXT, day TEXT, at TEXT, "
               "PRIMARY KEY (uid, day))")
    return st


def post(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b"{}")


def send(user):
    """`sync: True` — мимо общей очереди релея. Очередь держит 20 тысяч, а
    утро Москвы больше: залей пачку туда, и пуши чата пошли бы в отказ
    QueueFull. Прямой путь ещё и отвечает, дошло ли."""
    data = {"kind": "chest"}
    ok = False
    if user.get("apns_token"):
        try:
            ans = post(APNS, {"token": user["apns_token"], "title": TITLE, "body": BODY,
                              "thread": "chest", "sandbox": bool(user.get("apns_sandbox")),
                              "data": data, "sync": True})
            ok = ok or bool(ans.get("ok"))
            if ans.get("gone"):
                bury("apns", user["apns_token"], ans.get("reason"))
        except Exception:
            pass
    if user.get("fcm_token"):
        try:
            ans = post(FCM, {"token": user["fcm_token"], "title": TITLE, "body": BODY,
                             "tag": "chest", "data": data, "sync": True})
            ok = ok or bool(ans.get("ok"))
            if ans.get("gone"):
                bury("fcm", user["fcm_token"], ans.get("reason"))
        except Exception:
            pass
    return ok


def bury(kind, token, reason):
    """Мёртвый токен — в ленту `clean_dead_tokens.py` (крон раз в 10 минут):
    иначе завтрашняя рассылка снова в него постучит."""
    with open(DEAD, "a") as f:
        f.write(json.dumps({"kind": kind, "token": token, "reason": reason or ""}) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hour", type=int, default=10, help="час по часам человека")
    ap.add_argument("--any-hour", action="store_true", help="не смотреть на час (проверка)")
    ap.add_argument("--uid", default="", help="только этому человеку (проверка)")
    ap.add_argument("--force", action="store_true",
                    help="с --uid: слать, даже если сундук сегодня открыт")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args()

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=15)
    con.execute("PRAGMA busy_timeout = 15000")
    if not chest_enabled(con):
        log("сундук выключен в app_config, рассылки нет")
        return

    utc_now = datetime.now(timezone.utc)
    pool = candidates(utc_now)
    if args.uid:
        pool = {args.uid: pool.get(args.uid)} if args.uid in pool or args.any_hour else {}

    local_day = {}
    for uid, minutes in pool.items():
        now = local_now(utc_now, DEFAULT_TZ_MIN if minutes is None else minutes)
        if args.any_hour or now.hour == args.hour:
            local_day[uid] = now.strftime("%Y-%m-%d")

    users = load_users(con, local_day)
    opened = opened_on(con, {u: d for u, d in local_day.items() if u in users})
    if args.force and args.uid:
        opened = set()
    st = state_db()
    sent = {(u, d) for u, d in st.execute(
        "SELECT uid, day FROM sent WHERE day >= ?",
        ((utc_now - timedelta(days=2)).strftime("%Y-%m-%d"),))}

    todo = [users[u] | {"_day": d} for u, d in local_day.items()
            if u in users and wants_push(users[u], u in opened, (u, d) in sent)]
    log(f"в паре и активны: {len(pool)}, сейчас утро: {len(local_day)}, "
        f"уже открыли: {len(opened)}, к отправке: {len(todo)}")
    if args.dry_run or not todo:
        return

    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(send, todo))
    stamp = utc_now.isoformat()
    st.executemany("INSERT OR IGNORE INTO sent (uid, day, at) VALUES (?, ?, ?)",
                   [(u["id"], u["_day"], stamp) for u, ok in zip(todo, results) if ok])
    st.execute("DELETE FROM sent WHERE day < ?",
               ((utc_now - timedelta(days=7)).strftime("%Y-%m-%d"),))
    st.commit()
    log(f"отправлено {sum(results)} из {len(todo)} за {time.time() - started:.0f} с")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # крон должен оставить причину в журнале
        log("ошибка:", e)
        sys.exit(1)
