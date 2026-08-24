"""Тонкая обёртка над App Store Connect API: подпись JWT и запросы.

Ключ и идентификаторы — из ~/keys, см. память togetherly_asc_api_access.
"""

import json
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


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(path, method="GET", body=None, tok=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + (tok or token()))
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=40) as res:
            raw = res.read().decode()
            return res.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:500]}


def errors(payload):
    """Короткое человеческое описание отказа Apple."""
    out = []
    for err in (payload or {}).get("errors", []):
        out.append(f"{err.get('title')}: {err.get('detail')}")
    return out or [json.dumps(payload)[:300]]
