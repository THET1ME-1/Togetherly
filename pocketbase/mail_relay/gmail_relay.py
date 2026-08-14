#!/usr/bin/env python3
"""Локальный почтовый релей PocketBase → Resend (основной) → Gmail (запасной).

ЗАЧЕМ РЕЛЕЙ: провайдер VPS (hostkey) режет ВСЕ исходящие SMTP-порты
(25/465/587/2525), поэтому PocketBase не может слать письма по SMTP. Работает
только HTTPS:443, значит письма уходят по HTTP-API почтовых сервисов. PB-хук
`gmail_mailer.pb.js` (onMailerSend) перехватывает каждое письмо и POST'ит
{to,subject,html,text} на этот релей (127.0.0.1, loopback — не блокируется).

ЗАЧЕМ ДВА КАНАЛА (14.08.2026). Раньше всё шло с личного ящика
stgroup.dev@gmail.com — с него же владелец отвечает людям руками. В день аварии
PocketBase получил 3580 запросов «забыл пароль» (люди жали кнопку без
остановки, потому что вход не работал), релей отправил 458 писем и выжег
суточную квоту Gmail (500 на аккаунт). Почта поддержки перестала уходить вовсе.
Теперь письма робота идут через Resend, а ящик Gmail остаётся живым людям и
включается лишь как запасной.

КЛАПАН держит три рубежа:
  * один адрес получает письмо с одной темой не чаще раза в 30 минут;
  * у каждого канала свой суточный бюджет (Resend 100 по тарифу, Gmail 250 —
    вторая половина квоты остаётся ручным ответам);
  * канал, отказавший по квоте, молчит 15 минут, а не долбит API впустую.
Отбитые письма возвращают 429, PB пишет это в журнал. Состояние лежит в
`/var/lib/gmail-relay/state.json` и переживает перезапуск; адресов там нет,
только их хеши.

КРЕДЫ — из окружения (systemd EnvironmentFile=/etc/gmail-relay.env, режим 600,
НЕ в репозитории):
  GMAIL_CLIENT_ID / GMAIL_CLIENT_SECRET / GMAIL_REFRESH_TOKEN — запасной канал;
  RESEND_API_KEY — основной канал (без него релей работает на одном Gmail);
  MAIL_FROM — отправитель для Resend, например «Togetherly <noreply@…>».
Пороги: MAIL_DEDUP_WINDOW, MAIL_RESEND_BUDGET, MAIL_GMAIL_BUDGET,
MAIL_QUOTA_COOLDOWN, MAIL_STATE_PATH. Слушает только 127.0.0.1.
"""
import json
import os
import time
import threading
import base64
import hashlib
import urllib.error
import urllib.request
import urllib.parse
from email.message import EmailMessage
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SENDER_ADDR = os.environ.get("GMAIL_SENDER_ADDR", "stgroup.dev@gmail.com")
SENDER_NAME = os.environ.get("GMAIL_SENDER_NAME", "Togetherly")
MAIL_FROM = os.environ.get("MAIL_FROM", f"{SENDER_NAME} <{SENDER_ADDR}>")
REPLY_TO = os.environ.get("MAIL_REPLY_TO", SENDER_ADDR)
USER_AGENT = os.environ.get("MAIL_USER_AGENT", "Togetherly-relay/1.0 (+https://togetherly.day)")
PORT = int(os.environ.get("GMAIL_RELAY_PORT", "8099"))

DAY = 86400

_tok = {"at": None, "exp": 0.0}
_lock = threading.Lock()


# ---------------------------------------------------------------- состояние
class State:
    """Общий файл состояния: хеши дедупа и счётчики каналов.

    Пишем атомарно и без адресов — в файле не должно быть ничего, что можно
    прочитать как переписку.
    """

    def __init__(self, path=None):
        self.path = path
        self.lock = threading.Lock()
        self.data = {"dedup": {}, "channels": {}}
        self._load()

    def _load(self):
        if not self.path or not os.path.exists(self.path):
            return
        try:
            with open(self.path, encoding="utf-8") as f:
                d = json.load(f)
            self.data["dedup"] = {str(k): float(v) for k, v in (d.get("dedup") or {}).items()}
            self.data["channels"] = d.get("channels") or {}
        except Exception as e:  # noqa: BLE001 — битый файл не должен ронять почту
            print(f"relay: состояние не прочиталось ({e}), начинаем с нуля", flush=True)

    def save(self):
        if not self.path:
            return
        try:
            d = os.path.dirname(self.path)
            if d:
                os.makedirs(d, exist_ok=True)
            tmp = self.path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.data, f)
            os.replace(tmp, self.path)
        except Exception as e:  # noqa: BLE001
            print(f"relay: состояние не сохранилось ({e})", flush=True)


