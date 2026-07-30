#!/usr/bin/env python3
"""Приём событий аналитики приложения.

Слушает 127.0.0.1:8098, наружу его пускает Caddy на `/api/stats/collect`
с ограничением частоты. Пишет в СВОЮ базу `/opt/app_stats/stats.db`: события
в базе PocketBase конкурировали бы за запись с чатом и синхронизацией — SQLite
запирает файл целиком, а перегрузку 27 июня повторять незачем. Заодно сырьё не
ездит в ночном шифрованном бэкапе основной базы.

Запуск (юнит `stats-collector`):
    python3 /opt/app_stats/stats_collector.py

Проверка живьём:
    curl -s -X POST http://127.0.0.1:8098/collect -H 'Content-Type: application/json' \\
      -d '{"uid":"test","platform":"android","version":"1.20.0+148",
           "events":[{"ts":1753800000,"kind":"screen","name":"home","ms":4200}]}'
"""
import hashlib
import json
import os
import sqlite3
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("STATS_DB", "/opt/app_stats/stats.db")
SALT_PATH = os.environ.get("STATS_SALT", "/opt/app_stats/.salt")
PORT = int(os.environ.get("STATS_PORT", "8098"))

# Потолки на пачку: кривой или зловредный клиент не должен положить службу.
MAX_BODY = 256 * 1024
MAX_EVENTS = 200
KINDS = {"screen", "action", "funnel", "ad"}
# Имя события — из латиницы, цифр и подчёркиваний. Всё прочее отбрасываем:
# в базу не должно попадать ни имя человека, ни текст сообщения.
NAME_MAX = 64


def salt():
    """Серверная соль для хеша uid. Заводится при первом запуске."""
    if not os.path.exists(SALT_PATH):
        os.makedirs(os.path.dirname(SALT_PATH), exist_ok=True)
        with open(SALT_PATH, "wb") as f:
            f.write(os.urandom(32))
        os.chmod(SALT_PATH, 0o600)
    with open(SALT_PATH, "rb") as f:
        return f.read()


_SALT = salt()


def uid_hash(uid):
    """Связки «человек → его экраны» в базе нет: только хеш с серверной солью."""
    return hashlib.sha256(_SALT + uid.encode()).hexdigest()[:16]


def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    # WAL: запись не ждёт диск и не блокирует чтение агрегатором.
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY,
              ts INTEGER NOT NULL,
              uid_hash TEXT NOT NULL,
              platform TEXT NOT NULL,
              version TEXT NOT NULL,
              kind TEXT NOT NULL,
              name TEXT NOT NULL,
              ms INTEGER,
              params TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
            CREATE INDEX IF NOT EXISTS idx_events_kind_name
              ON events(kind, name, ts);

            CREATE TABLE IF NOT EXISTS daily (
              day TEXT NOT NULL,
              kind TEXT NOT NULL,
              name TEXT NOT NULL,
              hits INTEGER NOT NULL,
              uniques INTEGER NOT NULL,
              ms_total INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (day, kind, name)
            );
            """
        )


def clean_name(raw):
    """Имя события: латиница, цифры, подчёркивание и точка. Прочее — мимо."""
    if not isinstance(raw, str):
        return None
    name = raw.strip()[:NAME_MAX]
    if not name:
        return None
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
    return name if set(name) <= allowed else None


def parse_batch(payload):
    """Разбирает пачку в строки для вставки. Кривое событие пропускаем молча:
    из-за одного испорченного не теряем остальные девяносто девять."""
    uid = payload.get("uid")
    if not isinstance(uid, str) or not uid:
        return None
    platform = str(payload.get("platform", ""))[:16]
    version = str(payload.get("version", ""))[:32]
    events = payload.get("events")
    if not isinstance(events, list) or not events:
        return None

    who = uid_hash(uid)
    rows = []
    for ev in events[:MAX_EVENTS]:
        if not isinstance(ev, dict):
            continue
        kind = ev.get("kind")
        name = clean_name(ev.get("name"))
        if kind not in KINDS or name is None:
            continue
        try:
            ts = int(ev.get("ts", 0))
        except (TypeError, ValueError):
            continue
        if ts <= 0:
            continue
        ms = ev.get("ms")
        try:
            ms = int(ms) if ms is not None else None
        except (TypeError, ValueError):
            ms = None
        params = ev.get("params")
        params = json.dumps(params, ensure_ascii=False)[:512] if params else None
        rows.append((ts, who, platform, version, kind, name, ms, params))
    return rows


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path.rstrip("/") not in ("/collect", ""):
            self._reply(404, {"ok": False})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._reply(413, {"ok": False, "error": "body"})
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except ValueError:
            self._reply(400, {"ok": False, "error": "json"})
            return

        rows = parse_batch(payload) if isinstance(payload, dict) else None
        if not rows:
            # Пустая или целиком кривая пачка — не ошибка клиента, ответ тот же
            # 200: приложение не должно копить и переслать её снова.
            self._reply(200, {"ok": True, "saved": 0})
            return

        try:
            with db() as conn:
                conn.executemany(
                    "INSERT INTO events (ts, uid_hash, platform, version, kind,"
                    " name, ms, params) VALUES (?,?,?,?,?,?,?,?)",
                    rows,
                )
        except sqlite3.Error as e:
            print(f"insert failed: {e}", file=sys.stderr, flush=True)
            self._reply(503, {"ok": False, "error": "db"})
            return

        self._reply(200, {"ok": True, "saved": len(rows)})

    def do_GET(self):
        # Проба живости для systemd и для рук.
        if self.path.rstrip("/") == "/health":
            self._reply(200, {"ok": True})
            return
        self._reply(404, {"ok": False})

    def log_message(self, *args):
        # Журнал Caddy и так пишет запросы; дублировать в systemd незачем.
        pass


def main():
    init_db()
    print(f"stats collector on 127.0.0.1:{PORT}, db {DB_PATH}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
