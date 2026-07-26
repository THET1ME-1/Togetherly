#!/usr/bin/env python3
"""Посещения совместного просмотра из журнала Caddy.

Журнал пишет только `/watch/*` (см. блок `log watch` в /etc/caddy/Caddyfile).
Код комнаты живёт в хеше адреса (`/watch/room/#код`), а хеш браузер на сервер
не отправляет — из логов видно, что человек открыл комнату, но не какую.

Запуск на сервере:
    python3 watch_stats.py                    # последние 30 дней
    python3 watch_stats.py --days 7
    python3 watch_stats.py --log /путь/watch.log

С ключом --json пишет сводку файлом — её читает админка (`/modapi/site-stats`).
Разбирать мегабайты журнала на каждое открытие страницы незачем, поэтому файл
обновляет крон раз в десять минут:

    */10 * * * * python3 /opt/watch_stats.py --json /opt/pocketbase/pb_data/.watch_stats.json
"""
import argparse
import glob
import json
import os
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# Страницы, а не их обвес: js, css и картинки в счёт посещений не идут.
PAGES = {
    "/watch/": "лендинг",
    "/watch/index.html": "лендинг",
    "/watch/room/": "комната",
    "/watch/room/index.html": "комната",
}


def rows(pattern):
    """Читает журнал и все его ротации, отдаёт разобранные записи."""
    for path in sorted(glob.glob(pattern)):
        if not os.path.isfile(path):
            continue
        with open(path, errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    yield json.loads(line)
                except ValueError:
                    continue


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default="/var/log/caddy/watch.log")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--json", help="записать сводку сюда вместо печати")
    args = ap.parse_args()

    pattern = args.log.replace(".log", "*.log")
    edge = datetime.now(timezone.utc) - timedelta(days=args.days)

    by_day = defaultdict(lambda: defaultdict(int))
    ips_day = defaultdict(set)
    ips_all = set()
    agents = defaultdict(int)
    total = defaultdict(int)

    for row in rows(pattern):
        req = row.get("request") or {}
        uri = (req.get("uri") or "").split("?")[0]
        page = PAGES.get(uri)
        if not page:
            continue
        when = datetime.fromtimestamp(row.get("ts", 0), timezone.utc)
        if when < edge:
            continue

        day = when.date().isoformat()
        ip = req.get("client_ip") or req.get("remote_ip") or "?"
        by_day[day][page] += 1
        total[page] += 1
        ips_day[day].add(ip)
        ips_all.add(ip)

        ua = ((req.get("headers") or {}).get("User-Agent") or [""])[0]
        # Приложение открывает комнату во встроенном браузере — по этой метке
        # видно, пришёл человек из приложения или со стороны.
        kind = "приложение" if "wv)" in ua or "Togetherly" in ua else "браузер"
        agents[kind] += 1

    if args.json:
        summary = {
            "updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "days": [
                {
                    "d": day,
                    "landing": by_day[day]["лендинг"],
                    "room": by_day[day]["комната"],
                    "uniques": len(ips_day[day]),
                }
                for day in sorted(by_day)
            ],
            "landing": total["лендинг"],
            "room": total["комната"],
            "uniques": len(ips_all),
            "app": agents["приложение"],
            "web": agents["браузер"],
        }
        tmp = args.json + ".tmp"
        with open(tmp, "w") as f:
            json.dump(summary, f, ensure_ascii=False)
        # Подменяем целиком: админка не должна прочитать файл на середине записи.
        os.replace(tmp, args.json)
        os.chmod(args.json, 0o644)
        print(f"сводка записана: {args.json} ({len(summary['days'])} дн.)")
        return

    if not total:
        print(f"За {args.days} дн. записей нет: {pattern}")
        return

    print(f"Посещения совместного просмотра за {args.days} дн.")
    print(f"  лендинг: {total['лендинг']}, комната: {total['комната']}")
    print(f"  уникальных адресов: {len(ips_all)}")
    print(f"  из приложения: {agents['приложение']}, со стороны: {agents['браузер']}")
    print()
    print(f"{'день':<12}{'лендинг':>9}{'комната':>9}{'адресов':>9}")
    for day in sorted(by_day, reverse=True):
        d = by_day[day]
        print(f"{day:<12}{d['лендинг']:>9}{d['комната']:>9}{len(ips_day[day]):>9}")


if __name__ == "__main__":
    main()
