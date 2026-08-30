#!/usr/bin/env python3
"""Заводит на проде то, чем живёт приём уведомлений App Store.

Три вещи:
  • коллекция `apple_notifications` — что Apple прислала и что мы с этим
    сделали (id = notificationUUID, он же держит идемпотентность: Apple
    повторяет уведомление, пока не получит 200);
  • `iap_purchases.transaction_id` — по нему возврат находит покупку. Без
    него уведомление о возврате знает номер сделки, а мы нет;
  • `users.apple_account_token` — единственная ниточка от покупки к нашему
    пользователю. Apple кладёт в уведомление только то, что приложение
    передало при оплате; ничего другого, что указывало бы на аккаунт, в нём
    нет.

Запускать на VPS: python3 /opt/pocketbase/apply_apple_notifications.py
Повторный запуск ничего не ломает — уже заведённое пропускается.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("PB_BASE", "http://127.0.0.1:8090")
IDENTITY = os.environ.get("PB_SUPERUSER", "badzoff@gmail.com")
PASSWORD = os.environ.get("PB_PASSWORD", "")


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body,
                                 method=method or ("POST" if body else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:400]}


КОЛЛЕКЦИЯ = {
    "name": "apple_notifications",
    "type": "base",
    "fields": [
        # id = notificationUUID Apple: с дефисами, поэтому свой шаблон.
        {"name": "id", "type": "text", "primaryKey": True, "required": True,
         "system": True, "pattern": "^[A-Za-z0-9_-]+$", "min": 1, "max": 60,
         "autogeneratePattern": ""},
        {"name": "kind", "type": "text"},
        {"name": "subtype", "type": "text"},
        {"name": "product_id", "type": "text"},
        {"name": "transaction_id", "type": "text"},
        {"name": "original_transaction_id", "type": "text"},
        {"name": "account_token", "type": "text"},
        {"name": "environment", "type": "text"},
        {"name": "user_uid", "type": "text"},
        # Что сделали: granted / no_owner / refunded / ignored.
        {"name": "outcome", "type": "text"},
        {"name": "at", "type": "date"},
    ],
    "indexes": [
        "CREATE INDEX idx_apple_notif_tx ON apple_notifications (transaction_id)",
        "CREATE INDEX idx_apple_notif_at ON apple_notifications (at)",
    ],
    # Наружу не отдаём: внутри номера сделок и метки аккаунтов.
    "listRule": None, "viewRule": None,
    "createRule": None, "updateRule": None, "deleteRule": None,
}


def добавить_поле(token, коллекция, поле):
    st, col = api(f"/api/collections/{коллекция}", None, token)
    if st != 200:
        print(f"  !! {коллекция}: {st} {col}")
        return False
    if any(f["name"] == поле["name"] for f in col["fields"]):
        print(f"  · {коллекция}.{поле['name']} уже есть")
        return True
    st, res = api(f"/api/collections/{коллекция}",
                  {"fields": col["fields"] + [поле]}, token, "PATCH")
    print(f"  {'+' if st == 200 else '!!'} {коллекция}.{поле['name']}: {st} "
          f"{res.get('message', '')}")
    return st == 200


def main():
    if not PASSWORD:
        print("нужен PB_PASSWORD в окружении")
        sys.exit(1)
    st, auth = api("/api/collections/_superusers/auth-with-password",
                   {"identity": IDENTITY, "password": PASSWORD})
    if st != 200:
        print("вход суперюзера не удался:", st, auth)
        sys.exit(1)
    token = auth["token"]

    st, есть = api("/api/collections/apple_notifications", None, token)
    if st == 200:
        print("  · коллекция apple_notifications уже есть")
    else:
        st, res = api("/api/collections", КОЛЛЕКЦИЯ, token)
        print(f"  {'+' if st == 200 else '!!'} apple_notifications: {st} "
              f"{res.get('message', '')}")
        if st != 200:
            print(json.dumps(res, ensure_ascii=False)[:600])
            sys.exit(1)

    ok = добавить_поле(token, "iap_purchases",
                       {"name": "transaction_id", "type": "text"})
    ok = добавить_поле(token, "users",
                       {"name": "apple_account_token", "type": "text"}) and ok
    print("готово" if ok else "часть не применилась")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
