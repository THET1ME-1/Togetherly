#!/usr/bin/env python3
"""Релей пушей в APNs.

Зачем он есть. Уведомления у нас показывает сам телефон: приложение подписано на
realtime PocketBase и рисует их через flutter_local_notifications. Пока
приложение открыто или висит в фоне — работает; стоит iOS выгрузить процесс, и
сокета нет, а значит нет и уведомлений. «Уведы с закрытым приложением не ворк» —
самая частая жалоба после выхода в App Store.

Чинится это только пушем от Apple. Подписать запрос к APNs нужно JWT на ES256, а
JSVM внутри PocketBase такого не умеет — отсюда отдельный маленький сервис рядом,
как почтовый релей для Gmail. Хуки зовут его по localhost.

Протокол простой:

    POST /push
    {"token": "<64 hex>", "title": "...", "body": "...",
     "thread": "chat", "data": {"kind": "chat"}, "sandbox": false}

    → 200 {"ok": true}
    → 4xx {"ok": false, "reason": "BadDeviceToken"}

Токен устройства присылает приложение (`users.apns_token`). Sandbox-адрес нужен
сборкам из Xcode: у них токен из песочницы, и production-шлюз отвечает
BadDeviceToken. Флаг приходит от вызывающего.
"""

import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt

KEY_ID = os.environ.get("APNS_KEY_ID", "LQ52U2LRSR")
TEAM_ID = os.environ.get("APNS_TEAM_ID", "Y2Z9V86248")
TOPIC = os.environ.get("APNS_TOPIC", "com.togetherly.love")
KEY_PATH = os.environ.get(
    "APNS_KEY_PATH", "/opt/pocketbase/keys/AuthKey_%s.p8" % KEY_ID
)
PORT = int(os.environ.get("APNS_PORT", "8096"))

PROD_HOST = "api.push.apple.com"
SANDBOX_HOST = "api.sandbox.push.apple.com"

# Apple разрешает жить провайдерскому токену час; берём с запасом, чтобы не
# попасть в отказ ExpiredProviderToken на границе.
_TOKEN_TTL = 45 * 60
_cached = {"jwt": None, "born": 0.0}


def provider_token() -> str:
    now = time.time()
    if _cached["jwt"] and now - _cached["born"] < _TOKEN_TTL:
        return _cached["jwt"]
    with open(KEY_PATH) as f:
        key = f.read()
    token = jwt.encode(
        {"iss": TEAM_ID, "iat": int(now)},
        key,
        algorithm="ES256",
        headers={"kid": KEY_ID},
    )
    _cached["jwt"] = token
    _cached["born"] = now
    return token


def send(device_token: str, payload: dict, *, sandbox: bool, push_type: str = "alert"):
    """Отдаёт (код ответа Apple, причина отказа)."""
    host = SANDBOX_HOST if sandbox else PROD_HOST
    result = subprocess.run(
        [
            "curl", "-s", "--http2", "--max-time", "15",
            "-o", "-", "-w", "\n%{http_code}",
            "-H", "apns-topic: " + TOPIC,
            "-H", "apns-push-type: " + push_type,
            "-H", "apns-priority: 10",
            "-H", "authorization: bearer " + provider_token(),
            "-d", json.dumps(payload, ensure_ascii=False),
            "https://%s/3/device/%s" % (host, device_token),
        ],
        capture_output=True,
        text=True,
        timeout=25,
    )
    out = (result.stdout or "").rsplit("\n", 1)
    body = out[0] if len(out) == 2 else ""
    code = int(out[-1] or 0)
    reason = ""
    if body:
        try:
            reason = json.loads(body).get("reason", "")
        except ValueError:
            reason = body[:120]
    return code, reason


def build_payload(req: dict) -> dict:
    alert = {"title": req.get("title") or "Togetherly"}
    body = req.get("body")
    if body:
        alert["body"] = body
    aps = {"alert": alert, "sound": "default"}
    thread = req.get("thread")
    if thread:
        aps["thread-id"] = thread
    badge = req.get("badge")
    if isinstance(badge, int):
        aps["badge"] = badge
    payload = {"aps": aps}
    data = req.get("data")
    if isinstance(data, dict):
        payload.update(data)
    return payload


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
            return self._reply(200, {"ok": True, "topic": TOPIC})
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
            code, reason = send(
                token,
                build_payload(req),
                sandbox=bool(req.get("sandbox")),
            )
        except Exception as e:  # сеть, curl, ключ — наружу отдаём причину
            return self._reply(502, {"ok": False, "reason": str(e)[:120]})

        if code == 200:
            return self._reply(200, {"ok": True})
        # Токен устройства мёртв (приложение удалили, токен сменился) — зовущий
        # должен вычистить его из профиля, иначе будем стучать вечно.
        gone = reason in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic")
        self._reply(
            200 if gone else 502,
            {"ok": False, "reason": reason, "gone": gone, "status": code},
        )

    def log_message(self, fmt, *args):
        # Журнал ведёт systemd; молчим о каждом запросе, чтобы не пухли логи.
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
