#!/usr/bin/env python3
"""Проверки релея APNs, не требующие ни сети, ни ключа.

Запуск: python3 pocketbase/apns/test_apns_relay.py

Сеть проверяется отдельно, на сервере: отправка на заведомо неверный токен
устройства должна получить от Apple BadDeviceToken — это доказывает, что ключ,
JWT и topic приняты. Если ключ не тот, ответ будет InvalidProviderToken.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import apns_relay  # noqa: E402

failures = []


def check(name, condition, extra=""):
    mark = "  ✓ " if condition else "  ✗ "
    print(mark + name, extra)
    if not condition:
        failures.append(name)


payload = apns_relay.build_payload({"title": "Аня", "body": "Привет", "thread": "chat"})
check("заголовок и текст на месте",
      payload["aps"]["alert"] == {"title": "Аня", "body": "Привет"},
      str(payload["aps"]["alert"]))
check("ветка уходит в thread-id", payload["aps"].get("thread-id") == "chat")
check("звук по умолчанию есть", payload["aps"].get("sound") == "default")

# Пустой текст бывает у голосового и у реакции: заголовок остаётся, тела нет.
short = apns_relay.build_payload({"title": "Аня"})
check("без текста тело не подставляется", "body" not in short["aps"]["alert"])

# Имя приложения — последняя защита от пустого баннера.
fallback = apns_relay.build_payload({})
check("без заголовка подставляется имя приложения",
      fallback["aps"]["alert"]["title"] == "Togetherly")

# Полезная нагрузка приложения едет рядом с aps, а не внутри него: по `kind`
# приложение решает, какой экран открыть по тапу.
withdata = apns_relay.build_payload({"title": "т", "data": {"kind": "miss"}})
check("свои поля лежат рядом с aps", withdata.get("kind") == "miss")

badge = apns_relay.build_payload({"title": "т", "badge": 3})
check("счётчик на иконке проходит", badge["aps"].get("badge") == 3)
notbadge = apns_relay.build_payload({"title": "т", "badge": "3"})
check("строка вместо числа в счётчик не попадает",
      "badge" not in notbadge["aps"])

# ── Нативный вход через Google (09.11.2026) ──────────────────────────────────
# Ключи Google подменяем своим: подпись, аудитория, издатель и срок проверяются
# по-настоящему, без сети.
import time  # noqa: E402

import jwt  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import rsa  # noqa: E402

_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class _FakeJwk:
    def get_signing_key_from_jwt(self, token):
        return type("K", (), {"key": _key.public_key()})()


apns_relay._google_jwk_client = _FakeJwk()


def google_token(**over):
    claims = {
        "iss": "https://accounts.google.com",
        "aud": apns_relay.GOOGLE_AUDIENCES[0],
        "sub": "1234567890",
        "email": "Anya@Gmail.com",
        "email_verified": True,
        "name": "Аня",
        "picture": "https://lh3.googleusercontent.com/a/x",
        "exp": int(time.time()) + 600,
        "iat": int(time.time()),
    }
    claims.update(over)
    return jwt.encode(claims, _key, algorithm="RS256")


ok = apns_relay.verify_google_identity(google_token())
check("Google: свой токен принят", ok.get("sub") == "1234567890")


def refused(token):
    try:
        apns_relay.verify_google_identity(token)
        return False
    except Exception:
        return True


check("Google: чужой клиент отвергнут", refused(google_token(aud="чужой.apps.googleusercontent.com")))
check("Google: чужой издатель отвергнут", refused(google_token(iss="https://evil.example")))
check("Google: просроченный отвергнут", refused(google_token(exp=int(time.time()) - 10)))
check("Google: неподтверждённая почта отвергнута", refused(google_token(email_verified=False)))
check("Google: издатель без https тоже свой",
      apns_relay.verify_google_identity(google_token(iss="accounts.google.com")).get("sub") == "1234567890")

print()
if failures:
    print("ЕСТЬ ПРОВАЛЫ:", ", ".join(failures))
    sys.exit(1)
print("ВСЁ ХОРОШО")