class Dedup:
    """Одно и то же письмо одному человеку — не чаще раза в окно."""

    def __init__(self, window=1800, state=None):
        self.window = int(window)
        self.state = state or State(None)
        self.lock = threading.Lock()

    @staticmethod
    def key(addr, subject):
        raw = f"{str(addr).strip().lower()}|{str(subject).strip().lower()}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]

    def _prune(self, now):
        keep = max(self.window, 600)
        d = self.state.data["dedup"]
        for k in [k for k, t in d.items() if now - float(t) > keep]:
            d.pop(k, None)

    def seen(self, addr, subject, now=None):
        now = time.time() if now is None else now
        with self.lock:
            self._prune(now)
            last = self.state.data["dedup"].get(self.key(addr, subject))
            return last is not None and now - float(last) < self.window

    def note(self, addr, subject, now=None):
        now = time.time() if now is None else now
        with self.lock:
            self._prune(now)
            self.state.data["dedup"][self.key(addr, subject)] = now
            self.state.save()


class Channel:
    """Канал отправки со своим суточным бюджетом и паузой после отказа."""

    def __init__(self, name, daily_budget, cooldown=900, state=None):
        self.name = name
        self.daily_budget = int(daily_budget)
        self.cooldown = int(cooldown)
        self.state = state or State(None)
        self.lock = threading.Lock()
        self.state.data["channels"].setdefault(name, {"sent": [], "cooldown_until": 0})

    @property
    def _slot(self):
        return self.state.data["channels"].setdefault(
            self.name, {"sent": [], "cooldown_until": 0})

    def _prune(self, now):
        slot = self._slot
        slot["sent"] = [float(t) for t in slot.get("sent", []) if now - float(t) < DAY]
        return slot

    def ready(self, now=None):
        """→ (можно ли слать, причина отказа)."""
        now = time.time() if now is None else now
        with self.lock:
            slot = self._prune(now)
            if now < float(slot.get("cooldown_until", 0)):
                return False, "cooldown"
            if len(slot["sent"]) >= self.daily_budget:
                return False, "budget"
            return True, ""

    def note_sent(self, now=None):
        now = time.time() if now is None else now
        with self.lock:
            slot = self._prune(now)
            slot["sent"].append(now)
            self.state.save()

    def note_quota_error(self, now=None):
        now = time.time() if now is None else now
        with self.lock:
            self._slot["cooldown_until"] = now + self.cooldown
            self.state.save()

    def remaining(self, now=None):
        now = time.time() if now is None else now
        with self.lock:
            slot = self._prune(now)
            return max(0, self.daily_budget - len(slot["sent"]))


def _looks_like_quota(err):
    """Отказ по квоте: Gmail отвечает 429 (изредка 403), Resend — 429."""
    if isinstance(err, urllib.error.HTTPError):
        if err.code == 429:
            return True
        if err.code == 403:
            try:
                body = err.read().decode("utf-8", "replace").lower()
            except Exception:  # noqa: BLE001
                return False
            return "quota" in body or "limit" in body
        return False
    text = str(err).lower()
    return "quota" in text or "too many requests" in text or "rate limit" in text


# ------------------------------------------------------------------ каналы
def _creds():
    """Креды Gmail читаем при первом обращении: без них модуль всё равно
    импортируем (иначе тесты клапана не поднять)."""
    return (
        os.environ["GMAIL_CLIENT_ID"],
        os.environ["GMAIL_CLIENT_SECRET"],
        os.environ["GMAIL_REFRESH_TOKEN"],
    )


def _access_token():
    with _lock:
        if _tok["at"] and time.time() < _tok["exp"] - 60:
            return _tok["at"]
        cid, csec, rt = _creds()
        data = urllib.parse.urlencode({
            "client_id": cid, "client_secret": csec,
            "refresh_token": rt, "grant_type": "refresh_token",
        }).encode()
        r = urllib.request.urlopen(
            "https://oauth2.googleapis.com/token", data=data, timeout=20)
        t = json.loads(r.read())
        _tok["at"] = t["access_token"]
        _tok["exp"] = time.time() + int(t.get("expires_in", 3600))
        return _tok["at"]


def send_gmail(to, subject, html, text):
    m = EmailMessage()
    m["From"] = f"{SENDER_NAME} <{SENDER_ADDR}>"
    m["To"] = ", ".join(to)
    m["Subject"] = subject or ""
    m.set_content(text or " ")
    if html:
        m.add_alternative(html, subtype="html")
    raw = base64.urlsafe_b64encode(m.as_bytes()).decode()
    req = urllib.request.Request(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        data=json.dumps({"raw": raw}).encode(),
        headers={"Authorization": "Bearer " + _access_token(),
                 "Content-Type": "application/json"})
    r = urllib.request.urlopen(req, timeout=20)
    return json.loads(r.read()).get("id")


