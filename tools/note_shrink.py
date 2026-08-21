#!/usr/bin/env python3
"""Пережимает фигурки (видеосообщения чата) в квадрат 480×480 H.264.

Зачем. Телефон снимает прямоугольный кадр и жмёт его аппаратным кодеком «как
получится»: тридцать секунд весят три с половиной мегабайта. Показывается при
этом КВАДРАТ — форма всё равно обрезает края, — то есть больше сорока процентов
пикселей хранятся и раздаются впустую. Здесь кадр обрезается по центру, сводится
к 480×480 и кодируется медленным пресетом: тот же ролик выходит около мегабайта,
типичная фигурка на десять секунд — около трёхсот килобайт.

Почему H.264, а не HEVC или AV1. Фигурку смотрит ровно один человек — партнёр, —
и если у него не окажется декодера, сообщение просто не откроется. HEVC дал бы
ещё вдвое меньше, но на дешёвых Android его аппаратная поддержка не гарантирована,
а VP9 не играет AVPlayer на iPhone. Совместимость здесь дороже мегабайтов.

Почему кроном, а не роутом из приложения. Так не нужен ни рестарт PocketBase (а
он роняет всем 502 на время старта), ни новая версия клиента: файл в бакете
подменяется ПОД ТЕМ ЖЕ ИМЕНЕМ, поэтому ссылка `pb://media/<id>/<file>` остаётся
прежней и ничего в базе править не надо.

Запуск: /opt/pocketbase/tools/note_shrink.py [--days 3] [--limit 200] [--dry-run]
Крон: */3 * * * * flock -n /tmp/note_shrink.lock /opt/pocketbase/tools/note_shrink.py
"""

import argparse
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pb_storage  # noqa: E402

RCLONE = "/usr/local/bin/rclone"
BUCKET = "hk:b86d5542-togetherly-storage"
MEDIA = "pbc_2708086759"
STATE_DB = "/opt/pocketbase/pb_data/note_shrink.db"
ENV_FILE = "/opt/hotpath/env"

# Ширина кадра. Фигурка занимает на экране около 230 dp — это до 690 физических
# пикселей на самых плотных экранах, и 480 там уже почти неотличимо, а весит
# вдвое меньше 720.
SIDE = 480
CRF = "31"
FFMPEG_TIMEOUT = 180

# Меньше этой доли экономии файл не трогаем: перекодирование всегда теряет
# качество, и ради пяти процентов это невыгодно.
MIN_GAIN = 0.15

REF = re.compile(r"^pb://media/([a-zA-Z0-9_]+)/(.+)$")


