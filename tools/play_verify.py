#!/usr/bin/env python3
"""Проверка чека Google Play. Локальная служба на 127.0.0.1:8097.

Зачем отдельной службой. Проверять покупку должен сервер: клиент присылает
`purchaseToken`, и без сверки с Google этот токен можно выдумать — тогда Plus
или монеты достаются даром. Сверку хочется делать прямо в хуке PocketBase, но
JSVM не умеет подписывать RS256, а без подписи не получить токен доступа к
Play Developer API. Поэтому подпись и поход в Google живут здесь, а хук ходит
на localhost.

Протокол:
    POST /verify  {"productId": "...", "purchaseToken": "..."}
      → 200 {"ok": true, "valid": true,  "state": 0}         покупка настоящая
      → 200 {"ok": true, "valid": false, "reason": "..."}    Google не признал
      → 200 {"ok": false, "reason": "..."}                   сверить не вышло

Разница между `valid:false` и `ok:false` важна для хука: первое — отказ
(товар не покупали), второе — наша беда (Google не ответил), и на ней ломать
покупку живому человеку нельзя.

Ключ сервисного аккаунта: /opt/play-service-account.json (тот же
play-publisher@, что публикует сборки из CI). Права выданы в Play Console.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt

KEY_PATH = os.environ.get("PLAY_KEY_PATH", "/opt/play-service-account.json")
PACKAGE = os.environ.get("PLAY_PACKAGE", "com.togetherly.love")
PORT = int(os.environ.get("PLAY_VERIFY_PORT", "8097"))
SCOPE = "https://www.googleapis.com/auth/androidpublisher"

log = logging.getLogger("play_verify")

_token: str | None = None
_token_until: float = 0.0
_lock = threading.Lock()


def access_token() -> str:
    """Токен доступа к Play API. Держим до истечения: он живёт час, а покупки
    приходят редко — просить новый на каждую было бы расточительно."""
    global _token, _token_until
    with _lock:
        if _token and time.time() < _token_until - 60:
            return _token
        key = json.load(open(KEY_PATH))
        now = int(time.time())
        assertion = jwt.encode(
            {
                "iss": key["client_email"],
                "scope": SCOPE,
                "aud": "https://oauth2.googleapis.com/token",
                "iat": now,
                "exp": now + 3600,
            },
            key["private_key"],
            algorithm="RS256",
        )
        body = urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }).encode()
        req = urllib.request.Request("https://oauth2.googleapis.com/token",
                                     data=body)
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
        _token = data["access_token"]
        _token_until = time.time() + int(data.get("expires_in", 3600))
        return _token


def verify(product_id: str, purchase_token: str) -> dict:
    """Спрашивает Google про конкретную покупку.

    purchaseState: 0 — куплено, 1 — отменено, 2 — ожидает оплаты. Засчитываем
    только ноль: у отменённой деньги вернули, у ожидающей их ещё не списали.
    """
    url = (f"https://androidpublisher.googleapis.com/androidpublisher/v3"
           f"/applications/{PACKAGE}/purchases/products/"
           f"{urllib.parse.quote(product_id)}/tokens/"
           f"{urllib.parse.quote(purchase_token)}")
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {access_token()}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        # 400 и 404 — Google не знает такой покупки: это отказ, а не наша беда.
        if e.code in (400, 404):
            return {"ok": True, "valid": False, "reason": f"google_{e.code}"}
        return {"ok": False, "reason": f"http_{e.code}"}
    except Exception as exc:
        return {"ok": False, "reason": type(exc).__name__}

    state = int(data.get("purchaseState", 1))
    return {
        "ok": True,
        "valid": state == 0,
        "state": state,
        "orderId": data.get("orderId", ""),
        "reason": "" if state == 0 else f"state_{state}",
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, payload: dict) -> None:
        raw = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self) -> None:  # noqa: N802 — имя задано базовым классом
        if self.path.rstrip("/") != "/verify":
            self._send({"ok": False, "reason": "no_such_path"})
            return
        try:
            size = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(size) or b"{}")
        except Exception:
            self._send({"ok": False, "reason": "bad_body"})
            return

        product = str(body.get("productId") or "").strip()
        token = str(body.get("purchaseToken") or "").strip()
        if not product or not token:
            self._send({"ok": False, "reason": "no_args"})
            return

        result = verify(product, token)
        log.info("%s → %s", product, result.get("reason") or "valid")
        self._send(result)

    def do_GET(self) -> None:  # noqa: N802
        self._send({"ok": True, "service": "play_verify"})

    def log_message(self, *args) -> None:
        """Свой журнал ведём сами: стандартный пишет строку на каждый запрос."""


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    log.info("проверка чеков Play слушает 127.0.0.1:%s", PORT)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