def resend_payload(to, subject, html, text):
    """Тело запроса к Resend. Reply-To ведёт в ящик поддержки: письмо приходит
    с noreply-адреса, но ответ человека должен попасть к живому человеку."""
    payload = {"from": MAIL_FROM, "to": list(to), "subject": subject or "",
               "reply_to": REPLY_TO}
    if html:
        payload["html"] = html
    payload["text"] = text or " "
    return payload


def resend_headers(key):
    """Свой User-Agent обязателен: перед Resend стоит Cloudflare, и на
    умолчание `Python-urllib` он отвечает 403 «error code: 1010», хотя тот же
    запрос curl'ом с этого же сервера проходит (проверено 14.08.2026)."""
    return {
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    }


def send_resend(to, subject, html, text):
    payload = resend_payload(to, subject, html, text)
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(payload).encode(),
        headers=resend_headers(os.environ["RESEND_API_KEY"]))
    r = urllib.request.urlopen(req, timeout=20)
    return json.loads(r.read()).get("id")


# ---------------------------------------------------------------- доставка
def deliver(to, subject, html, text, now=None, senders=None, channels=None, dedup=None):
    """Отдаёт письмо первому готовому каналу. → (HTTP-код, тело ответа).

    Дедуп отмечаем только на успехе: если сеть отвалилась, человек должен
    иметь возможность нажать «забыл пароль» ещё раз, а не ждать полчаса.
    """
    now = time.time() if now is None else now
    senders = senders if senders is not None else SENDERS
    channels = channels if channels is not None else CHANNELS
    dedup = dedup if dedup is not None else DEDUP

    addr = to[0]
    if dedup.seen(addr, subject, now=now):
        return 429, {"ok": False, "skipped": "dedup"}

    first_reason = ""
    last_error = ""
    for ch in channels:
        send = senders.get(ch.name)
        if send is None:
            continue
        ok, reason = ch.ready(now=now)
        if not ok:
            first_reason = first_reason or reason
            continue
        try:
            mid = send(to, subject, html, text)
        except Exception as e:  # noqa: BLE001 — падение канала не должно ронять релей
            last_error = str(e)
            if _looks_like_quota(e):
                ch.note_quota_error(now=now)
                print(f"relay: канал {ch.name} отказал по квоте, пауза {ch.cooldown} с",
                      flush=True)
            else:
                print(f"relay: канал {ch.name} не отправил ({e})", flush=True)
            continue
        ch.note_sent(now=now)
        dedup.note(addr, subject, now=now)
        print(f"relay: отправлено через {ch.name}, id={mid}, "
              f"остаток {ch.remaining(now=now)}", flush=True)  # без PII
        return 200, {"ok": True, "id": mid, "channel": ch.name}

    if last_error:
        return 502, {"ok": False, "error": last_error}
    return 429, {"ok": False, "skipped": first_reason or "no channels"}


STATE = State(os.environ.get("MAIL_STATE_PATH", "/var/lib/gmail-relay/state.json"))
DEDUP = Dedup(window=os.environ.get("MAIL_DEDUP_WINDOW", 1800), state=STATE)
COOLDOWN = int(os.environ.get("MAIL_QUOTA_COOLDOWN", 900))
CHANNELS = [
    Channel("resend", os.environ.get("MAIL_RESEND_BUDGET", 100), COOLDOWN, state=STATE),
    Channel("gmail", os.environ.get("MAIL_GMAIL_BUDGET", 250), COOLDOWN, state=STATE),
]
SENDERS = {"gmail": send_gmail}
if os.environ.get("RESEND_API_KEY"):
    SENDERS["resend"] = send_resend


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # healthcheck и остаток бюджетов
        self._reply(200, {
            "ok": True, "service": "mail-relay",
            "channels": {c.name: {"left": c.remaining(), "enabled": c.name in SENDERS}
                         for c in CHANNELS},
        })

    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length", 0) or 0)
            d = json.loads(self.rfile.read(n) or b"{}")
            to = d.get("to") or []
            if isinstance(to, str):
                to = [to]
            if not to:
                return self._reply(400, {"ok": False, "error": "no recipients"})
            code, body = deliver(to, d.get("subject", ""), d.get("html", ""),
                                 d.get("text", ""))
            self._reply(code, body)
        except Exception as e:  # noqa: BLE001
            print(f"relay ERROR: {e}", flush=True)
            self._reply(500, {"ok": False, "error": str(e)})

    def log_message(self, *a):  # тихо
        pass


if __name__ == "__main__":
    if "resend" not in SENDERS:
        _creds()  # запасной канал единственный — падаем сразу, если кредов нет
    print(f"mail-relay: старт на 127.0.0.1:{PORT}, каналы "
          + ", ".join(f"{c.name}={c.remaining()}"
                      + ("" if c.name in SENDERS else " (выключен)")
                      for c in CHANNELS), flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