def dsn():
    """Строка подключения к Postgres берётся из окружения hotpath."""
    try:
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("HOTPATH_PG_DSN="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return os.environ.get("HOTPATH_PG_DSN", "")


def state():
    db = sqlite3.connect(STATE_DB)
    db.execute(
        "CREATE TABLE IF NOT EXISTS done ("
        " msg_id TEXT PRIMARY KEY, before INTEGER, after INTEGER, at INTEGER)"
    )
    db.commit()
    return db


def fresh_notes(days, limit):
    """Фигурки за последние [days] суток: id сообщения и ссылка на файл."""
    conn = dsn()
    if not conn:
        print("нет строки подключения к Postgres", file=sys.stderr)
        return []
    since = int((time.time() - days * 86400) * 1000)
    sql = (
        "SELECT id, note_url FROM chat_messages "
        "WHERE note_url LIKE 'pb://media/%%' AND ts > %d "
        "ORDER BY ts DESC LIMIT %d" % (since, limit)
    )
    res = subprocess.run(
        ["psql", conn, "-tAF", "\x1f", "-c", sql],
        capture_output=True, text=True, timeout=60,
    )
    if res.returncode != 0:
        print("psql: " + res.stderr.strip(), file=sys.stderr)
        return []
    out = []
    for line in res.stdout.splitlines():
        if "\x1f" not in line:
            continue
        msg_id, url = line.split("\x1f", 1)
        m = REF.match(url.strip())
        if m:
            out.append((msg_id, m.group(1), m.group(2)))
    return out


def shrink(src_path, dst_path):
    """ffmpeg: квадрат по центру, 480×480, H.264. Возвращает True при удаче."""
    cmd = [
        "nice", "-n", "10", "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", src_path,
        "-vf", "crop='min(iw,ih)':'min(iw,ih)',scale=%d:%d:flags=lanczos,fps=24" % (SIDE, SIDE),
        "-c:v", "libx264", "-preset", "slow", "-crf", CRF,
        "-profile:v", "high", "-pix_fmt", "yuv420p", "-g", "48",
        "-c:a", "aac", "-b:a", "40k", "-ac", "1", "-ar", "44100",
        "-movflags", "+faststart",
        dst_path,
    ]
    try:
        res = subprocess.run(cmd, capture_output=True, timeout=FFMPEG_TIMEOUT)
    except subprocess.TimeoutExpired:
        print("ffmpeg завис на %s" % src_path, file=sys.stderr)
        return False
    if res.returncode != 0:
        print("ffmpeg: " + res.stderr.decode(errors="replace")[:300], file=sys.stderr)
        return False
    return os.path.exists(dst_path) and os.path.getsize(dst_path) > 0


def upload(path, rec_id, name):
    """Кладёт файл обратно ПОД ТЕМ ЖЕ ИМЕНЕМ — ссылка в базе не меняется."""
    key = "%s/%s/%s/%s" % (BUCKET, MEDIA, rec_id, name)
    res = subprocess.run(
        [RCLONE, "copyto", path, key,
         "--header-upload", "Content-Type: video/mp4",
         "--retries", "3", "--low-level-retries", "10"],
        capture_output=True, timeout=180,
    )
    if res.returncode != 0:
        print("rclone: " + res.stderr.decode(errors="replace")[:300], file=sys.stderr)
        return False
    # Локальная копия (если хранилище ещё на диске) тоже должна стать лёгкой.
    local = os.path.join(pb_storage.STORE, MEDIA, rec_id, name)
    if os.path.exists(local):
        try:
            subprocess.run(["cp", path, local], check=True, timeout=60)
        except Exception as e:
            print("локальная копия не заменилась: %s" % e, file=sys.stderr)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    db = state()
    if args.report:
        row = db.execute(
            "SELECT COUNT(*), COALESCE(SUM(before),0), COALESCE(SUM(after),0) FROM done"
        ).fetchone()
        saved = (row[1] - row[2]) / 1048576 if row[1] else 0
        print("пережато: %d, было %.1f МБ, стало %.1f МБ, сэкономлено %.1f МБ"
              % (row[0], row[1] / 1048576, row[2] / 1048576, saved))
        return 0

    todo = fresh_notes(args.days, args.limit)
    done = {r[0] for r in db.execute("SELECT msg_id FROM done")}
    todo = [t for t in todo if t[0] not in done]
    if not todo:
        return 0

    ok = 0
    saved = 0
    for msg_id, rec_id, name in todo:
        with pb_storage.Source(rec_id, name) as src:
            if not src.path:
                # Файла нет — сообщение могли удалить. Помечаем, чтобы не
                # ходить за ним каждые три минуты.
                db.execute("INSERT OR REPLACE INTO done VALUES (?,?,?,?)",
                           (msg_id, 0, 0, int(time.time())))
                db.commit()
                continue
            before = os.path.getsize(src.path)
            tmp = tempfile.mkdtemp(prefix="noteshrink_")
            dst = os.path.join(tmp, "out.mp4")
            try:
                if not shrink(src.path, dst):
                    continue
                after = os.path.getsize(dst)
                gain = 1 - after / before if before else 0
                if gain < MIN_GAIN:
                    db.execute("INSERT OR REPLACE INTO done VALUES (?,?,?,?)",
                               (msg_id, before, before, int(time.time())))
                    db.commit()
                    continue
                if args.dry_run:
                    print("%s: %.2f → %.2f МБ (−%d%%)"
                          % (msg_id, before / 1048576, after / 1048576, gain * 100))
                    continue
                if not upload(dst, rec_id, name):
                    continue
                db.execute("INSERT OR REPLACE INTO done VALUES (?,?,?,?)",
                           (msg_id, before, after, int(time.time())))
                db.commit()
                ok += 1
                saved += before - after
            finally:
                subprocess.run(["rm", "-rf", tmp], timeout=30)

    if ok:
        print("пережато %d, сэкономлено %.1f МБ" % (ok, saved / 1048576))
    return 0


if __name__ == "__main__":
    sys.exit(main())
