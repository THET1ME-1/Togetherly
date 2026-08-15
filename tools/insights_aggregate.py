#!/usr/bin/env python3
"""Продуктовые срезы для вкладки «Продукт» в админке.

Почему отдельным скриптом. SQLite внутри PocketBase — чистый Go-порт без CGO,
и полный скан там в десятки раз медленнее нативного: `SELECT COUNT(*) FROM
users` (41 тысяча строк) отвечает из хука за 2,2 секунды, когорты — за 43, а
весь роут `/modapi/insights` собирался ТРИ МИНУТЫ, из-за чего вкладка выглядела
намертво зависшей. Те же запросы в системном sqlite3 укладываются в сотые доли
секунды. Поэтому считаем здесь по крону, а хук только отдаёт готовый файл —
ровно как с `stats_aggregate.py` и сводкой дохода.

Ответ повторяет прежнюю структуру роута один в один: фронт админки не трогаем.

Запуск: `python3 /opt/income/insights_aggregate.py` по крону раз в 10 минут.
"""
import json
import os
import sqlite3
from datetime import datetime, timezone

DB = "/opt/pocketbase/pb_data/data.db"
OUT = "/opt/pocketbase/pb_data/.insights.json"
OUT_STATS = "/opt/pocketbase/pb_data/.stats.json"

PALETTES = {
    "0": "Розовая", "1": "Фиолетовая", "2": "Голубая", "3": "Персиковая",
    "4": "Шалфейная", "5": "Полуночная", "6": "Лавандовая", "7": "Вишнёвая",
    "8": "Мятная", "9": "Закатная", "10": "Монохром", "11": "Лесная",
    "12": "Океан", "13": "Медовая", "14": "Лимонная", "15": "Песочная",
    "16": "Северное сияние", "17": "Бордовая", "18": "Бирюзовая", "19": "Нордик",
    "20": "Угольная бирюза", "21": "Кофе", "22": "Тёмный лес", "23": "Гранат",
    "24": "Тёмный мёд",
}
MODES = {"light": "Светлая", "dark": "Тёмная", "system": "Как в системе"}
PLATFORMS = {"android": "Android", "ios": "iOS", "unknown": "Неизвестно"}
PLUS_WHERE = {"play": "Google Play", "lava": "lava.top", "code": "Код от бота", "unknown": "До 28 июля"}

MEMBERS = "json_array_length(CASE WHEN json_valid(members) THEN members ELSE '[]' END)"
CREATED_MS = "(julianday(u.created) - 2440587.5) * 86400000"
PLATFORM_KEY = "CASE WHEN platform IN ('android','ios') THEN platform ELSE 'unknown' END"


def hotpath_stats() -> dict:
    """Срезы по коллекциям, уехавшим в Postgres (memories, widget_data и др.).
    Пустой словарь при недоступности — карточки покажут нули, а не сломаются."""
    try:
        import urllib.request
        with urllib.request.urlopen(
            "http://127.0.0.1:8120/internal/product-stats", timeout=15
        ) as r:
            return json.load(r)
    except Exception:
        return {}


