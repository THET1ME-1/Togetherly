#!/usr/bin/env python3
"""Идемпотентно применяет схему PocketBase (Этап 3 миграции Firebase→PocketBase).

Делает две вещи:
  1) импортирует базовые коллекции из collections_schema.json
     (PUT /api/collections/import, deleteMissing:false — только создаёт/мёрджит);
  2) дописывает в дефолтную auth-коллекцию `users` кастомные Firebase-поля
     (PATCH — пересоздавать auth-коллекцию нельзя) + уникальный индекс firebase_uid.

Креды берутся из окружения (НЕ хардкодить в репо):
    PB_URL=https://togetherly.duckdns.org   (по умолчанию)
    PB_EMAIL=...  PB_PASSWORD=...            (суперюзер)

Запуск:
    PB_EMAIL=badzoff@gmail.com PB_PASSWORD=*** python3 pocketbase/apply_schema.py
"""
import json
import os
import urllib.request
import urllib.error

PB_URL = os.environ.get("PB_URL", "https://togetherly.duckdns.org").rstrip("/")
PB_EMAIL = os.environ["PB_EMAIL"]
PB_PASSWORD = os.environ["PB_PASSWORD"]
HERE = os.path.dirname(__file__)


def api(method, path, token=None, body=None):
    url = PB_URL + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        return e.code, (json.loads(raw) if raw else {})


def auth():
    st, d = api("POST", "/api/collections/_superusers/auth-with-password",
                body={"identity": PB_EMAIL, "password": PB_PASSWORD})
    if st != 200:
        raise SystemExit(f"auth failed: {st} {d}")
    return d["token"]


# ── кастомные поля users (Firebase-профиль). id остаётся авто-PB; Firebase UID
#    хранится в firebase_uid (uniq) — связи в данных ссылаются на него строкой. ──
def text(n):
    return {"name": n, "type": "text", "required": False}

def number(n):
    return {"name": n, "type": "number", "required": False}

def boolean(n):
    return {"name": n, "type": "bool", "required": False}

def date(n):
    return {"name": n, "type": "date", "required": False}

def jsonf(n):
    return {"name": n, "type": "json", "required": False, "maxSize": 5000000}

USERS_CUSTOM = [
    text("firebase_uid"), text("display_name"), text("avatar_url"),
    text("gender"), date("birth_date"), number("coins"),
    jsonf("owned_themes"), jsonf("owned_icons"), jsonf("owned_features"),
    jsonf("granted_badges"), text("badge"), text("pair_id"), jsonf("pair_ids"),
    text("invite_code"), text("fcm_token"), jsonf("fcm_tokens"),
    boolean("notif_miss_you"), boolean("notif_new_memory"),
    boolean("notif_mood"), boolean("notif_chat"), jsonf("solo_timers"),
    date("updated_at"), date("last_daily_bonus_at"),
    date("last_memory_reward_at"), text("ad_rewards_date"),
    number("ad_rewards_today"), boolean("dev_coins_granted"),
    boolean("partner_invite_reward_granted"),
    jsonf("partner_invite_rewarded_keys"), jsonf("mood_streak_rewards"),
]
USERS_FB_UID_INDEX = (
    "CREATE UNIQUE INDEX `idx_users_firebase_uid` ON `users` (`firebase_uid`) "
    "WHERE `firebase_uid` != ''"
)


def main():
    token = auth()

    # 1) импорт базовых коллекций
    with open(os.path.join(HERE, "collections_schema.json"), encoding="utf-8") as f:
        schema = json.load(f)
    st, d = api("PUT", "/api/collections/import", token, schema)
    print(f"[import] HTTP {st}" + ("" if st == 204 else f"  {json.dumps(d, ensure_ascii=False)[:400]}"))

    # 2) users: дописать недостающие поля (идемпотентно) + индекс firebase_uid
    st, users = api("GET", "/api/collections/users", token)
    if st != 200:
        raise SystemExit(f"get users failed: {st} {users}")
    have = {f["name"] for f in users["fields"]}
    added = [f for f in USERS_CUSTOM if f["name"] not in have]
    if added:
        users["fields"] += added
    idx = users.get("indexes", [])
    if not any("idx_users_firebase_uid" in s for s in idx):
        idx.append(USERS_FB_UID_INDEX)
    users["indexes"] = idx
    st, d = api("PATCH", f"/api/collections/{users['id']}", token, users)
    print(f"[users] HTTP {st}  добавлено полей={len(added)}: {[f['name'] for f in added]}")
    if st != 200:
        print("  ОШИБКА:", json.dumps(d, ensure_ascii=False)[:500])


if __name__ == "__main__":
    main()
