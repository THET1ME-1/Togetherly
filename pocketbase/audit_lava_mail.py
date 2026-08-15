#!/usr/bin/env python3
"""Аудит покупок Togetherly+, пришедших письмами lava.

Витринная покупка не оставляет следов ни в счетах, ни в журнале PocketBase:
единственный свидетель — письмо продавцу. Его разбирает сторож
(`/opt/lava_mail_watch.py`), но когда аккаунта с почтой покупки ещё нет, он
пишет «аккаунта в базе нет» и оставляет письмо на потом. Дальше человек
регистрируется под этой почтой — и ничего не происходит, потому что сторож
перечитывает только новые письма.

Скрипт сводит журнал сторожа с базой и показывает, у кого оплата есть, а
Плюса нет. С `--fix` доводит дело до конца: у кого аккаунт есть — включает
Плюс, у кого нет — заводит код, который выдастся сам при первом входе
(`pb_hooks/plus_pending.pb.js`).

    python3 audit_lava_mail.py            только показать
    python3 audit_lava_mail.py --fix      выдать
"""

import argparse
import os
import re
import secrets
import sqlite3
import sys
import time

DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
ЖУРНАЛ = os.environ.get("LAVA_WATCH_LOG", "/var/log/lava_mail_watch.log")
СТРОКА = re.compile(r"^(\S+ \S+) (\S+@\S+?): (.+)$")
# исходы, которые означают «это была покупка Togetherly+»
ПОКУПКА = ("Плюс выдан", "Togetherly+ выдан", "Плюс уже есть",
           "аккаунта в базе нет", "аккаунта с почтой покупки нет",
           "эта продажа уже разобрана", "роут не ответил")
НЕ_ПЛЮС = ("донат",)


def разобрать_журнал() -> dict:
    """Последний исход по каждой почте покупателя."""
    итог = {}
    with open(ЖУРНАЛ, encoding="utf-8", errors="replace") as f:
        for строка in f:
            m = СТРОКА.match(строка.strip())
            if not m:
                continue
            когда, почта, что = m.groups()
            if any(с in что for с in НЕ_ПЛЮС):
                continue
            if not any(с in что for с in ПОКУПКА):
                continue
            итог[почта.strip().lower()] = (когда, что)
    return итог


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()

    покупки = разобрать_журнал()
    lite = sqlite3.connect(DB, timeout=60)
    lite.row_factory = sqlite3.Row

    люди = {}
    for r in lite.execute("SELECT id, lower(trim(email)) AS email, plus FROM users"):
        if r["email"]:
            люди.setdefault(r["email"], r)
    коды = {}
    for r in lite.execute(
            "SELECT lower(trim(buyer_email)) AS email, lower(trim(coalesce(given_to,''))) "
            "AS запасной, code, coalesce(used_by,'') AS кем "
            "FROM redeem_codes WHERE plus = 1"):
        коды.setdefault(r["email"], r)
        if r["запасной"]:
            коды.setdefault(r["запасной"], r)

    # Домен в платеже и домен входа сплошь и рядом разные: платят с mail.ru, а
    # заходят с gmail. Часть до собачки при этом совпадает, и если она длинная,
    # случайных двойников не бывает — то же правило, что в plus_pending.pb.js.
    def часть(a: str) -> str:
        return (a or "").split("@")[0]

    по_части = {}
    for почта, ч in люди.items():
        к = часть(почта)
        if len(к) >= 12:
            по_части.setdefault(к, ч)
    коды_по_части = {}
    for почта, r in коды.items():
        к = часть(почта)
        if len(к) >= 12:
            коды_по_части.setdefault(к, r)

    есть, надо_выдать, надо_код = [], [], []
    for почта, (когда, что) in sorted(покупки.items()):
        ч = люди.get(почта) or по_части.get(часть(почта))
        if ч and ч["plus"]:
            есть.append(почта)
        elif ч:
            надо_выдать.append((почта, ч["id"], когда))
        elif почта in коды or часть(почта) in коды_по_части:
            есть.append(почта)          # аккаунта нет, но код уже ждёт
        else:
            надо_код.append((почта, когда))

    print(f"покупок Togetherly+ по письмам: {len(покупки)}")
    print(f"  доступ есть или код ждёт: {len(есть)}")
    print(f"  аккаунт есть, а Плюса нет: {len(надо_выдать)}")
    print(f"  аккаунта нет и кода нет:   {len(надо_код)}")

    for почта, uid, когда in надо_выдать:
        print(f"    [нет доступа] {почта} — {uid}, покупка {когда}")
    for почта, когда in надо_код:
        print(f"    [ждёт входа]  {почта} — покупка {когда}")

    if args.fix and (надо_выдать or надо_код):
        сейчас_мс = int(time.time() * 1000)
        сейчас = time.strftime("%Y-%m-%d %H:%M:%S.000Z", time.gmtime())
        for почта, uid, _ in надо_выдать:
            lite.execute(
                "UPDATE users SET plus = 1, plus_platform = 'lava', "
                "last_plus_grant_ms = ?, updated = ? WHERE id = ? AND plus = 0",
                (сейчас_мс, сейчас, uid))
        for почта, _ in надо_код:
            lite.execute(
                "INSERT INTO redeem_codes (id, code, plus, coins, buyer_email, "
                "sku, order_key, created, updated) VALUES (?,?,?,?,?,?,?,?,?)",
                (secrets.token_hex(7) + "b",
                 "TG" + "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
                                for _ in range(8)),
                 1, 0, почта, "письмо lava",
                 "MAIL" + secrets.token_hex(6).upper(), сейчас, сейчас))
        lite.commit()
        print(f"\nвыдано Плюсов: {len(надо_выдать)}, заведено кодов: {len(надо_код)}")
        print("коды выдадутся сами при первом входе под этой почтой")
    elif надо_выдать or надо_код:
        print("\n(прогон без --fix, ничего не изменено)")

    lite.close()
    sys.exit(1 if (надо_выдать or надо_код) and not args.fix else 0)


if __name__ == "__main__":
    main()
