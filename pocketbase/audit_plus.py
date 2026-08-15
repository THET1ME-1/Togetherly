#!/usr/bin/env python3
"""Аудит Togetherly+: у всех ли, кто заплатил, доступ действительно есть.

Каналов оплаты четыре, и каждый однажды ломался молча: чек Play не сохранялся
из-за точки в первичном ключе, вебхука lava не существовало вовсе, код с нулём
монет валил роут погашения, а витринные покупки не оставляют следов нигде,
кроме почты продавца. Поэтому сверяем по всем источникам разом и печатаем тех,
у кого оплата есть, а доступа нет.

Только чтение, ничего не меняет:
    python3 audit_plus.py
"""

import json
import os
import sqlite3
import sys

DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
КЕШ_ПИСЕМ = "/opt/income/.lava_mail_cache.json"
ТОВАР_ПЛЮСА_PLAY = "togetherly_plus"

lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
lite.row_factory = sqlite3.Row

люди = {}
почты = {}
for r in lite.execute(
        "SELECT id, lower(trim(email)) AS email, plus, "
        "coalesce(plus_platform,'') AS канал FROM users"):
    люди[r["id"]] = r
    if r["email"]:
        почты.setdefault(r["email"], r)

беда = []          # (канал, кто, что известно)
ждут = []          # оплатил, но аккаунта ещё нет


def есть_плюс(uid: str) -> bool:
    ч = люди.get(uid)
    return bool(ч and ч["plus"])


# ── 1. Google Play и RuStore ────────────────────────────────────────────────
покупки = lite.execute(
    "SELECT user_uid, product_id, at FROM iap_purchases "
    "WHERE product_id = ?", (ТОВАР_ПЛЮСА_PLAY,)).fetchall()
for п in покупки:
    if not есть_плюс(п["user_uid"]):
        кто = люди.get(п["user_uid"])
        беда.append(("магазин", п["user_uid"],
                     f"почта {кто['email'] if кто else 'аккаунта нет'}, "
                     f"чек от {п['at']}"))

# ── 2. Счета lava ───────────────────────────────────────────────────────────
счета = lite.execute(
    "SELECT contract_id, lower(trim(email)) AS email, user_uid, status, "
    "coalesce(granted,0) AS выдано, coalesce(feature,'') AS ключ, created "
    "FROM lava_invoices").fetchall()
for с in счета:
    оплачен = (с["status"] or "").upper() == "COMPLETED"
    if not (оплачен or с["выдано"]):
        continue
    if с["ключ"]:
        continue                      # счёт на элемент каталога, не на Плюс
    ч = люди.get(с["user_uid"]) or почты.get(с["email"] or "")
    if ч is None:
        ждут.append(("счёт lava", с["email"], f"счёт {с['contract_id']}, {с['created']}"))
    elif not ч["plus"]:
        беда.append(("счёт lava", ч["id"],
                     f"почта {ч['email']}, счёт {с['contract_id']} ({с['status']})"))

# ── 3. Коды ─────────────────────────────────────────────────────────────────
коды = lite.execute(
    "SELECT code, plus, coalesce(feature,'') AS ключ, "
    "lower(trim(buyer_email)) AS email, coalesce(used_by,'') AS кем, created "
    "FROM redeem_codes WHERE plus = 1").fetchall()
for к in коды:
    if к["кем"]:
        if not есть_плюс(к["кем"]):
            беда.append(("код", к["кем"],
                         f"код {к['code']} погашен, а Плюса нет"))
    else:
        ч = почты.get(к["email"] or "")
        if ч is None:
            ждут.append(("код не погашен", к["email"],
                         f"код {к['code']} от {к['created']}"))
        elif not ч["plus"]:
            беда.append(("код не погашен", ч["id"],
                         f"аккаунт есть ({ч['email']}), код {к['code']} ждёт"))

# ── 4. Письма lava о продажах ───────────────────────────────────────────────
разобрано = 0
try:
    with open(КЕШ_ПИСЕМ, encoding="utf-8") as f:
        кеш = json.load(f)
    письма = кеш if isinstance(кеш, list) else кеш.get("items", [])
except (OSError, ValueError, NameError):
    письма = []
for п in письма if isinstance(письма, list) else []:
    if not isinstance(п, dict):
        continue
    почта = str(п.get("email") or "").strip().lower()
    if not почта:
        continue
    разобрано += 1
    ч = почты.get(почта)
    if ч is None:
        ждут.append(("письмо lava", почта, "покупка есть, аккаунта нет"))
    elif not ч["plus"]:
        беда.append(("письмо lava", ч["id"], f"почта {почта}, оплата письмом"))

lite.close()

всего_плюс = sum(1 for ч in люди.values() if ч["plus"])
print(f"людей с Togetherly+: {всего_плюс}")
print(f"проверено: покупок в магазине {len(покупки)}, счетов lava {len(счета)}, "
      f"кодов с Плюсом {len(коды)}, писем о продажах {разобрано}")

print(f"\nОПЛАТИЛИ, А ДОСТУПА НЕТ: {len(беда)}")
for канал, кто, что in беда:
    print(f"  [{канал}] {кто} — {что}")

print(f"\nОПЛАТИЛИ, НО В ПРИЛОЖЕНИЕ ЕЩЁ НЕ ЗАХОДИЛИ: {len(ждут)}")
for канал, кто, что in ждут:
    print(f"  [{канал}] {кто} — {что}")
if ждут:
    print("  (им доступ включится сам при первом входе — plus_pending.pb.js)")

sys.exit(1 if беда else 0)
