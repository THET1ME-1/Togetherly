"""Доходит ли до сервера телефон одного человека.

PocketBase пишет в журнал только отказы, без адреса и почты, поэтому
удачный вход и обычные запросы человека в нём не видны. Скрипт слушает
запросы к PocketBase (8090) и hotpath (8120) на всех интерфейсах и печатает
вход с его почтой и запросы с его токеном. Пароль не печатается.

Запуск на сервере (почта через окружение, чтобы не попасть в журнал юнита):
    systemd-run --unit who-reaches --property=RuntimeMaxSec=1800 \
        --setenv=WHO_MAIL=<почта> python3 -u who_reaches.py <uid>
    journalctl -u who-reaches -f -o cat

Источник 127.0.0.1 значит, что запрос пришёл через Caddy этого сервера,
10.10.0.x — через туннель с прежней точки входа.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time

person_uid = sys.argv[1]
person_mail = os.environ.get("WHO_MAIL", "").encode()

request_line = re.compile(rb"(GET|POST|PATCH|DELETE) (\S{1,160}) HTTP/1")
token_header = re.compile(rb"[Aa]uthorization: ([A-Za-z0-9_\-]+)\.([A-Za-z0-9_\-]+)\.")
identity_field = re.compile(rb'"identity"\s*:\s*"([^"]{0,80})"')
packet_source = re.compile(rb"IP (\d+\.\d+\.\d+\.\d+)\.\d+ > ")


def say(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


def token_owner_is_person(payload, known):
    # Разбор полезной нагрузки токена запоминается: у человека она одна на сессию
    if payload in known:
        return known[payload]
    try:
        raw = base64.urlsafe_b64decode(payload + b"=" * (-len(payload) % 4))
        result = json.loads(raw).get("id") == person_uid
    except Exception:
        result = False
    if len(known) > 100000:
        known.clear()
    known[payload] = result
    return result


capture = subprocess.Popen(
    ["tcpdump", "-i", "any", "-A", "-s", "0", "-l", "-nn",
     "tcp dst port 8090 or tcp dst port 8120"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
)
known_payloads = {}
current_request = b""
current_source = b""
say("слушаю", person_uid, "почта задана" if person_mail else "почта не задана")

for line in capture.stdout:
    found = packet_source.search(line)
    if found:
        current_source = found.group(1)
    found = request_line.search(line)
    if found:
        current_request = found.group(0)[:180]

    # Вход по почте: печатаем только начало адреса
    if person_mail and person_mail in line:
        identity = identity_field.search(line)
        shown = identity.group(1)[:4] + b"..." if identity else b"?"
        say("вход с его почтой", current_request.decode(errors="replace"),
            "почта", shown.decode(errors="replace"), "от", current_source.decode())

    found = token_header.search(line)
    if found and token_owner_is_person(found.group(2), known_payloads):
        say("его токен", current_request.decode(errors="replace"), "от", current_source.decode())
