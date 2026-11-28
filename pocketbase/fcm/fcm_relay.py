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

import collections
import http.client
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import threading
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


FCM_MAX_DATA_BYTES = 4000  # предел FCM 4096, запас на служебные ключи

# Выключатель уведомлений «А»: есть файл — пуш данными не уходит никому, все
# получают прежний `notification`. На случай, если отрисовка в сборке
# сломалась: возврат без выпуска (`touch /opt/fcm/cover.off`).
COVER_OFF_FILE = os.environ.get("FCM_COVER_OFF_FILE", "/opt/fcm/cover.off")
_cover_off_cache = (0.0, False)


def _cover_off() -> bool:
    global _cover_off_cache
    now = time.monotonic()
    if now - _cover_off_cache[0] > 10:
        _cover_off_cache = (now, os.path.exists(COVER_OFF_FILE))
    return _cover_off_cache[1]


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

    # Обложка «А» (28.11.2026): новая сборка рисует уведомление сама
    # (`FcmService` → `NotifCover`), поэтому только данные — с готовым
    # `notification` система нарисовала бы его за неё. Старым сборкам
    # отправитель `data_only` не ставит, и они получают прежнее.
    cover = req.get("cover")
    if isinstance(cover, dict) and req.get("data_only") and not _cover_off():
        rich = dict(data)
        rich["cover"] = json.dumps(cover, ensure_ascii=False)
        rich.setdefault("title", req.get("title") or "Togetherly")
        rich.setdefault("body", req.get("body") or "")
        if req.get("tag"):
            rich.setdefault("tag", str(req["tag"]))
        # Данные больше 4096 байт FCM отбивает: длинное сообщение уходит
        # обычным пушем системы, а не пропадает.
        if sum(len(k.encode()) + len(v.encode()) for k, v in rich.items()) <= FCM_MAX_DATA_BYTES:
            message["data"] = rich
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


FCM_HOST = "fcm.googleapis.com"
SEND_TIMEOUT = 20

# Своё соединение у каждого рабочего потока, живёт между пушами. Раньше каждый
# пуш открывал новое: TCP и TLS до Google из Москвы — от 0,15 до 2 с, и очередь
# стояла на рукопожатиях (TOG-90).
_local = threading.local()


def _post(path: str, body: bytes, headers: dict):
    """POST в FCM по соединению потока. Отдаёт (код, тело ответа).

    Соединение, которое Google успел закрыть, ломается на первом же запросе:
    тогда открываем новое и повторяем один раз. Повтор только для старого
    соединения: на свежем ошибка — уже настоящая, и пуш мог уйти.
    """
    for attempt in (1, 2):
        conn = getattr(_local, "conn", None)
        fresh = conn is None
        if fresh:
            conn = http.client.HTTPSConnection(FCM_HOST, timeout=SEND_TIMEOUT)
            _local.conn = conn
        try:
            conn.request("POST", path, body=body, headers=headers)
            resp = conn.getresponse()
            return resp.status, resp.read()
        except (http.client.HTTPException, OSError):
            conn.close()
            _local.conn = None
            if fresh or attempt == 2:
                raise
    raise RuntimeError("unreachable")


def send(token: str, req: dict):
    """Отдаёт (код ответа FCM, причина отказа)."""
    acc = account()
    path = "/v1/projects/%s/messages:send" % acc["project"]
    payload = json.dumps({"message": build_message(req, token)}, ensure_ascii=False)
    headers = {
        "Authorization": "Bearer " + access_token(),
        "Content-Type": "application/json; charset=utf-8",
    }
    code, raw = _post(path, payload.encode(), headers)
    if code == 200:
        return code, ""
    return code, error_code(raw.decode(errors="replace"))


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



# ── Отправка в фоне ────────────────────────────────────────────────────────────
#
# Хук PocketBase звал релей внутри пользовательского запроса и ждал ответа
# Google. Ждал не сервер, а человек: сохранение сообщения или настроения стояло
# ровно столько, сколько отвечал чужой сервис. Теперь запрос кладётся в очередь
# и подтверждается сразу; проверочный пуш (`tag: "test"`) остаётся синхронным,
# в нём ответ Google и есть весь смысл.
#
# Полос две (TOG-90, 14.11.2026). Пуш с баннером — подарок, сообщение,
# «Скучаю» — человек ждёт глазами, тихий пуш виджетов не ждёт никто. В одной
# очереди подарок стоял за пачкой тихих пушей: ночью, при одном пуше в секунду,
# проба прождала 21 с, а днём пачки тихих идут тысячами, и при полной очереди
# пуш с баннером выбрасывался вовсе — о подарке человек узнавал, открыв
# приложение через несколько часов. Теперь баннерный пуш берётся первым и
# своё место в очереди тихим не отдаёт.
QUEUE_MAX = int(os.environ.get("FCM_QUEUE_MAX", "20000"))
URGENT_MAX = int(os.environ.get("FCM_URGENT_MAX", "5000"))
WORKERS = int(os.environ.get("FCM_WORKERS", "12"))
STATS_EVERY = 600
DEAD_TOKENS_FILE = os.environ.get(
    "FCM_DEAD_TOKENS", "/opt/pocketbase/pb_data/.dead_tokens.jsonl")


