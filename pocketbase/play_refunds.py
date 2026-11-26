#!/usr/bin/env python3
"""Возвраты Google Play: снять оплаченное и сообщить владельцу.

Уведомлений Play о возвратах (RTDN) у нас нет, и до 26.11.2026 возврат не
видел никто: пара, вернувшая деньги за Плюс и за подарок 22–23 ноября, четыре
дня пользовалась им даром. Теперь раз в час (крон) скрипт берёт у Google
список возвращённых покупок (`voidedpurchases`) за 30 дней и разбирает те,
которых ещё нет в `pb_data/.play_refunds`:

* `togetherly_plus` — у плательщика снимается Плюс, если он пришёл из Play и
  другой непогашенной покупки Плюса у него нет;
* `togetherly_plus_gift` — Плюс снимается у партнёра, которому ушёл этот
  подарок (`plus_platform = gift`, выдан не раньше покупки), если после
  него подарков в паре не было;
* всё остальное (монеты, чек без записи, неясный получатель) — только
  сообщение: решает владелец.

Каждый разобранный возврат дописывается строкой в `.play_refunds` (по ней
`audit_plus.py` не считает покупку «оплачено, а доступа нет»), владельцу уходит
сообщение в Telegram через воркер приёмной (`/notify`).

    python3 play_refunds.py           # разобрать и снять
    python3 play_refunds.py --dry     # только показать, что было бы
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass

PACKAGE = "com.togetherly.love"
DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
REFUNDS = os.environ.get("PLAY_REFUNDS", "/opt/pocketbase/pb_data/.play_refunds")
KEY = os.environ.get("PLAY_KEY", "/opt/play-service-account.json")
PB = os.environ.get("PB_URL", "http://127.0.0.1:8090")
PB_DIR = os.environ.get("PB_DIR", "/opt/pocketbase")
SUPPORT_ENV = os.environ.get("SUPPORT_ENV", "/opt/support/env")
PLUS = "togetherly_plus"
GIFT = "togetherly_plus_gift"
DAY_MS = 86_400_000
# Подарок выдаётся, когда приложение донесёт чек: секунды или минуты после
# покупки. Выдача раньше покупки — это другой подарок.
GIFT_EARLY_MS = 60_000


@dataclass(frozen=True)
class Purchase:
    id: str
    user_uid: str
    product: str
    at_ms: int


@dataclass(frozen=True)
class User:
    uid: str
    plus: bool
    platform: str
    granted_ms: int
    groups: tuple[str, ...]


@dataclass(frozen=True)
class Action:
    kind: str            # revoke — снять Плюс, manual — решает владелец, done — снимать нечего
    uid: str
    purchase: Purchase
    why: str


def plan(voided: list[Purchase], purchases: dict[str, Purchase],
         users: dict[str, User], groups: dict[str, list[str]]) -> list[Action]:
    """Что делать с каждым возвратом. Чистая функция, под тестами."""
    actions = []
    for p in voided:
        if p.id not in purchases:
            actions.append(Action("manual", "", p, "чека нет в iap_purchases"))
            continue
        if p.product == PLUS:
            actions.append(_plan_plus(p, purchases, users))
        elif p.product == GIFT:
            actions.append(_plan_gift(p, purchases, users, groups))
        else:
            actions.append(Action("manual", p.user_uid, p, f"товар {p.product}: Плюс не снимается"))
    return actions


def _plan_plus(p: Purchase, purchases: dict[str, Purchase], users: dict[str, User]) -> Action:
    u = users.get(p.user_uid)
    if u is None:
        return Action("manual", p.user_uid, p, "аккаунта нет")
    if not u.plus:
        return Action("done", u.uid, p, "Плюса уже нет")
    if u.platform != "play":
        return Action("manual", u.uid, p, f"Плюс сейчас из канала «{u.platform or 'неизвестно'}»")
    again = [q for q in purchases.values()
             if q.user_uid == u.uid and q.product == PLUS and q.id != p.id and q.at_ms > p.at_ms]
    if again:
        return Action("manual", u.uid, p, "после возврата купил Плюс снова")
    return Action("revoke", u.uid, p, "Плюс себе")


def _plan_gift(p: Purchase, purchases: dict[str, Purchase], users: dict[str, User],
               groups: dict[str, list[str]]) -> Action:
    payer = users.get(p.user_uid)
    if payer is None:
        return Action("manual", p.user_uid, p, "плательщика нет")
    partners = {m for g in payer.groups for m in groups.get(g, []) if m != payer.uid}
    candidates = [users[m] for m in sorted(partners)
                  if m in users and users[m].plus and users[m].platform == "gift"
                  and users[m].granted_ms >= p.at_ms - GIFT_EARLY_MS]
    if not candidates:
        if any(m in users and users[m].plus for m in partners):
            return Action("manual", payer.uid, p, "у партнёра Плюс не от этого подарка")
        return Action("done", payer.uid, p, "у партнёров Плюса нет")
    if len(candidates) > 1:
        return Action("manual", payer.uid, p, "подарок мог уйти нескольким")
    later = [q for q in purchases.values()
             if q.product == GIFT and q.id != p.id and q.at_ms > p.at_ms
             and (q.user_uid in partners or q.user_uid == payer.uid)]
    if later:
        return Action("manual", candidates[0].uid, p, "после этого в паре был ещё подарок")
    return Action("revoke", candidates[0].uid, p, f"подарок от {payer.uid}")


# ── Google Play ──────────────────────────────────────────────────────────────


def google_token() -> str:
    import jwt  # PyJWT, есть на сервере

    key = json.load(open(KEY))
    now = int(time.time())
    assertion = jwt.encode(
        {"iss": key["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
         "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now + 600},
        key["private_key"], algorithm="RS256")
    body = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": assertion}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=body),
                                timeout=30) as res:
        return json.load(res)["access_token"]


def voided_purchases(token: str) -> list[dict]:
    # Google отдаёт возвраты не старше 30 дней; ровно 30 он отклоняет (400).
    start = int(time.time() * 1000) - 29 * DAY_MS
    url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
           f"/purchases/voidedpurchases?startTime={start}&maxResults=1000")
    out, page = [], None
    while True:
        with urllib.request.urlopen(urllib.request.Request(
                url + (f"&token={page}" if page else ""), headers={"Authorization": f"Bearer {token}"}),
                timeout=60) as res:
            d = json.load(res)
        out += d.get("voidedPurchases", [])
        page = (d.get("tokenPagination") or {}).get("nextPageToken")
        if not page:
            return out


# ── база ─────────────────────────────────────────────────────────────────────


def _ms(text: str) -> int:
    from datetime import datetime, timezone
    try:
        return int(datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=timezone.utc).timestamp() * 1000)
    except ValueError:
        return 0


def load_db(uids_hint: set[str]) -> tuple[dict[str, Purchase], dict[str, User], dict[str, list[str]]]:
    lite = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=30)
    lite.row_factory = sqlite3.Row
    purchases = {r["id"]: Purchase(r["id"], r["user_uid"] or "", r["product_id"] or "", _ms(r["at"] or ""))
                 for r in lite.execute("SELECT id, user_uid, product_id, at FROM iap_purchases")}
    users: dict[str, User] = {}
    groups: dict[str, list[str]] = {}

    def load_users(ids: set[str]) -> None:
        if not ids:
            return
        for r in lite.execute(f"SELECT id, plus, coalesce(plus_platform,'') AS platform, "
                              f"coalesce(last_plus_grant_ms,0) AS granted, coalesce(group_ids,'[]') AS g "
                              f"FROM users WHERE id IN ({','.join('?' * len(ids))})", tuple(ids)):
            users[r["id"]] = User(r["id"], bool(r["plus"]), r["platform"], int(r["granted"] or 0),
                                  tuple(json.loads(r["g"] or "[]")))

    # Плательщики, их пары и все участники этих пар (получатели подарков).
    load_users(set(uids_hint))
    gids = {g for u in users.values() for g in u.groups}
    if gids:
        for r in lite.execute(f"SELECT id, members FROM groups WHERE disbanded = 0 AND id IN "
                              f"({','.join('?' * len(gids))})", tuple(gids)):
            groups[r["id"]] = json.loads(r["members"] or "[]")
    load_users({m for ms in groups.values() for m in ms} - set(users))
    lite.close()
    return purchases, users, groups


def handled() -> set[str]:
    try:
        with open(REFUNDS, encoding="utf-8") as f:
            return {line.split()[0] for line in f if line.strip() and not line.startswith("#")}
    except OSError:
        return set()


# ── снятие Плюса и сообщение ─────────────────────────────────────────────────


def revoke(uids: list[str]) -> None:
    """Снимает Плюс временным суперюзером: поле закрыто стражем, клиенту его
    не изменить. Суперюзер удаляется в любом случае."""
    mail = f"refunds-{int(time.time())}@togetherly.local"
    password = os.urandom(16).hex()
    subprocess.run(["./pocketbase", "superuser", "create", mail, password], cwd=PB_DIR,
                   check=True, capture_output=True)
    try:
        def call(method, path, body, token=None):
            req = urllib.request.Request(PB + path, method=method, data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json",
                                                  **({"Authorization": token} if token else {})})
            with urllib.request.urlopen(req, timeout=30) as res:
                return json.load(res)
        token = call("POST", "/api/collections/_superusers/auth-with-password",
                     {"identity": mail, "password": password})["token"]
        for uid in uids:
            call("PATCH", f"/api/collections/users/records/{uid}", {"plus": False, "plus_platform": ""}, token)
    finally:
        subprocess.run(["./pocketbase", "superuser", "delete", mail], cwd=PB_DIR, capture_output=True)


def notify(text: str) -> None:
    env = {}
    try:
        for line in open(SUPPORT_ENV, encoding="utf-8"):
            if "=" in line and not line.startswith("#"):
                k, v = line.strip().split("=", 1)
                env[k] = v.strip().strip('"')
    except OSError:
        pass
    url = env.get("WORKER_URL", "https://togetherly-bug-bot.badzoff.workers.dev").rstrip("/")
    secret = env.get("SUPPORT_SECRET", "")
    if not secret:
        print("сообщение не ушло: нет SUPPORT_SECRET")
        return
    try:
        # Своя подпись обязательна: стандартную «Python-urllib» Cloudflare
        # отбивает ошибкой 1010 (403) ещё до воркера.
        urllib.request.urlopen(urllib.request.Request(
            f"{url}/notify", data=json.dumps({"text": text}).encode(),
            headers={"Content-Type": "application/json", "X-Support-Secret": secret,
                     "User-Agent": "togetherly-play-refunds/1.0"}), timeout=15)
    except Exception as err:  # сообщение не повод сорвать снятие
        print(f"сообщение не ушло: {err}")


def main() -> int:
    dry = "--dry" in sys.argv
    voided = voided_purchases(google_token())
    seen = handled()
    fresh = []
    for v in voided:
        pid = hashlib.sha256(v["purchaseToken"].encode()).hexdigest()
        if pid not in seen:
            fresh.append((pid, v))
    if not fresh:
        print("новых возвратов нет")
        return 0
    purchases, _, _ = load_db(set())
    hint = {purchases[pid].user_uid for pid, _ in fresh if pid in purchases}
    purchases, users, groups = load_db(hint)
    voided_p = [purchases.get(pid) or Purchase(pid, "", "", 0) for pid, _ in fresh]
    actions = plan(voided_p, purchases, users, groups)
    orders = {pid: v.get("orderId", "?") for pid, v in fresh}
    lines = []
    for a in actions:
        what = {"revoke": f"Плюс снят у {a.uid}", "done": "снимать нечего",
                "manual": "НЕ снято, решай сам"}[a.kind]
        lines.append(f"• {orders[a.purchase.id]} ({a.purchase.product or 'чек не найден'}): {what} — {a.why}")
    print("\n".join(lines))
    if dry:
        return 0
    to_revoke = [a.uid for a in actions if a.kind == "revoke"]
    if to_revoke:
        revoke(to_revoke)
    with open(REFUNDS, "a", encoding="utf-8") as f:
        for a in actions:
            f.write(f"{a.purchase.id} {orders[a.purchase.id]} {a.purchase.product or '-'} "
                    f"{a.kind} {a.uid or '-'} {time.strftime('%Y-%m-%d %H:%M')}\n")
    notify("Возврат Google Play:\n" + "\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
