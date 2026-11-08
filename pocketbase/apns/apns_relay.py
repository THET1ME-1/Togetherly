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
import queue
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt

# Второе дело этого сервиса — проверка нативного входа через Apple.
#
# Вход через веб-страницу отказывает у части людей: системный браузер не может
# загрузить appleid.apple.com, и за сутки таких обрывов 77 против 33 удачных
# входов на 57 разных телефонах. Нативный вход браузера не открывает вовсе, но
# отдаёт подписанный Apple identityToken, и его надо проверить: подпись по JWKS
# Apple, аудитория, срок, nonce. RS256 и JWKS в JSVM PocketBase недоступны,
# поэтому проверка живёт здесь, рядом с подписью пушей.
APPLE_JWKS = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"
# Нативный вход приходит с bundle id, вход через веб — с Services ID. Один и тот
# же человек в обоих случаях получает один `sub`, поэтому старые аккаунты
# находятся по нему без переносов.
APPLE_AUDIENCES = [
    a.strip()
    for a in os.environ.get(
        "APPLE_AUDIENCES", "com.togetherly.love,com.togetherly.love.signin"
    ).split(",")
    if a.strip()
]

_jwk_client = None


def verify_apple_identity(token: str, nonce: str = "") -> dict:
    """Возвращает разобранные утверждения токена или бросает исключение."""
    global _jwk_client
    if _jwk_client is None:
        _jwk_client = jwt.PyJWKClient(APPLE_JWKS, cache_keys=True)
    signing_key = _jwk_client.get_signing_key_from_jwt(token)
    claims = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=APPLE_AUDIENCES,
        issuer=APPLE_ISSUER,
    )
    if nonce:
        # Nonce защищает от переигрывания чужого токена: приложение шлёт сырое
        # значение, а в токене лежит его SHA-256 — сверяет вызывающий.
        if str(claims.get("nonce") or "") != nonce:
            raise ValueError("nonce не совпал")
    if not claims.get("sub"):
        raise ValueError("в токене нет sub")
    return claims


# ── Нативный вход через Google (09.11.2026) ────────────────────────────────────
#
# Вход через страницу Google рвался: Google просит подтвердить личность ключом
# доступа, человек уходит в другое приложение, Android закрывает соединение, по
# которому PocketBase ждёт ответа, и страница отвечает «Auth failed». На Android
# вход теперь берёт системное окно выбора аккаунта, а приложение присылает
# idToken. Аудитория — веб-клиент Google, тот же, что у входа через страницу в
# PocketBase: так `sub` у человека тот же, и прежние аккаунты находятся.
GOOGLE_JWKS = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"]
GOOGLE_AUDIENCES = [
    a.strip()
    for a in os.environ.get(
        "GOOGLE_AUDIENCES",
        # Веб-клиент (Android присылает токен на него) и клиент iPhone.
        "941141989934-tsglnvua139egis1oajaovb2sfgd81cf.apps.googleusercontent.com,"
        "941141989934-213e5lei669lppqe72lo1bnc7o6tsaqg.apps.googleusercontent.com",
    ).split(",")
    if a.strip()
]

_google_jwk_client = None


def verify_google_identity(token: str) -> dict:
    """Утверждения idToken Google или исключение: подпись, аудитория, издатель,
    срок и подтверждённая почта."""
    global _google_jwk_client
    if _google_jwk_client is None:
        _google_jwk_client = jwt.PyJWKClient(GOOGLE_JWKS, cache_keys=True)
    signing_key = _google_jwk_client.get_signing_key_from_jwt(token)
    claims = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=GOOGLE_AUDIENCES,
        options={"verify_iss": False},
    )
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise ValueError("чужой издатель")
    if not claims.get("sub"):
        raise ValueError("в токене нет sub")
    # По почте находим прежний аккаунт, поэтому неподтверждённую не берём.
    if str(claims.get("email_verified", "")).lower() != "true":
        raise ValueError("почта не подтверждена")
    return claims

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