class Outbox:
    """Очередь на две полосы: заметные пуши уходят раньше тихих."""

    def __init__(self, bulk_max: int, urgent_max: int):
        self._urgent = collections.deque()
        self._bulk = collections.deque()
        self._max = {True: urgent_max, False: bulk_max}
        self._cond = threading.Condition()

    def put(self, job: dict, urgent: bool) -> bool:
        """Ставит пуш в свою полосу. Ложь — полоса полна."""
        lane = self._urgent if urgent else self._bulk
        with self._cond:
            if len(lane) >= self._max[urgent]:
                return False
            job["at"] = time.monotonic()
            lane.append(job)
            self._cond.notify()
            return True

    def get(self):
        """Следующий пуш и его полоса; ждёт, пока что-то появится."""
        with self._cond:
            while not self._urgent and not self._bulk:
                self._cond.wait()
            if self._urgent:
                return self._urgent.popleft(), True
            return self._bulk.popleft(), False

    def sizes(self) -> dict:
        with self._cond:
            return {"urgent": len(self._urgent), "bulk": len(self._bulk)}


def is_urgent(req: dict) -> bool:
    """Пуш с баннером человек ждёт, тихий пуш виджетов — нет."""
    return not req.get("silent")


_outbox = Outbox(QUEUE_MAX, URGENT_MAX)
_dead_lock = threading.Lock()
_stats = {"queued": 0, "sent": 0, "failed": 0, "dropped": 0, "gone": 0,
          "dropped_urgent": 0, "wait_urgent_max": 0.0, "wait_bulk_max": 0.0}


def remember_dead_token(token: str, reason: str) -> None:
    """Мёртвый токен складываем в файл — вычистит крон."""
    try:
        with _dead_lock:
            with open(DEAD_TOKENS_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(
                    {"token": token, "reason": reason, "kind": "fcm",
                     "at": int(time.time())}, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _deliver(job: dict) -> None:
    try:
        code, reason = send(job["token"], job["req"])
    except Exception as e:
        _stats["failed"] += 1
        print("fcm: не отправлено:", str(e)[:160], flush=True)
        return
    if code == 200:
        _stats["sent"] += 1
        return
    _stats["failed"] += 1
    if token_is_gone(reason):
        _stats["gone"] += 1
        remember_dead_token(job["token"], reason)


def _worker() -> None:
    while True:
        job, urgent = _outbox.get()
        # Сколько пуш простоял в очереди — главный признак задержки.
        waited = time.monotonic() - job["at"]
        key = "wait_urgent_max" if urgent else "wait_bulk_max"
        if waited > _stats[key]:
            _stats[key] = waited
        _deliver(job)


def _report() -> None:
    """Раз в десять минут — сводка в журнал, максимумы ожидания с нуля."""
    while True:
        time.sleep(STATS_EVERY)
        sizes = _outbox.sizes()
        print("fcm: сводка", json.dumps({**_stats, **sizes,
              "wait_urgent_max": round(_stats["wait_urgent_max"], 1),
              "wait_bulk_max": round(_stats["wait_bulk_max"], 1)}, ensure_ascii=False), flush=True)
        _stats["wait_urgent_max"] = 0.0
        _stats["wait_bulk_max"] = 0.0


def start_workers() -> None:
    for _ in range(WORKERS):
        threading.Thread(target=_worker, daemon=True).start()
    threading.Thread(target=_report, daemon=True).start()


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
        if self.path == "/stats":
            return self._reply(200, {**_stats, **_outbox.sizes()})
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

        wants_answer = bool(req.get("sync")) or str(req.get("tag") or "") == "test"
        if not wants_answer:
            urgent = is_urgent(req)
            if not _outbox.put({"token": token, "req": req}, urgent):
                _stats["dropped"] += 1
                if urgent:
                    _stats["dropped_urgent"] += 1
                    print("fcm: полоса баннеров полна, пуш выброшен", flush=True)
                return self._reply(200, {"ok": False, "reason": "QueueFull"})
            _stats["queued"] += 1
            return self._reply(202, {"ok": True, "queued": True})

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
    start_workers()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