def build(db: sqlite3.Connection) -> dict:
    hp = hotpath_stats()

    def one(sql: str, default=0):
        # Горячие коллекции живут в hotpath (Postgres) с 14.08.2026 —
        # их счётчики спрашиваем у него, остальное по-прежнему SQLite.
        if sql.startswith("HP:"):
            return hp.get(sql.split(":", 1)[1], default)
        if sql.startswith("HOTPATH:"):
            try:
                import urllib.request
                with urllib.request.urlopen(
                    "http://127.0.0.1:8120/internal/count?" + ("col=" + sql.split(":", 1)[1] if "?" not in sql else "col=" + sql.split(":", 1)[1].replace("?", "&")),
                    timeout=5,
                ) as r:
                    return json.load(r).get("n", default)
            except Exception:
                return default
        try:
            row = db.execute(sql).fetchone()
            return (row[0] if row and row[0] is not None else default)
        except sqlite3.Error:
            return default

    def many(sql: str) -> list:
        try:
            return db.execute(sql).fetchall()
        except sqlite3.Error:
            return []

    out: dict = {}

    # 1. Удержание по когортам недели регистрации.
    out["cohorts"] = [
        {"wk": r[0], "n": r[1], "d7": r[2], "d30": r[3], "age": r[4]}
        for r in many(
            "SELECT strftime('%Y-%m-%d', u.created, 'weekday 0', '-6 days') AS wk, COUNT(*),"
            f" SUM(CASE WHEN CAST(p.seen_at AS INTEGER) >= {CREATED_MS} + 604800000 THEN 1 ELSE 0 END),"
            f" SUM(CASE WHEN CAST(p.seen_at AS INTEGER) >= {CREATED_MS} + 2592000000 THEN 1 ELSE 0 END),"
            " CAST(julianday('now') - julianday(MAX(u.created)) AS INTEGER)"
            " FROM users u LEFT JOIN user_presence p ON p.user_uid = u.id"
            " GROUP BY wk ORDER BY wk")
    ]

    # 2. Воронка активации: шаги независимы, следующий может быть шире прошлого.
    out["funnel"] = [
        {"k": "Зарегистрировались", "v": one("SELECT COUNT(*) FROM users")},
        {"k": "Поставили аватар", "v": one("SELECT COUNT(*) FROM users WHERE avatar_url != ''")},
        {"k": "Завели группу", "v": one(
            "SELECT COUNT(DISTINCT je.value) FROM groups g, json_each(g.members) je"
            " WHERE g.disbanded = false AND json_valid(g.members)")},
        {"k": "Сошлись в пару", "v": one(
            "SELECT COUNT(DISTINCT je.value) FROM groups g, json_each(g.members) je"
            f" WHERE g.disbanded = false AND json_valid(g.members) AND {MEMBERS} >= 2")},
        {"k": "Написали воспоминание", "v": hp.get("memory_authors", 0)},
        {"k": "Вернулись через неделю", "v": one(
            "SELECT COUNT(*) FROM users u JOIN user_presence p ON p.user_uid = u.id"
            f" WHERE CAST(p.seen_at AS INTEGER) >= {CREATED_MS} + 604800000")},
    ]

    # 3. Живучесть пар. Медиана вместо среднего: распавшиеся в первый день
    #    тянут среднее вниз сильнее, чем прожившие год тянут вверх.
    life = "CAST(julianday(disbanded_at) - julianday(created_at) AS INTEGER)"
    dated = one("SELECT COUNT(*) FROM groups WHERE disbanded = true AND disbanded_at != ''")
    out["pairs"] = {
        "alive": one("SELECT COUNT(*) FROM groups WHERE disbanded = false"),
        "disbanded": one("SELECT COUNT(*) FROM groups WHERE disbanded = true"),
        "dated": dated,
        "medianDays": one(
            f"SELECT {life} FROM groups WHERE disbanded = true AND disbanded_at != ''"
            f" ORDER BY {life} LIMIT 1 OFFSET {dated // 2}"),
        "buckets": [{"k": r[0], "c": r[1]} for r in many(
            f"SELECT CASE WHEN {life} < 7 THEN 'до недели'"
            f" WHEN {life} < 30 THEN 'до месяца'"
            f" WHEN {life} < 90 THEN '1–3 месяца'"
            f" WHEN {life} < 180 THEN '3–6 месяцев'"
            f" WHEN {life} < 365 THEN 'полгода–год' ELSE 'больше года' END, COUNT(*)"
            " FROM groups WHERE disbanded = true AND disbanded_at != '' GROUP BY 1")],
        "byMonth": [{"m": r[0], "c": r[1]} for r in many(
            "SELECT substr(disbanded_at,1,7), COUNT(*) FROM groups"
            " WHERE disbanded = true AND disbanded_at != '' GROUP BY 1 ORDER BY 1")],
    }

    # 4. Экономика монет: журнала начислений нет, считаем остаток и владение.
    def owners_of(col: str) -> int:
        return one(f"SELECT COUNT(*) FROM users WHERE {col} IS NOT NULL"
                   f" AND json_valid({col}) AND json_array_length({col}) > 0")

    out["coins"] = {
        "inWallets": one("SELECT COALESCE(SUM(coins),0) FROM users"),
        "holders": one("SELECT COUNT(*) FROM users WHERE coins > 0"),
        "themeOwners": owners_of("owned_themes"),
        "iconOwners": owners_of("owned_icons"),
        "featureOwners": owners_of("owned_features"),
        "plus": one("SELECT COUNT(*) FROM users WHERE plus = 1"),
        "purchases": one("SELECT COUNT(*) FROM iap_purchases"),
        "donations": one("SELECT COUNT(*) FROM donation_grants"),
        "topThemes": [{"k": PALETTES.get(str(r[0]), f"Палитра {r[0]}"), "c": r[1]} for r in many(
            "SELECT je.value, COUNT(*) FROM users u, json_each(u.owned_themes) je"
            " WHERE json_valid(u.owned_themes) GROUP BY 1 ORDER BY 2 DESC LIMIT 8")],
        "top": [{"uid": r[0], "name": r[1] or r[2] or "", "email": r[3] or "",
                 "coins": r[4] or 0, "plus": bool(r[5]), "groupId": r[6] or ""} for r in many(
            "SELECT u.id, u.display_name, u.name, u.email, u.coins, CAST(u.plus AS INT),"
            " COALESCE((SELECT je.value FROM json_each(u.group_ids) je"
            "           WHERE json_valid(u.group_ids) LIMIT 1), '')"
            " FROM users u WHERE u.coins > 0 ORDER BY u.coins DESC LIMIT 10")],
    }

    # 4б. Оформление. Режимы отдаём все три, даже с нулём: иначе по одному
    #     тёмному аккаунту выходило «Тёмная — 100%».
    mode_counts = {r[0]: r[1] for r in many(
        "SELECT theme_mode, COUNT(*) FROM users WHERE theme_mode != '' GROUP BY 1")}
    out["appearance"] = {
        "known": one("SELECT COUNT(*) FROM users WHERE theme_mode != ''"),
        "modes": sorted(
            [{"k": MODES.get(k, k), "c": mode_counts.get(k, 0)} for k in ("light", "dark", "system")],
            key=lambda x: -x["c"]),
        "palettes": [{"k": PALETTES.get(str(r[0]), f"Палитра {r[0]}"), "c": r[1]} for r in many(
            "SELECT theme_id, COUNT(*) FROM users WHERE theme_mode != '' GROUP BY 1"
            " ORDER BY 2 DESC LIMIT 10")],
    }

    # 4в. Платформы. Доли берём от ВСЕХ, а не от известных: поле пишется с
    #     версии от 28 июля, и по горстке аккаунтов вышло бы «100% iOS».
    users_all = one("SELECT COUNT(*) FROM users") or 1

    def split_by(where: str) -> list:
        rows = {r[0]: r[1] for r in many(
            f"SELECT {PLATFORM_KEY}, COUNT(*) FROM users"
            + (f" WHERE {where}" if where else "") + " GROUP BY 1")}
        return rows

    def ordered(rows: dict, total: int) -> list:
        return [{"k": PLATFORMS[key], "c": rows.get(key, 0),
                 "share": round(rows.get(key, 0) / total * 1000) / 10 if total else 0}
                for key in ("android", "ios", "unknown")]

    new7 = one("SELECT COUNT(*) FROM users WHERE created >= datetime('now','-7 days')")
    new30 = one("SELECT COUNT(*) FROM users WHERE created >= datetime('now','-30 days')")
    out["platforms"] = {
        "total": users_all,
        "known": one("SELECT COUNT(*) FROM users WHERE platform IN ('android','ios')"),
        "split": ordered(split_by(""), users_all),
        "new7": {"total": new7, "split": ordered(split_by("created >= datetime('now','-7 days')"), new7)},
        "new30": {"total": new30, "split": ordered(split_by("created >= datetime('now','-30 days')"), new30)},
        "mixedPairs": one(
            "SELECT COUNT(*) FROM groups g WHERE g.disbanded = false AND json_valid(g.members)"
            f" AND {MEMBERS} >= 2 AND (SELECT COUNT(DISTINCT u.platform) FROM json_each(g.members) je"
            " JOIN users u ON u.id = je.value WHERE u.platform IN ('android','ios')) = 2"),
        "knownPairs": one(
            "SELECT COUNT(*) FROM groups g WHERE g.disbanded = false AND json_valid(g.members)"
            f" AND {MEMBERS} >= 2 AND (SELECT COUNT(*) FROM json_each(g.members) je"
            " JOIN users u ON u.id = je.value WHERE u.platform IN ('android','ios')) >= 2"),
        "plusTotal": one("SELECT COUNT(*) FROM users WHERE plus = 1"),
        "plusOnIos": one("SELECT COUNT(*) FROM users WHERE plus = 1 AND platform = 'ios'"),
        "plusBy": [{"k": PLUS_WHERE.get(r[0], r[0]), "c": r[1]} for r in many(
            "SELECT CASE WHEN plus_platform IN ('play','lava','code') THEN plus_platform"
            " ELSE 'unknown' END, COUNT(*) FROM users WHERE plus = 1 GROUP BY 1 ORDER BY 2 DESC")],
    }

    # 5. Что живо. Единица счёта — пары, а не записи: миллион штрихов может
    #    нарисовать одна упорная пара, и фича выглядела бы народной.
    groups_all = one("SELECT COUNT(*) FROM groups") or 1
    features = [
        ("Воспоминания", "HP:memories_groups"),
        ("Чат", "HOTPATH:chat_messages"),  # чат в Postgres с 14.08.2026
        ("Настроения", "HOTPATH:mood_entries"),
        ("Виджеты", "HP:widget_groups"),
        ("Маскоты", "SELECT COUNT(DISTINCT group_id) FROM mascots"),
        ("«Скучаю»", "SELECT COUNT(DISTINCT group_id) FROM miss_you"),
        ("Рисование", "HOTPATH:canvas_strokes"),  # штрихи в Postgres с 14.08.2026
        ("Подарки", "SELECT COUNT(DISTINCT group_id) FROM gifts"),
        ("Совместный просмотр", "SELECT COUNT(DISTINCT group_id) FROM watch_history"),
        ("Цикл", "SELECT COUNT(DISTINCT group_id) FROM cycle_entries"),
    ]
    out["features"] = [{"k": label, "c": (c := one(sql)),
                        "share": round(c / groups_all * 1000) / 10} for label, sql in features]
    out["groupsAll"] = groups_all

    # 6. Виджеты: что пары держат на рабочем столе.
    def filled(cond: str) -> int:
        # widget_data в Postgres: срезы приходят готовыми из hotpath.
        return hp.get({"status != ''": "widget_with_status",
                       "mood_label != ''": "widget_with_mood",
                       "message != ''": "widget_with_message",
                       "photo_url != ''": "widget_with_photo",
                       "music_title != ''": "widget_with_music"}.get(cond, ""), 0)

    out["widgets"] = {
        "records": hp.get("widget_rows", 0),
        "groups": hp.get("widget_groups", 0),
        "fields": [
            {"k": "Статус", "c": filled("status != ''")},
            {"k": "Настроение", "c": filled("mood_label != ''")},
            {"k": "Сообщение", "c": filled("message != ''")},
            {"k": "Фото себе", "c": filled("photo_url != ''")},
            {"k": "Фото партнёру", "c": filled("photo_for_partner_url != ''")},
            {"k": "Музыка", "c": filled("music_title != ''")},
            {"k": "Сетка фото", "c": filled(
                "json_valid(photo_grid_urls) AND json_array_length(photo_grid_urls) > 0")},
        ],
    }

    out["updated"] = datetime.now(timezone.utc).isoformat()
    return out


