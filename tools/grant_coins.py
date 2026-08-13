#!/usr/bin/env python3
"""Начислить монеты человеку по почте — для призов и компенсаций.

Экономику ведут серверные роуты, и клиентский PATCH поля `coins` отбивает
`users_guard.pb.js`. Суперюзера страж пропускает, поэтому выдача идёт от него:
скрипт заводит временного, начисляет и сразу удаляет.

Запуск НА СЕРВЕРЕ (там лежит бинарник PocketBase):
    python3 grant_coins.py qqggyy@bk.ru 500
    python3 grant_coins.py qqggyy@bk.ru 500 --dry-run

Локально то же самое одной строкой:
    scp tools/grant_coins.py root@77.91.95.34:/tmp/ && \
    ssh root@77.91.95.34 'python3 /tmp/grant_coins.py <почта> <монеты>'
"""

import argparse
import json
import secrets
import subprocess
import sqlite3
import sys
import urllib.error
import urllib.request

PB_DIR = "/opt/pocketbase"
DB = f"{PB_DIR}/pb_data/data.db"
API = "http://127.0.0.1:8090"
TMP_SUPERUSER = "tmp-grant@x.local"


def find_user(email: str) -> tuple:
    """id, имя и текущий баланс по почте. Регистр почты не важен."""
    with sqlite3.connect(f"file:{DB}?mode=ro", uri=True) as db:
        row = db.execute(
            "SELECT id, display_name, COALESCE(coins, 0) FROM users "
            "WHERE lower(email) = lower(?)",
            (email,),
        ).fetchone()
    if not row:
        sys.exit(f"Человека с почтой {email} в базе нет")
    return row


def api(path: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Content-Type": "application/json", "Authorization": token},
        method=method,
    )
    try:
        return json.load(urllib.request.urlopen(req))
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} → {e.code}: {e.read().decode()[:300]}")


def superuser_token() -> tuple:
    """Заводит временного суперюзера и отдаёт (токен, пароль для уборки)."""
    # Пароль без «!» и прочей пунктуации: она съедается оболочкой по дороге.
    password = "Grant" + secrets.token_hex(8) + "aA1"
    subprocess.run(
        [f"{PB_DIR}/pocketbase", "superuser", "create", TMP_SUPERUSER, password],
        cwd=PB_DIR, capture_output=True, check=True,
    )
    res = api(
        "/api/collections/_superusers/auth-with-password", "", "POST",
        {"identity": TMP_SUPERUSER, "password": password},
    )
    token = res.get("token", "")
    if not token:
        sys.exit("Суперюзер создан, а токен не выдан")
    return token


def drop_superuser() -> None:
    subprocess.run(
        [f"{PB_DIR}/pocketbase", "superuser", "delete", TMP_SUPERUSER],
        cwd=PB_DIR, capture_output=True,
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("email")
    p.add_argument("coins", type=int, help="сколько начислить (можно отрицательное)")
    p.add_argument("--dry-run", action="store_true", help="только показать, что будет")
    args = p.parse_args()

    uid, name, coins = find_user(args.email)
    print(f"{args.email} ({name or 'без имени'}): сейчас {coins}")
    if args.dry_run:
        print(f"было бы {coins + args.coins}")
        return

    token = superuser_token()
    try:
        # Баланс перечитываем перед записью: между запуском и патчем человек мог
        # получить бонус за день или потратить монеты в магазине.
        fresh = api(f"/api/collections/users/records/{uid}", token).get("coins") or 0
        res = api(
            f"/api/collections/users/records/{uid}", token, "PATCH",
            {"coins": fresh + args.coins},
        )
        print(f"стало {res['coins']}")
    finally:
        drop_superuser()


if __name__ == "__main__":
    main()
