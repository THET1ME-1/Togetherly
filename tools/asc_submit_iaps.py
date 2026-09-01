#!/usr/bin/env python3
"""Кладёт готовые к подаче покупки в заявку на ревью.

Воркфлоу `ios-submit.yml` отправляет только сборку — слова `inAppPurchase` в
нём нет, поэтому товары не поедут на ревью сами по себе никогда. Этот скрипт
доносит их: находит (или заводит) заявку и добавляет в неё каждый товар в
состоянии READY_TO_SUBMIT.

    python3 tools/asc_submit_iaps.py            # показать, что будет сделано
    python3 tools/asc_submit_iaps.py --commit   # добавить и отправить заявку
"""
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

ISSUER = "2872ead5-19a2-4dcc-b2c0-88e7ed59d743"
KEY_ID = "XU8YHQFQAX"
KEY_PATH = Path.home() / "keys" / f"AuthKey_{KEY_ID}.p8"
APP_ID = "6781019737"
BASE = "https://api.appstoreconnect.apple.com"
COMMIT = "--commit" in sys.argv


def token() -> str:
    return jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


TOK = token()


def call(method: str, path: str, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Authorization", "Bearer " + TOK)
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:300].decode(errors="replace")}


def main() -> int:
    _, iaps = call("GET", f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=50")
    ready = [
        p for p in iaps.get("data", [])
        if p["attributes"].get("state") == "READY_TO_SUBMIT"
    ]
    if not ready:
        print("готовых к подаче товаров нет")
        return 0
    print("готовы к подаче:")
    for p in ready:
        print("  ", p["attributes"]["productId"])

    # Версия покупки — именно её кладут в заявку, а не сам товар.
    # Версия покупки живёт по /v2/…/versions — путь v1 отвечает PATH_ERROR.
    versions = {}
    for p in ready:
        _, vs = call("GET", f'/v2/inAppPurchases/{p["id"]}/versions?limit=1')
        items = vs.get("data") or []
        if items:
            versions[p["attributes"]["productId"]] = items[0]["id"]
    print("\nверсии покупок:", json.dumps(versions, ensure_ascii=False))

    _, subs = call(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={APP_ID}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&limit=5",
    )
    sub = (subs.get("data") or [None])[0]
    if sub:
        print(f'\nживая заявка: {sub["id"]} ({sub["attributes"].get("state")})')
    else:
        print("\nживой заявки нет — её создаёт воркфлоу вместе со сборкой")
        if not COMMIT:
            return 0
        code, made = call("POST", "/v1/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        })
        if code >= 300:
            print("не вышло создать заявку:", code, made)
            return 1
        sub = made["data"]
        print("создана заявка", sub["id"])

    if not COMMIT:
        print("\nсухой прогон: с --commit товары уедут в эту заявку")
        return 0

    for product, version_id in versions.items():
        code, res = call("POST", "/v1/reviewSubmissionItems", {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": sub["id"]}
                    },
                    "inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": version_id}
                    },
                },
            }
        })
        print(f"  {product}: {code} {'ок' if code < 300 else res}")

    code, res = call("PATCH", f'/v1/reviewSubmissions/{sub["id"]}', {
        "data": {
            "type": "reviewSubmissions",
            "id": sub["id"],
            "attributes": {"submitted": True},
        }
    })
    print(f"\nотправка заявки: {code} {'ок' if code < 300 else res}")
    return 0 if code < 300 else 1


if __name__ == "__main__":
    raise SystemExit(main())