def build_stats(db: sqlite3.Connection) -> dict:
    """Обзорная вкладка. Живой «онлайн» из Centrifugo сюда не входит — его
    хук спрашивает сам на каждом запросе, это дёшево."""
    hp = hotpath_stats()

    def one(sql: str, default=0):
        # Маркеры те же, что в build(): горячие коллекции живут в Postgres, и
        # спрашивать их надо у hotpath. Без этой ветки строка «HOTPATH:…»
        # уходила в SQLite как обычный SQL, падала и превращалась в ноль —
        # сводка честно писала «сообщений 0» при живом чате (15.08.2026).
        if sql.startswith("HP:"):
            return hp.get(sql.split(":", 1)[1], default)
        if sql.startswith("HOTPATH:"):
            try:
                import urllib.request
                хвост = sql.split(":", 1)[1]
                запрос = ("col=" + хвост.replace("?", "&")
                          if "?" in хвост else "col=" + хвост)
                with urllib.request.urlopen(
                    "http://127.0.0.1:8120/internal/count?" + запрос, timeout=5,
                ) as r:
                    return json.load(r).get("n", default)
            except Exception:
                return default
        try:
            row = db.execute(sql).fetchone()
            return (row[0] if row and row[0] is not None else default)
        except sqlite3.Error:
            return default

    def many(sql: str) -> list:
        try:
            return db.execute(sql).fetchall()
        except sqlite3.Error:
            return []

    video = "(lower(file) LIKE '%.mp4' OR lower(file) LIKE '%.mov' OR lower(file) LIKE '%.m4v'" \
            " OR lower(file) LIKE '%.webm' OR lower(file) LIKE '%.3gp' OR lower(file) LIKE '%.mkv')"
    out = {
        "totalUsers": one("SELECT COUNT(*) FROM users"),
        "pairedGroups": one(f"SELECT COUNT(*) FROM groups WHERE disbanded = false AND {MEMBERS} >= 2"),
        "soloGroups": one(f"SELECT COUNT(*) FROM groups WHERE disbanded = false AND {MEMBERS} = 1"),
        "totalGroups": one("SELECT COUNT(*) FROM groups WHERE disbanded = false"),
        "disbanded": one("SELECT COUNT(*) FROM groups WHERE disbanded = true"),
        "activeHour": one("SELECT COUNT(*) FROM users WHERE updated >= datetime('now','-1 hours')"),
        "dau": one("SELECT COUNT(*) FROM users WHERE updated >= datetime('now','-24 hours')"),
        "wau": one("SELECT COUNT(*) FROM users WHERE updated >= datetime('now','-7 days')"),
        "mau": one("SELECT COUNT(*) FROM users WHERE updated >= datetime('now','-30 days')"),
        "newHour": one("SELECT COUNT(*) FROM users WHERE created >= datetime('now','-1 hours')"),
        "newDay": one("SELECT COUNT(*) FROM users WHERE created >= datetime('now','-24 hours')"),
        "newWeek": one("SELECT COUNT(*) FROM users WHERE created >= datetime('now','-7 days')"),
        "baselineUsers": one("SELECT COUNT(*) FROM users WHERE created < datetime('now','-30 days')"),
        "content": {
            "memories": hp.get("memories_rows", 0),
            "messages": one("HOTPATH:chat_messages?mode=rows"),
            "media": one("SELECT COUNT(*) FROM media"),
            "videos": one(f"SELECT COUNT(*) FROM media WHERE {video}"),
            "moods": one("HOTPATH:mood_entries?mode=rows"),
            "missYou": one("SELECT COALESCE(SUM(count),0) FROM miss_you"),
            "mascots": one("SELECT COUNT(*) FROM mascots"),
            "comments": one("SELECT COUNT(*) FROM memory_comments"),
        },
        "daily": [{"d": r[0], "c": r[1]} for r in many(
            "SELECT substr(created,1,10), COUNT(*) FROM users"
            " WHERE created >= datetime('now','-30 days') GROUP BY 1 ORDER BY 1")],
        "mediaKinds": [{"k": r[0], "c": r[1]} for r in many(
            "SELECT kind, COUNT(*) FROM media GROUP BY 1 ORDER BY 2 DESC")],
        "moods": [{"k": m["k"], "c": m["c"]} for m in hp.get("mood_labels", [])[:10]],
        "online": None,
    }
    out["content"]["photos"] = (out["content"]["media"] or 0) - (out["content"]["videos"] or 0)
    out["updated"] = datetime.now(timezone.utc).isoformat()
    return out


def write_json(path: str, data: dict) -> None:
    tmp = path + ".tmp"
    # ensure_ascii обязателен: хук читает файл побайтово как latin-1.
    with open(tmp, "w", encoding="ascii") as f:
        json.dump(data, f, ensure_ascii=True)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def main() -> int:
    started = datetime.now(timezone.utc)
    # Только чтение: база живая, писать в неё мимо PocketBase нельзя.
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
    db.execute("PRAGMA query_only = 1")
    try:
        data = build(db)
        stats = build_stats(db)
    finally:
        db.close()
    data["took_ms"] = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)
    write_json(OUT, data)
    write_json(OUT_STATS, stats)
    print(f"готово за {data['took_ms']} мс, когорт {len(data['cohorts'])}, "
          f"пар живых {data['pairs']['alive']}, всего людей {stats['totalUsers']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
