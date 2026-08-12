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

print()
if failures:
    print("ЕСТЬ ПРОВАЛЫ:", ", ".join(failures))
    sys.exit(1)
print("ВСЁ ХОРОШО")
