#!/usr/bin/env python3
"""Вечернее напоминание: отметить настроение и выполнить задание дня (TOG-113).

Просьба из канала 26.11.2026: «Я хочу напоминалки о приложении :( Вечно
забываю выполнить одно задание или добавить своё настроение за день».

Запускается кроном раз в пять минут на основном сервере
(`/opt/pocketbase/tools/evening_reminder_push.py`). Каждый запуск берёт тех, у
кого на часах сейчас их время напоминания (окно 15 минут: пропущенный запуск
не съедает день), и шлёт пуш, только если что-то из выбранного ещё не сделано.
Сделано всё — молчим.

    python3 evening_reminder_push.py --dry-run           # сколько ушло бы сейчас
    python3 evening_reminder_push.py --dry-run --any-time
    python3 evening_reminder_push.py --uid <id> --any-time   # проверить на себе

Кому и о чём:
  * сборка знает напоминание: в `users.remind_at` есть время (новые сборки
    шлют его всегда, по умолчанию 21:00). У выпущенных раньше выключателя нет,
    а задача требует «может выключить», поэтому им не шлём ничего;
  * был в приложении за 14 дней (`user_presence`), есть токен, не выключил
    уведомления целиком;
  * настроение — если сегодня по его часам не отмечено, выключатель
    `users.remind_mood_off` не стоит и есть привычка: отмечал хотя бы в 4 дня
    из последних 14. Замер 27.11.2026: из 36 тысяч, отмечавших хоть раз за две
    недели, к 21:00 не отметились 27 тысяч, с порогом 4 дня — 9 тысяч;
  * задание дня — если он в живой паре, задание за его сегодня не выполнено,
    `users.remind_task_off` не стоит и пара делала задание за последние 3 дня;
  * сам трогал эти настройки (`users.remind_custom`) — напоминаем без привычки;
  * сегодня по своим часам это напоминание ещё не получал
    (`pb_data/.evening_reminder.db`).

Задания в приложении меняются по UTC (`DailyTaskProgress.dayKey`), а день
человека — по его часам. «Сегодняшним» считается задание с датой не раньше
UTC-даты в его местный полдень: иначе в Сан-Паулу в 21:00 (в UTC уже завтра)
задание было бы «не сделано» всегда.

Пояс: имя из записи виджета (`widget_data.data.tzn`), без него смещение
(`data.zone`), без него — из последней отметки настроения, без неё Москва.
"""

import argparse
import json
import re
import sqlite3
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DB = "/opt/pocketbase/pb_data/data.db"
STATE = "/opt/pocketbase/pb_data/.evening_reminder.db"
APNS = "http://127.0.0.1:8096/push"
FCM = "http://127.0.0.1:8100/push"
DEAD = "/opt/pocketbase/pb_data/.dead_tokens.jsonl"

ACTIVE_DAYS = 14
HABIT_DAYS = 14
HABIT_MOOD_DAYS = 4
HABIT_TASK_DAYS = 3
DEFAULT_AT = "21:00"
WINDOW_MIN = 15
MOSCOW = "Europe/Moscow"
NOTIF_FIELDS = ("notif_miss_you", "notif_new_memory", "notif_mood",
                "notif_chat", "notif_draw", "notif_comments")

