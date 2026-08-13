#!/usr/bin/env python3
"""Релей пушей в FCM (Android).

Зачем он есть. До 13 августа 2026 уведомления на Android держал свой
foreground-сервис: он поднимал SSE-подписку в отдельном изоляте и жил, пока
приложение свёрнуто. Цена — строка «Togetherly на связи» в шторке у каждого
(жалоба тестера) и суточный лимит Android 14 на сервисы типа dataSync: шесть
часов, после которых сервис останавливается сам, и доставка молчит до утра.

FCM бесплатен в любом тарифе Firebase, а платный Blaze нужен только Cloud
Functions — их тут нет, шлём со своего VPS. Запрос к FCM подписывается JWT на
RS256, чего JSVM внутри PocketBase не умеет, отсюда отдельный сервис рядом —
как `apns_relay.py` для iPhone.

Протокол тот же, что у релея APNs:

    POST /push
    {"token": "<токен устройства>", "title": "...", "body": "...",
     "data": {"kind": "chat"}, "silent": false, "channel": "partner_notifications"}

    → 200 {"ok": true}
    → 200 {"ok": false, "reason": "UNREGISTERED", "gone": true}
    → 502 {"ok": false, "reason": "..."}

Мёртвый токен (приложение удалили, токен сменился) приходит с `gone: true` —
зовущий обязан вычистить его из профиля, иначе будем стучать вечно.

Содержимое переписки в Google не уходит: хук шлёт нейтральный заголовок, а текст
живое приложение забирает из PocketBase. Чистый data-only не годится — MIUI и
EMUI такие пуши глушат, и половина пар осталась бы без уведомлений вовсе.
"""

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt

PORT = int(os.environ.get("FCM_RELAY_PORT", "8100"))
KEY_PATH = os.environ.get("FCM_KEY", "/opt/pocketbase/keys/fcm-service-account.json")
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
TOKEN_URL = "https://oauth2.googleapis.com/token"

# Токен Google живёт час; берём с запасом, чтобы не отправить с протухшим.
_TOKEN_TTL = 50 * 60
_cached = {"access": "", "born": 0.0}
_account = {"email": "", "key": "", "project": ""}


def account() -> dict:
    """Ключ сервисного аккаунта с диска. Читаем один раз."""
    if not _account["email"]:
        with open(KEY_PATH) as f:
            data = json.load(f)
        _account["email"] = data["client_email"]
        _account["key"] = data["private_key"]
        _account["project"] = data["project_id"]
    return _account


def access_token() -> str:
    """OAuth-токен для FCM: свой JWT меняем у Google на access_token."""
    now = time.time()
    if _cached["access"] and now - _cached["born"] < _TOKEN_TTL:
        return _cached["access"]

    acc = account()
    assertion = jwt.encode(
        {
            "iss": acc["email"],
            "scope": SCOPE,
            "aud": TOKEN_URL,
            "iat": int(now),
            "exp": int(now) + 3600,
        },
        acc["key"],
        algorithm="RS256",
    )
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": assertion,
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=15) as r:
        got = json.loads(r.read().decode())
    _cached["access"] = got["access_token"]
    _cached["born"] = now
    return _cached["access"]


def build_message(req: dict, token: str) -> dict:
    """Запрос релея → тело FCM.

    Значения в `data` у FCM могут быть только строками: число или булево
    отбиваются как INVALID_ARGUMENT, и пуш не уходит вовсе.
    """
    data = {}
    raw = req.get("data")
    if isinstance(raw, dict):
        for k, v in raw.items():
            data[str(k)] = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)

    message = {"token": token, "data": data}

    # Тихий пуш будит приложение обновить виджеты — баннера у него нет.
    if req.get("silent"):
        message["android"] = {"priority": "high"}
        return message

    title = req.get("title") or "Togetherly"
    body = req.get("body") or ""
    message["notification"] = {"title": title, "body": body}
    android = {
        "priority": "high",
        "notification": {
            # Канал тот же, в котором приложение рисует свои уведомления
            # (`PbPushService._channelId`): иначе система заведёт второй, и
            # человек будет выключать звук дважды.
            "channel_id": req.get("channel") or "partner_notifications",
            "default_sound": True,
        },
    }
    tag = req.get("tag")
    if tag:
        # Одна пара — одна строка в шторке: новое сообщение заменяет прежнее.
        android["notification"]["tag"] = str(tag)
    message["android"] = android
    return message


def send(token: str, req: dict):
    """Отдаёт (код ответа FCM, причина отказа)."""
    acc = account()
    url = "https://fcm.googleapis.com/v1/projects/%s/messages:send" % acc["project"]
    payload = json.dumps({"message": build_message(req, token)}, ensure_ascii=False)
    request = urllib.request.Request(url, data=payload.encode(), method="POST")
    request.add_header("Authorization", "Bearer " + access_token())
    request.add_header("Content-Type", "application/json; charset=utf-8")
    try:
        with urllib.request.urlopen(request, timeout=20) as r:
            return r.status, ""
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        return e.code, error_code(raw)


def error_code(raw: str) -> str:
    """Из тела отказа FCM достать машинную причину.

    Она лежит не в `error.status`, а в `details[].errorCode` — по нему и видно
    мёртвый токен: `UNREGISTERED`.
    """
    try:
        err = json.loads(raw).get("error", {})
    except ValueError:
        return raw[:120]
    for d in err.get("details", []):
        if isinstance(d, dict) and d.get("errorCode"):
            return str(d["errorCode"])
    return str(err.get("status") or err.get("message") or "")[:120]


def token_is_gone(reason: str) -> bool:
    """Токен больше не принадлежит живому приложению — чистить из профиля."""
    return reason in ("UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, code: int, obj: dict):
        raw = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == "/health":
            try:
                return self._reply(200, {"ok": True, "project": account()["project"]})
            except Exception as e:
                return self._reply(500, {"ok": False, "reason": str(e)[:120]})
        self._reply(404, {"ok": False, "reason": "NotFound"})

    def do_POST(self):
        if self.path != "/push":
            return self._reply(404, {"ok": False, "reason": "NotFound"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, TypeError):
            return self._reply(400, {"ok": False, "reason": "BadRequest"})

        token = str(req.get("token") or "").strip()
        if not token:
            return self._reply(400, {"ok": False, "reason": "NoDeviceToken"})

        try:
            code, reason = send(token, req)
        except Exception as e:  # сеть, ключ, отказ Google — причину наружу
            return self._reply(502, {"ok": False, "reason": str(e)[:120]})

        if code == 200:
            return self._reply(200, {"ok": True})
        gone = token_is_gone(reason)
        self._reply(
            200 if gone else 502,
            {"ok": False, "reason": reason, "gone": gone, "status": code},
        )

    def log_message(self, fmt, *args):
        # Журнал ведёт systemd; молчим о каждом запросе, чтобы не пухли логи.
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
