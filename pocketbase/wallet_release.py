#!/usr/bin/env python3
"""Выход Togetherly Wallet: флаг для кнопки на главной и рассылка пушей.

Запускается на сервере PocketBase (`/opt/pocketbase/tools/wallet_release.py`).

    python3 wallet_release.py status
    python3 wallet_release.py open  --platform android     # кнопка ведёт в Wallet
    python3 wallet_release.py close --platform android     # вернуть стену ожидания
    python3 wallet_release.py push  --audience waitlist --platform android --dry-run
    python3 wallet_release.py push  --audience waitlist --platform android

Флаг живёт в `app_config.wallet` (json): `android`, `ios` и ссылки на магазины.
Клиент читает его вместе с остальным конфигом на главной и в ответе
`/api/wallet/waitlist`, поэтому обновлять Togetherly не нужно. Платформы
открываются по отдельности: карточка в App Store может задержаться на ревью,
и iPhone тогда продолжает видеть стену.

Пуши идут через те же релеи, что у хуков (`apns_push.js`): APNs на 8096, FCM на
8100, с `sync: true`, чтобы видеть ответ Apple и Google на каждый токен. Кому
уже ушло, записано в `pb_data/.wallet_push_sent`, и повторный запуск их
пропускает: оборванную рассылку можно просто запустить снова.

`--audience waitlist` — те, кто нажал «Добавить в ожидание».
`--audience all` — все, у кого есть токен (около ста тысяч человек).
"""

import argparse
import json
import sqlite3
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

DB = "/opt/pocketbase/pb_data/data.db"
SENT = "/opt/pocketbase/pb_data/.wallet_push_sent"
APNS = "http://127.0.0.1:8096/push"
FCM = "http://127.0.0.1:8100/push"

TITLE = "Togetherly Wallet вышел"
BODY = "Общий бюджет на двоих, делёж трат и цели. Нажмите, чтобы установить."


def db(readonly=True):
    uri = f"file:{DB}?mode=ro" if readonly else f"file:{DB}"
    con = sqlite3.connect(uri, uri=True, timeout=15)
    con.execute("PRAGMA busy_timeout = 15000")
    return con


def load_config():
    row = db().execute("SELECT id, wallet FROM app_config LIMIT 1").fetchone()
    if not row:
        sys.exit("В app_config нет записи")
    return row[0], json.loads(row[1] or "{}")


def status(_args):
    _, cfg = load_config()
    con = db()
    total = con.execute("SELECT COUNT(*) FROM wallet_waitlist").fetchone()[0]
    by = con.execute(
        "SELECT platform, COUNT(*) FROM wallet_waitlist GROUP BY 1 ORDER BY 2 DESC").fetchall()
    reach = con.execute(
        "SELECT SUM(u.fcm_token != ''), SUM(u.apns_token != '') "
        "FROM wallet_waitlist w JOIN users u ON u.id = w.user_uid").fetchone()
    print("Флаг выхода:", json.dumps({k: cfg.get(k) for k in ("android", "ios")}, ensure_ascii=False))
    print("Ссылки:", json.dumps({k: v for k, v in cfg.items() if k not in ("android", "ios")},
                                ensure_ascii=False, indent=2))
    print(f"Ждут: {total}", dict(by))
    print(f"Из них с токеном FCM: {reach[0] or 0}, APNs: {reach[1] or 0}")


def set_flag(args, value):
    rec_id, cfg = load_config()
    for p in (["android", "ios"] if args.platform == "all" else [args.platform]):
        cfg[p] = value
    con = db(readonly=False)
    con.execute("UPDATE app_config SET wallet = ? WHERE id = ?",
                (json.dumps(cfg, ensure_ascii=False), rec_id))
    con.commit()
    print("Флаг выхода теперь:", {k: cfg.get(k) for k in ("android", "ios")})


def targets(audience, platform):
    con = db()
    if audience == "waitlist":
        rows = con.execute(
            "SELECT u.id, u.fcm_token, u.apns_token, u.apns_sandbox "
            "FROM wallet_waitlist w JOIN users u ON u.id = w.user_uid").fetchall()
    else:
        rows = con.execute(
            "SELECT id, fcm_token, apns_token, apns_sandbox FROM users "
            "WHERE fcm_token != '' OR apns_token != ''").fetchall()
    out = []
    for uid, fcm, apns, sandbox in rows:
        if fcm and platform in ("android", "all"):
            out.append((uid, "fcm", fcm, False))
        if apns and platform in ("ios", "all"):
            out.append((uid, "apns", apns, bool(sandbox)))
    return out


def post(url, body):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b"{}")


def push(args):
    _, cfg = load_config()
    package = cfg.get("package") or "com.togetherly.money"
    # Касание по пушу обрабатывает Togetherly: на Android открывает Wallet, если
    # он стоит, иначе эту ссылку; на iPhone ссылку на App Store.
    links = {
        "fcm": f"market://details?id={package}",
        "apns": cfg.get("appstore") or "",
    }
    for kind, plat in (("fcm", "android"), ("apns", "ios")):
        if args.platform in (plat, "all") and not cfg.get(plat) and not args.force:
            sys.exit(f"Флаг {plat} выключен: сперва `open --platform {plat}`, "
                     f"иначе касание по пушу приведёт на стену ожидания (или --force)")

    try:
        done = set(open(SENT).read().split())
    except FileNotFoundError:
        done = set()
    todo = [t for t in targets(args.audience, args.platform) if f"{t[0]}:{t[1]}" not in done]
    if args.limit:
        todo = todo[: args.limit]
    print(f"К отправке: {len(todo)} (уже отправлено раньше: {len(done)})")
    if args.dry_run or not todo:
        return

    lock = threading.Lock()
    stats = {"ok": 0, "gone": 0, "fail": 0}
    log = open(SENT, "a")

    def one(t):
        uid, kind, token, sandbox = t
        data = {"kind": "wallet", "url": links[kind], "package": package}
        if kind == "fcm":
            body = {"token": token, "title": TITLE, "body": BODY, "tag": "wallet",
                    "data": data, "sync": True}
        else:
            body = {"token": token, "title": TITLE, "body": BODY, "thread": "wallet",
                    "sandbox": sandbox, "data": data, "sync": True}
        try:
            ans = post(FCM if kind == "fcm" else APNS, body)
            key = "ok" if ans.get("ok") else ("gone" if ans.get("gone") else "fail")
        except Exception:
            key = "fail"
        with lock:
            stats[key] += 1
            # Мёртвый токен тоже помечаем: второй раз стучаться в него незачем,
            # а вычистит его из профиля обычная рассылка хуков.
            if key != "fail":
                log.write(f"{uid}:{kind}\n")
            n = sum(stats.values())
            if n % 500 == 0:
                log.flush()
                print(f"  {n}/{len(todo)} {stats}", flush=True)

    started = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(one, todo))
    log.close()
    print(f"Готово за {time.time() - started:.0f} с: {stats}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    for name in ("open", "close"):
        p = sub.add_parser(name)
        p.add_argument("--platform", choices=["android", "ios", "all"], required=True)
    p = sub.add_parser("push")
    p.add_argument("--audience", choices=["waitlist", "all"], required=True)
    p.add_argument("--platform", choices=["android", "ios", "all"], default="all")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()
    if args.cmd == "status":
        status(args)
    elif args.cmd == "open":
        set_flag(args, True)
    elif args.cmd == "close":
        set_flag(args, False)
    else:
        push(args)


if __name__ == "__main__":
    main()