# Тексты на языке приложения (`users.lang`), пусто или незнакомо — по-русски.
# У человека без пары настроение видит только он сам, «партнёр увидит» — враньё.
TEXTS = {
    "mood": {
        "ru": ("Как прошёл день?", "Отметь настроение, партнёр его увидит"),
        "en": ("How was your day?", "Log your mood so your partner can see it"),
        "de": ("Wie war dein Tag?", "Trag deine Stimmung ein, dein Partner sieht sie"),
        "fr": ("Comment s’est passée ta journée ?", "Note ton humeur, ton partenaire la verra"),
        "es": ("¿Qué tal tu día?", "Marca tu ánimo, tu pareja lo verá"),
        "it": ("Com’è andata oggi?", "Segna il tuo umore, il partner lo vedrà"),
        "pt": ("Como foi o seu dia?", "Marque seu humor, seu par vai ver"),
        "zh": ("今天过得怎么样？", "记录一下心情，伴侣会看到"),
        "uk": ("Як минув день?", "Познач настрій, партнер його побачить"),
    },
    "mood_solo": {
        "ru": ("Как прошёл день?", "Отметь настроение за сегодня"),
        "en": ("How was your day?", "Log your mood for today"),
        "de": ("Wie war dein Tag?", "Trag deine Stimmung für heute ein"),
        "fr": ("Comment s’est passée ta journée ?", "Note ton humeur du jour"),
        "es": ("¿Qué tal tu día?", "Marca tu ánimo de hoy"),
        "it": ("Com’è andata oggi?", "Segna il tuo umore di oggi"),
        "pt": ("Como foi o seu dia?", "Marque seu humor de hoje"),
        "zh": ("今天过得怎么样？", "记录一下今天的心情"),
        "uk": ("Як минув день?", "Познач настрій за сьогодні"),
    },
    "task": {
        "ru": ("Задание дня ждёт", "Выполните одно задание вместе, это пара минут"),
        "en": ("Today’s task is waiting", "Do one task together, it only takes a couple of minutes"),
        "de": ("Die Aufgabe des Tages wartet", "Erledigt eine Aufgabe zusammen, das dauert nur ein paar Minuten"),
        "fr": ("La mission du jour t’attend", "Faites une mission ensemble, ça prend deux minutes"),
        "es": ("La tarea del día te espera", "Haced una tarea juntos, son un par de minutos"),
        "it": ("La sfida del giorno ti aspetta", "Fate una sfida insieme, bastano un paio di minuti"),
        "pt": ("A tarefa do dia está esperando", "Façam uma tarefa juntos, leva só uns minutinhos"),
        "zh": ("今日任务在等你们", "一起完成一个任务，只要几分钟"),
        "uk": ("Завдання дня чекає", "Виконайте одне завдання разом, це кілька хвилин"),
    },
    "both": {
        "ru": ("Как прошёл день?", "Отметь настроение и загляни в задание дня"),
        "en": ("How was your day?", "Log your mood and check today’s task"),
        "de": ("Wie war dein Tag?", "Trag deine Stimmung ein und schau bei der Aufgabe des Tages vorbei"),
        "fr": ("Comment s’est passée ta journée ?", "Note ton humeur et jette un œil à la mission du jour"),
        "es": ("¿Qué tal tu día?", "Marca tu ánimo y mira la tarea del día"),
        "it": ("Com’è andata oggi?", "Segna il tuo umore e dai un’occhiata alla sfida del giorno"),
        "pt": ("Como foi o seu dia?", "Marque seu humor e veja a tarefa do dia"),
        "zh": ("今天过得怎么样？", "记录心情，再看看今日任务"),
        "uk": ("Як минув день?", "Познач настрій і зазирни в завдання дня"),
    },
}

_OFFSET = re.compile(r"^([+-])(\d{2}):(\d{2})$")
_AT = re.compile(r"^(\d{1,2}):(\d{2})$")


def log(*parts):
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    print(stamp, *parts, flush=True)


def _offset(raw):
    m = _OFFSET.match((raw or "").strip())
    if not m:
        return None
    minutes = int(m.group(2)) * 60 + int(m.group(3))
    if minutes > 14 * 60:
        return None
    return timezone(timedelta(minutes=minutes if m.group(1) == "+" else -minutes))


def zone_of(tzn, zone, mood_tz):
    """Пояс человека: имя, смещение из виджета, смещение из настроения, Москва."""
    name = (tzn or "").strip()
    if name:
        try:
            return ZoneInfo(name)
        except (ZoneInfoNotFoundError, ValueError):
            pass
    return _offset(zone) or _offset(mood_tz) or ZoneInfo(MOSCOW)