def send(device_token: str, payload: dict, *, sandbox: bool, push_type: str = "alert",
         topic: str = ""):
    """Отдаёт (код ответа Apple, причина отказа).

    Тихий пуш (`background`) Apple принимает ТОЛЬКО с приоритетом 5: с 10 он
    отвечает отказом, а не будит приложение. Этим пушем мы обновляем виджеты
    на закрытом телефоне, поэтому цена ошибки — застывшее фото у партнёра.
    """
    host = SANDBOX_HOST if sandbox else PROD_HOST
    priority = "5" if push_type == "background" else "10"
    result = subprocess.run(
        [
            "curl", "-s", "--http2", "--max-time", "15",
            "-o", "-", "-w", "\n%{http_code}",
            # Тема — это bundle id приложения. Ключ APNs выдан НА КОМАНДУ, а
            # не на приложение, поэтому одним релеем обслуживаются оба:
            # Togetherly и Wallet (com.togetherly.money). Пусто — прежняя тема.
            "-H", "apns-topic: " + (topic or TOPIC),
            "-H", "apns-push-type: " + push_type,
            "-H", "apns-priority: " + priority,
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
    # Тихий пуш: ни звука, ни баннера — только «проснись и обнови данные».
    # Нужен виджетам: фоновых обновлений у WidgetKit нет, и без этого фото
    # партнёра доезжало только при следующем открытии приложения.
    if req.get("silent"):
        payload = {"aps": {"content-available": 1}}
        data = req.get("data")
        if isinstance(data, dict):
            payload.update(data)
        return payload

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



# ── Отправка в фоне ────────────────────────────────────────────────────────────
#
# Раньше хук PocketBase ждал, пока Apple ответит: полсекунды в хороший день и до
# десяти по таймауту. Ждал не сервер — ждал человек, потому что пуш отправляется
# внутри его же запроса на сохранение. Вечером 13 августа 2026 запись в базу
# висела по тридцать секунд именно из-за этого, а сама вставка занимает пять
# сотых миллисекунды.
#
# Теперь запрос кладётся в очередь и подтверждается сразу, а отправкой заняты
# отдельные потоки. Проверочные пуши (`thread: "test"` из /api/apns/test) идут
# по-старому, синхронно: там ответ Apple и есть весь смысл вызова.
QUEUE_MAX = int(os.environ.get("APNS_QUEUE_MAX", "20000"))
WORKERS = int(os.environ.get("APNS_WORKERS", "12"))
DEAD_TOKENS_FILE = os.environ.get(
    "APNS_DEAD_TOKENS", "/opt/pocketbase/pb_data/.dead_tokens.jsonl")

_outbox: "queue.Queue[dict]" = queue.Queue(maxsize=QUEUE_MAX)
_dead_lock = threading.Lock()
_stats = {"queued": 0, "sent": 0, "failed": 0, "dropped": 0, "gone": 0}


def remember_dead_token(token: str, reason: str, kind: str = "apns") -> None:
    """Мёртвый токен: вычистит его из профилей отдельный крон.

    Синхронный ответ раньше сообщал хуку `gone`, и тот стирал токен сам. В
    фоновой отправке отвечать уже некому, поэтому складываем находку в файл —
    `tools/clean_dead_tokens.py` разберёт.
    """
    try:
        with _dead_lock:
            with open(DEAD_TOKENS_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(
                    {"token": token, "reason": reason, "kind": kind,
                     "at": int(time.time())}, ensure_ascii=False) + "\n")
    except Exception:
        pass  # не смогли записать — токен вычистится в следующий раз


def _deliver(job: dict) -> None:
    token = job["token"]
    try:
        code, reason = send(
            token, job["payload"],
            sandbox=job["sandbox"],
            push_type=job["push_type"],
            topic=job.get("topic") or "",
        )
    except Exception as e:
        _stats["failed"] += 1
        print("apns: не отправлено:", str(e)[:160], flush=True)
        return
    if code == 200:
        _stats["sent"] += 1
        return
    _stats["failed"] += 1
    if reason in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"):
        _stats["gone"] += 1
        remember_dead_token(token, reason)


def _worker() -> None:
    while True:
        job = _outbox.get()
        try:
            _deliver(job)
        finally:
            _outbox.task_done()


def start_workers() -> None:
    for _ in range(WORKERS):
        threading.Thread(target=_worker, daemon=True).start()


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
            return self._reply(200, {
                "ok": True, "topic": TOPIC,
                "queue": _outbox.qsize(), "workers": WORKERS, "stats": dict(_stats),
            })
        self._reply(404, {"ok": False, "reason": "NotFound"})

    def do_POST(self):
        if self.path not in ("/push", "/apple/verify", "/google/verify"):
            return self._reply(404, {"ok": False, "reason": "NotFound"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, TypeError):
            return self._reply(400, {"ok": False, "reason": "BadRequest"})

        if self.path == "/apple/verify":
            token = str(req.get("token") or "").strip()
            if not token:
                return self._reply(400, {"ok": False, "reason": "NoToken"})
            try:
                claims = verify_apple_identity(token, str(req.get("nonce") or ""))
            except Exception as e:
                return self._reply(
                    200, {"ok": False, "reason": type(e).__name__ + ": " + str(e)[:120]}
                )
            return self._reply(200, {
                "ok": True,
                "sub": claims.get("sub"),
                "email": claims.get("email") or "",
                "email_verified": str(claims.get("email_verified", "")).lower() == "true",
                "is_private_email": str(claims.get("is_private_email", "")).lower() == "true",
            })

        if self.path == "/google/verify":
            token = str(req.get("token") or "").strip()
            if not token:
                return self._reply(400, {"ok": False, "reason": "NoToken"})
            try:
                claims = verify_google_identity(token)
            except Exception as e:
                return self._reply(
                    200, {"ok": False, "reason": type(e).__name__ + ": " + str(e)[:120]}
                )
            return self._reply(200, {
                "ok": True,
                "sub": claims.get("sub"),
                "email": str(claims.get("email") or "").lower(),
                "name": claims.get("name") or "",
                "picture": claims.get("picture") or "",
            })

        token = str(req.get("token") or "").strip()
        if not token:
            return self._reply(400, {"ok": False, "reason": "NoDeviceToken"})

        job = {
            "token": token,
            "payload": build_payload(req),
            "sandbox": bool(req.get("sandbox")),
            "push_type": "background" if req.get("silent") else "alert",
            "topic": str(req.get("topic") or "")[:80],
        }

        # Проверка доставки должна видеть ответ Apple — её пропускаем как есть.
        wants_answer = bool(req.get("sync")) or str(req.get("thread") or "") == "test"
        if not wants_answer:
            try:
                _outbox.put_nowait(job)
            except queue.Full:
                _stats["dropped"] += 1
                return self._reply(200, {"ok": False, "reason": "QueueFull"})
            _stats["queued"] += 1
            return self._reply(202, {"ok": True, "queued": True})

        try:
            code, reason = send(
                token,
                job["payload"],
                sandbox=job["sandbox"],
                push_type=job["push_type"],
                topic=job.get("topic") or "",
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
    start_workers()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
