#!/usr/bin/env python3
"""Сворачивает сырые события аналитики в суточные срезы.

Крон в 5:30 (отдельно от шифрованного бэкапа в 4:30 — незачем соревноваться за
диск):

    30 5 * * * python3 /opt/app_stats/stats_aggregate.py

Делает три вещи:
  * пересчитывает `daily` за последние дни (пересчёт, а не досчёт: пачка могла
    доехать с опозданием, и досчёт задвоил бы события);
  * пишет `pb_data/.app_stats.json` — его читает `/modapi/app-stats`, а рисует
    вкладка «Экраны» в админке. Разбирать миллионы строк на каждое открытие
    страницы нельзя, поэтому витрина живёт готовым файлом (тот же приём, что у
    `watch_stats.py`);
  * чистит сырьё старше 14 дней. Суточные срезы остаются навсегда, они весят
    копейки.
"""
import argparse
import json
import os
import sqlite3
from datetime import datetime, timedelta, timezone

DB_PATH = os.environ.get("STATS_DB", "/opt/app_stats/stats.db")
OUT_JSON = os.environ.get(
    "STATS_JSON", "/opt/pocketbase/pb_data/.app_stats.json")

RAW_KEEP_DAYS = 14
RECOUNT_DAYS = 3  # сколько последних суток пересчитывать
WINDOW_DAYS = 30  # глубина витрины
TOP = 25  # сколько имён показывать в топах


def db(path=None):
    conn = sqlite3.connect(path or DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def recount(conn, since_day):
    """Пересчитывает суточные срезы начиная с [since_day] (включительно)."""
    conn.execute("DELETE FROM daily WHERE day >= ?", (since_day,))
    conn.execute(
        """
        INSERT INTO daily (day, kind, name, hits, uniques, ms_total)
        SELECT date(ts, 'unixepoch') AS day,
               kind,
               name,
               COUNT(*),
               COUNT(DISTINCT uid_hash),
               COALESCE(SUM(ms), 0)
        FROM events
        WHERE date(ts, 'unixepoch') >= ?
        GROUP BY day, kind, name
        """,
        (since_day,),
    )


def window(conn, kind, days):
    """Топ имён внутри вида событий за последние [days] суток.

    `uniques` суммировать по дням нельзя — один человек, заходивший всю неделю,
    посчитался бы семь раз. Уникальные берём прямо из сырья, поэтому окно и
    ограничено сроком хранения сырых событий.
    """
    edge = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    rows = conn.execute(
        """
        SELECT name,
               SUM(hits) AS hits,
               SUM(ms_total) AS ms_total
        FROM daily
        WHERE kind = ? AND day >= ?
        GROUP BY name
        ORDER BY hits DESC
        LIMIT ?
        """,
        (kind, edge, TOP),
    ).fetchall()

    edge_ts = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp())
    uniq = {
        r["name"]: r["u"]
        for r in conn.execute(
            "SELECT name, COUNT(DISTINCT uid_hash) AS u FROM events"
            " WHERE kind = ? AND ts >= ? GROUP BY name",
            (kind, edge_ts),
        )
    }

    out = []
    for r in rows:
        hits = r["hits"] or 0
        ms = r["ms_total"] or 0
        out.append(
            {
                "name": r["name"],
                "hits": hits,
                "uniques": uniq.get(r["name"], 0),
                # Среднее время на экране, секунды. Для действий смысла не
                # имеет и остаётся нулём.
                "avg_sec": round(ms / hits / 1000, 1) if hits and ms else 0,
            }
        )
    return out


def by_day(conn, days):
    """Ряд по дням: сколько экранов открыли и сколько человек их открывало."""
    edge = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    rows = conn.execute(
        """
        SELECT day, kind, SUM(hits) AS hits
        FROM daily WHERE day >= ?
        GROUP BY day, kind ORDER BY day
        """,
        (edge,),
    ).fetchall()
    acc = {}
    for r in rows:
        acc.setdefault(r["day"], {"d": r["day"]})[r["kind"]] = r["hits"]
    return list(acc.values())


def funnel(conn, days):
    """Путь новичка: сколько человек прошло каждый шаг за последние сутки-N.

    Шаги перечислены явно и в порядке прохождения: сортировать их по числу
    нельзя, иначе просевший шаг уедет вниз и воронка перестанет читаться.
    """
    steps = [
        ("signup", "Регистрация"),
        ("invite_screen", "Экран приглашения"),
        ("invite_sent", "Код отправлен"),
        ("pair_created", "Пара собралась"),
        ("first_action", "Первое действие"),
    ]
    edge_ts = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp())
    out = []
    for key, label in steps:
        n = conn.execute(
            "SELECT COUNT(DISTINCT uid_hash) AS u FROM events"
            " WHERE kind = 'funnel' AND name = ? AND ts >= ?",
            (key, edge_ts),
        ).fetchone()["u"]
        out.append({"k": key, "label": label, "users": n})
    # Доля считается от первого шага. Пока приложение шлёт из пяти шагов один
    # (`pair_created`), первый шаг равен нулю, и подстановка единицы вместо
    # него выдавала «56 человек · 5600%». Нет базы — нет и доли: None честно
    # говорит «считать не от чего», а ноль соврал бы про «никто не дошёл».
    first = out[0]["users"]
    for step in out:
        step["share"] = round(step["users"] / first * 1000) / 10 if first else None
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DB_PATH)
    ap.add_argument("--json", default=OUT_JSON)
    ap.add_argument("--keep", type=int, default=RAW_KEEP_DAYS)
    args = ap.parse_args()

    conn = db(args.db)
    since = (datetime.now(timezone.utc) - timedelta(days=RECOUNT_DAYS)).strftime(
        "%Y-%m-%d")
    with conn:
        recount(conn, since)

    summary = {
        "updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "window": WINDOW_DAYS,
        "raw_keep": args.keep,
        "days": by_day(conn, WINDOW_DAYS),
        "screens": window(conn, "screen", 7),
        "actions": window(conn, "action", 7),
        "ads": window(conn, "ad", 7),
        "funnel": funnel(conn, 7),
        "totals": {
            "events": conn.execute("SELECT COUNT(*) AS n FROM events").fetchone()["n"],
            "people": conn.execute(
                "SELECT COUNT(DISTINCT uid_hash) AS n FROM events").fetchone()["n"],
        },
    }

    tmp = args.json + ".tmp"
    # ensure_ascii=True не для красоты: файл читает хук админки, а в JSVM он
    # склеивается из байтов через String.fromCharCode — то есть по latin-1.
    # Русские подписи воронки доезжали до страницы как «ÐÐµÐ³Ð¸ÑÑÑÐ°ÑÐ¸Ñ».
    # Экранированный \uXXXX проходит этот путь без потерь.
    with open(tmp, "w") as f:
        json.dump(summary, f, ensure_ascii=True)
    # Подменяем целиком: админка не должна прочитать файл на середине записи.
    os.replace(tmp, args.json)
    os.chmod(args.json, 0o644)

    edge_ts = int((datetime.now(timezone.utc) - timedelta(days=args.keep)).timestamp())
    with conn:
        removed = conn.execute("DELETE FROM events WHERE ts < ?", (edge_ts,)).rowcount
    # VACUUM вне транзакции; база маленькая, идёт быстро.
    conn.execute("VACUUM")
    conn.close()

    print(
        f"сводка записана: {args.json}; "
        f"событий {summary['totals']['events']}, "
        f"людей {summary['totals']['people']}, "
        f"вычищено старых {removed}"
    )


if __name__ == "__main__":
    main()