def parse_pb_time(text):
    """`2026-11-28 10:13:10.528821Z` → момент в UTC; пусто и мусор — None."""
    text = (text or "").strip().replace("Z", "+00:00")
    if not text:
        return None
    try:
        t = datetime.fromisoformat(text.replace(" ", "T"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def _at_minutes(at):
    m = _AT.match((at or "").strip())
    if m and int(m.group(1)) < 24 and int(m.group(2)) < 60:
        return int(m.group(1)) * 60 + int(m.group(2))
    h, mi = DEFAULT_AT.split(":")
    return int(h) * 60 + int(mi)


def reminder_slot(utc_now, tz, at, force=False):
    """Окно напоминания человека: (день `ГГГГ-ММ-ДД`, начало его суток в UTC,
    UTC-дата заданий этого дня) или None, если сейчас не его время.

    День считается от НАЧАЛА окна: выбрал 23:55 — запуск в 00:05 относится к
    вчерашнему дню, иначе отметка в 22:00 стала бы «вчерашней», а день — новым.
    """
    local = utc_now.astimezone(tz)
    since = 0 if force else (local.hour * 60 + local.minute - _at_minutes(at)) % 1440
    if since >= WINDOW_MIN:
        return None
    start_local = local - timedelta(minutes=since)
    d = start_local.date()
    midnight = datetime(d.year, d.month, d.day, tzinfo=tz).astimezone(timezone.utc)
    noon = datetime(d.year, d.month, d.day, 12, tzinfo=tz).astimezone(timezone.utc)
    return d.isoformat(), midnight, noon.date().isoformat()


def _minus_days(day, n):
    return (datetime.strptime(day, "%Y-%m-%d") - timedelta(days=n)).strftime("%Y-%m-%d")


def what_to_remind(user, *, mood_last, mood_days, tasks, paired, day_start, task_day):
    """О чём напомнить: {'mood', 'task'} или пусто. Без сети и базы — тест."""
    # Время шлют только сборки, где напоминание можно выключить.
    if not (user.get("remind_at") or "").strip():
        return set()
    if not (user.get("fcm_token") or user.get("apns_token")):
        return set()
    # Метка стоит — значит нули в колонках выбрал человек: выключил всё разом.
    if user.get("notif_synced_at") and not any(user.get(f) for f in NOTIF_FIELDS):
        return set()
    custom = bool(user.get("remind_custom"))
    need = set()

    if not user.get("remind_mood_off"):
        marked_today = mood_last is not None and mood_last >= day_start
        if not marked_today and (custom or mood_days >= HABIT_MOOD_DAYS):
            need.add("mood")

    if paired and not user.get("remind_task_off"):
        tasks = tasks if isinstance(tasks, dict) else {}
        day = str(tasks.get("date") or "")
        done = tasks.get("done") if isinstance(tasks.get("done"), list) else []
        done_today = bool(done) and day >= task_day
        habit = bool(done) and day >= _minus_days(task_day, HABIT_TASK_DAYS)
        if not done_today and (custom or habit):
            need.add("task")
    return need


def best_tasks(items):
    """У человека бывает несколько пар: берём ту, где сделано позже всего.
    Сегодня сделано хоть в одной — напоминать не о чем."""
    best, best_key = {}, ("", 0)
    for t in items:
        if not isinstance(t, dict):
            continue
        done = t.get("done") if isinstance(t.get("done"), list) else []
        key = (str(t.get("date") or "") if done else "", len(done))
        if key > best_key or not best:
            best, best_key = t, key
    return best


def texts(need, lang, paired):
    """Заголовок и текст пуша на языке человека."""
    if need >= {"mood", "task"}:
        kind = "both"
    elif "mood" in need:
        kind = "mood" if paired else "mood_solo"
    else:
        kind = "task"
    table = TEXTS[kind]
    return table.get(str(lang or "").strip().lower()[:2]) or table["ru"]


def psql(query):
    out = subprocess.run(
        ["docker", "exec", "-i", "supabase-db", "psql", "-U", "postgres", "-d", "togetherly",
         "-At", "-F", "\t"],
        input="SET statement_timeout = 20000;\n" + query + "\n",
        capture_output=True, text=True, timeout=90)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip()[:300])
    return [line.split("\t") for line in out.stdout.splitlines() if line and line != "SET"]


def _chunks(items, size):
    items = list(items)
    for i in range(0, len(items), size):
        yield items[i:i + size]


def active_uids(utc_now):
    since_ms = int((utc_now - timedelta(days=ACTIVE_DAYS)).timestamp() * 1000)
    return {row[0] for row in psql(
        f"SELECT user_uid FROM user_presence WHERE seen_at > {since_ms}") if row and row[0]}


def zones(utc_now):
    """Пояс из записей виджета и из последних настроений: uid → [tzn, zone, mood_tz]."""
    out = {}
    for row in psql(
            "SELECT DISTINCT ON (user_uid) user_uid, coalesce(data->>'tzn', ''), "
            "coalesce(data->>'zone', '') FROM widget_data "
            "WHERE data ? 'zone' OR data ? 'tzn' ORDER BY user_uid, updated DESC"):
        if len(row) >= 3:
            out[row[0]] = [row[1], row[2], ""]
    since_day = (utc_now - timedelta(days=30)).strftime("%Y-%m-%d")
    for row in psql(
            "SELECT DISTINCT ON (user_uid) user_uid, tz FROM mood_entries "
            f"WHERE tz <> '' AND updated > '{since_day}' ORDER BY user_uid, updated DESC"):
        if len(row) >= 2:
            out.setdefault(row[0], ["", "", ""])[2] = row[1]
    return out


def reminder_times(con):
    """Время напоминания тех, чья сборка его знает: uid → `ЧЧ:ММ`."""
    have = {r[1] for r in con.execute("PRAGMA table_info(users)")}
    if "remind_at" not in have:
        return {}
    return {uid: at for uid, at in con.execute(
        "SELECT id, remind_at FROM users WHERE remind_at IS NOT NULL AND remind_at <> ''")}


def load_users(con, uids):
    cols = ["id", "fcm_token", "apns_token", "apns_sandbox", "notif_synced_at", "lang",
            "remind_mood_off", "remind_task_off", "remind_at", "remind_custom", *NOTIF_FIELDS]
    have = {r[1] for r in con.execute("PRAGMA table_info(users)")}
    picked = [c for c in cols if c in have]
    users = {}
    for part in _chunks(uids, 500):
        q = f"SELECT {', '.join(picked)} FROM users WHERE id IN ({', '.join('?' * len(part))})"
        for row in con.execute(q, part):
            users[row[0]] = dict(zip(picked, row))
    return users


# Оба запроса ниже — один проход таблицы на запуск, а не по пачкам людей.
# Индекса по одному `user_uid` у настроений нет (есть только с группой
# впереди), а GIN `jsonb_path_ops` у `groups.members` не умеет `?|`: замер
# 28.11.2026 — 3,9 с на каждую пачку из 2000 человек, 164 с на всех активных.
# Целиком: настроения за 14 дней — 0,2 с, живые пары — меньше секунды.

def mood_stats(wanted, utc_now):
    """Настроения за 14 дней: uid → (последняя отметка в UTC, сколько разных дней)."""
    since = (utc_now - timedelta(days=HABIT_DAYS)).strftime("%Y-%m-%d %H:%M:%S")
    out = {}
    for row in psql(
            "SELECT user_uid, max(timestamp), count(DISTINCT left(timestamp, 10)) "
            f"FROM mood_entries WHERE timestamp > '{since}' GROUP BY user_uid"):
        if len(row) >= 3 and row[0] in wanted:
            out[row[0]] = (parse_pb_time(row[1]), int(row[2] or 0))
    return out


def pair_tasks(wanted):
    """Живые пары человека и их прогресс заданий: uid → лучший daily_tasks."""
    found = {}
    for row in psql(
            "SELECT members::text, coalesce(daily_tasks::text, '') FROM groups "
            "WHERE NOT coalesce(disbanded, false) AND jsonb_array_length(members) >= 2"):
        if len(row) < 2:
            continue
        try:
            members = json.loads(row[0]) or []
            tasks = json.loads(row[1]) if row[1] else {}
        except ValueError:
            continue
        for m in members:
            if m in wanted:
                found.setdefault(m, []).append(tasks if isinstance(tasks, dict) else {})
    return {uid: best_tasks(items) for uid, items in found.items()}


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


def bury(kind, token, reason):
    """Мёртвый токен — в ленту `clean_dead_tokens.py`, как у сундука."""
    with open(DEAD, "a") as f:
        f.write(json.dumps({"kind": kind, "token": token, "reason": reason or ""}) + "\n")


def send(item):
    """`sync: True` — мимо общей очереди релея, как утренний сундук: вечер
    Москвы большой, и пачка в очереди отодвинула бы пуши чата."""
    user, need = item
    title, body = texts(need, user.get("lang"), user.get("_paired"))
    data = {"kind": "evening"}
    ok = False
    if user.get("apns_token"):
        try:
            ans = post(APNS, {"token": user["apns_token"], "title": title, "body": body,
                              "thread": "evening", "sandbox": bool(user.get("apns_sandbox")),
                              "data": data, "sync": True})
            ok = ok or bool(ans.get("ok"))
            if ans.get("gone"):
                bury("apns", user["apns_token"], ans.get("reason"))
        except Exception:
            pass
    if user.get("fcm_token"):
        try:
            ans = post(FCM, {"token": user["fcm_token"], "title": title, "body": body,
                             "tag": "evening", "data": data, "sync": True})
            ok = ok or bool(ans.get("ok"))
            if ans.get("gone"):
                bury("fcm", user["fcm_token"], ans.get("reason"))
        except Exception:
            pass
    return ok


def send_all(todo, st, utc_now, *, send=send, workers=12, batch=200):
    """Рассылка пачками с отметкой после каждой. Запусков в окне три, и
    рассылка 21:00 по Москве идёт дольше пяти минут (сундук — 12 пушей в
    секунду): отметь всё в конце — упавший или затянувшийся запуск повторил бы
    пачку тем же людям."""
    stamp = utc_now.isoformat()
    total = 0
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for part in _chunks(todo, batch):
            results = list(ex.map(send, part))
            st.executemany("INSERT OR IGNORE INTO sent (uid, day, at) VALUES (?, ?, ?)",
                           [(u["id"], u["_day"], stamp) for (u, _), ok in zip(part, results) if ok])
            st.commit()
            total += sum(results)
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--any-time", action="store_true", help="не смотреть на время (проверка)")
    ap.add_argument("--uid", default="", help="только этому человеку (проверка)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--workers", type=int, default=12)
    args = ap.parse_args()

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=15)
    con.execute("PRAGMA busy_timeout = 15000")
    utc_now = datetime.now(timezone.utc)

    times = reminder_times(con)
    pool = set(times) & active_uids(utc_now)
    if args.uid:
        pool = {args.uid} & set(times)
    tz_rows = zones(utc_now) if pool else {}

    due = {}
    for uid in pool:
        tz = zone_of(*(tz_rows.get(uid) or ["", "", ""]))
        slot = reminder_slot(utc_now, tz, times.get(uid, ""), force=args.any_time)
        if slot:
            due[uid] = slot

    # Получившие сегодня отсеиваются до тяжёлых запросов: второй и третий
    # запуск в окне обычно базу не трогают.
    st = state_db()
    sent = {(u, d) for u, d in st.execute(
        "SELECT uid, day FROM sent WHERE day >= ?", ((utc_now - timedelta(days=2)).strftime("%Y-%m-%d"),))}
    due = {u: v for u, v in due.items() if (u, v[0]) not in sent}
    if not due:
        log(f"знают напоминание: {len(times)}, активны: {len(pool)}, сейчас их время: никого")
        return

    users = load_users(con, due)
    moods = mood_stats(set(users), utc_now)
    tasks = pair_tasks(set(users))

    todo = []
    for uid, (day, start, task_day) in due.items():
        user = users.get(uid)
        if user is None:
            continue
        last, days = moods.get(uid, (None, 0))
        need = what_to_remind(user, mood_last=last, mood_days=days, tasks=tasks.get(uid),
                              paired=uid in tasks, day_start=start, task_day=task_day)
        if need:
            todo.append((user | {"_day": day, "_paired": uid in tasks}, need))
    log(f"знают напоминание: {len(times)}, активны: {len(pool)}, сейчас их время: {len(due)}, "
        f"к отправке: {len(todo)} (настроение {sum('mood' in n for _, n in todo)}, "
        f"задание {sum('task' in n for _, n in todo)})")
    if args.dry_run or not todo:
        return

    started = time.time()
    total = send_all(todo, st, utc_now, workers=args.workers)
    st.execute("DELETE FROM sent WHERE day < ?", ((utc_now - timedelta(days=7)).strftime("%Y-%m-%d"),))
    st.commit()
    log(f"отправлено {total} из {len(todo)} за {time.time() - started:.0f} с")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # крон должен оставить причину в журнале
        log("ошибка:", e)
        sys.exit(1)
