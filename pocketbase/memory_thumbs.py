#!/usr/bin/env python3
"""Обложки видео-воспоминаниям, у которых её нет.

Жалоба 05.10.2026: в «Наших видео» на экране «Смотрим» ролики стоят серыми
плитками. Причины две, обе в данных:

  * ссылки на ролики (YouTube, Rutube) почти никогда не хранят обложку —
    oEmbed на шеринге её не отдаёт: за сентябрь без неё 1540 записей из 1542;
  * своё видео хранит кадр, снятый телефоном при сохранении, но съёмка
    кадра ограничена 30 секундами и на части телефонов не успевает: в
    августе без обложки 750 своих видео из 3614.

Приложение с той же даты само выводит обложку ссылки по номеру ролика, но
выпущенные сборки этого не умеют. Поэтому обложку вписывает сервер, в саму
запись (`data.imageUrl`), и сдвигает `updated` — телефоны догружают ленту
по `updated > водяной знак`, и обложка доезжает до всех без обновления.

  * Ссылка: кадр площадки по номеру ролика, то же правило, что в
    приложении (`lib/utils/video_link_thumb.dart`, сверяет тест).
  * Своё видео: файл берётся из хранилища (диск или бакет, pb_storage.py),
    ffmpeg снимает кадр на первой секунде, кадр ложится новой записью
    `media` с видом `memories` от имени автора — так же, как кладёт телефон.

Перед правкой каждой записи её id и прежнее значение пишутся в журнал
отката (`--undo-log`): откат — вернуть `imageUrl` пустым по этим id.

Запуск на сервере (cron, раз в 10 минут, своими видео по 12 штук за проход):
  memory_thumbs.py --links --videos 12
Разово всё прошлое: --all. Посмотреть без записи: --dry-run.
"""
import argparse
import datetime
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

PB = "http://127.0.0.1:8090"
PB_DIR = "/opt/pocketbase"
ENV_FILE = "/opt/hotpath/env"
TOOLS = "/opt/pocketbase/tools"
UNDO_LOG = "/opt/pb_backups/memory_thumbs_undo.jsonl"
STATE = "/opt/pocketbase/pb_data/.memory_thumbs_failed.json"

_YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_RT = re.compile(r"/(?:video|shorts)/([0-9a-f]{32})")
_ID = re.compile(r"^[A-Za-z0-9_-]{6,40}$")


# ── правило обложки по ссылке (зеркало lib/utils/video_link_thumb.dart) ─────

def link_thumb(url: str) -> str:
    """Обложка ролика по ссылке на площадку; без открытой обложки — ''."""
    try:
        u = urllib.parse.urlparse((url or "").strip())
    except ValueError:
        return ""
    if u.scheme not in ("http", "https"):
        return ""
    host = re.sub(r"^(www|m)\.", "", (u.hostname or "").lower())
    yt = None
    if host == "youtu.be":
        parts = [p for p in u.path.split("/") if p]
        yt = parts[0] if parts else None
    elif host in ("youtube.com", "music.youtube.com"):
        yt = (urllib.parse.parse_qs(u.query).get("v") or [None])[0]
        if yt is None:
            m = re.match(r"^/(?:shorts|embed|live)/([^/?#]+)", u.path)
            yt = m.group(1) if m else None
    if yt and _YT_ID.match(yt):
        return "https://i.ytimg.com/vi/%s/hqdefault.jpg" % yt
    if host == "rutube.ru" or host.endswith(".rutube.ru"):
        m = _RT.search(u.path)
        if m:
            return "https://rutube.ru/api/video/%s/thumbnail/?redirect=1" % m.group(1)
    return ""


def pb_ref(url: str):
    """`pb://media/<запись>/<файл>` → (запись, файл), иначе None."""
    m = re.match(r"^pb://media/([a-z0-9]{6,32})/([A-Za-z0-9_.-]{1,200})$", url or "")
    if not m or ".." in m.group(2):
        return None
    return m.group(1), m.group(2)


def _q(s: str) -> str:
    return "'" + str(s).replace("'", "''") + "'"


def set_image_sql(rec_id: str, image: str, updated: str) -> str:
    """Вписать обложку записи, только если её всё ещё нет."""
    if not _ID.match(rec_id or ""):
        raise ValueError("bad id: %r" % rec_id)
    return (
        "UPDATE memories SET data = jsonb_set(data, '{imageUrl}', to_jsonb(%s::text)), "
        "updated = %s WHERE id = %s AND coalesce(data->>'imageUrl','') = '';"
        % (_q(image), _q(updated), _q(rec_id))
    )


def now_pb() -> str:
    t = datetime.datetime.now(datetime.timezone.utc)
    return t.strftime("%Y-%m-%d %H:%M:%S.") + "%03dZ" % (t.microsecond // 1000)


# ── база ────────────────────────────────────────────────────────────────────

def dsn() -> str:
    try:
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("HOTPATH_PG_DSN="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return os.environ.get("HOTPATH_PG_DSN", "")


def psql(sql: str):
    # Запрос идёт через стандартный ввод: сотни правок одной строкой не
    # помещаются в аргументы процесса (Argument list too long, 05.10.2026).
    res = subprocess.run(["psql", dsn(), "-tAF", "\x1f", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                         input=sql, capture_output=True, text=True, timeout=300)
    if res.returncode != 0:
        raise RuntimeError("psql: " + res.stderr.strip())
    return [line.split("\x1f") for line in res.stdout.splitlines() if line]


def candidates(own: bool, limit: int, since_days):
    """Записи без обложки: ссылки ([own]=False) или свои файлы ([own]=True)."""
    cond = "data->>'videoUrl' LIKE 'pb://media/%%'" if own else "data->>'videoUrl' NOT LIKE 'pb://%%'"
    window = "" if since_days is None else (
        " AND created_at >= %s" % _q((datetime.datetime.utcnow() - datetime.timedelta(days=since_days))
                                     .strftime("%Y-%m-%d %H:%M:%S")))
    sql = (
        "SELECT id, group_id, author_uid, data->>'videoUrl' FROM memories "
        "WHERE NOT deleted AND coalesce(data->>'videoUrl','') <> '' "
        "AND coalesce(data->>'imageUrl','') = '' AND %s%s "
        "ORDER BY created_at DESC LIMIT %d" % (cond, window, limit)
    ).replace("%%", "%")
    return psql(sql)


def write(rows, dry: bool) -> int:
    """[(id, imageUrl)] → база; каждая правка сперва в журнал отката."""
    if not rows:
        return 0
    if dry:
        for rec_id, image in rows[:10]:
            print("  было бы: %s ← %s" % (rec_id, image))
        return len(rows)
    # Порциями по 200: короткие транзакции не держат строки ленты, которые
    # в эту же секунду правят телефоны.
    for i in range(0, len(rows), 200):
        part = rows[i:i + 200]
        stamp = now_pb()
        with open(UNDO_LOG, "a") as f:
            for rec_id, _ in part:
                f.write(json.dumps({"id": rec_id, "imageUrl": "", "at": stamp}) + "\n")
        psql("BEGIN;\n" + "\n".join(set_image_sql(r, img, stamp) for r, img in part) + "\nCOMMIT;")
    return len(rows)


# ── свои видео: кадр из файла ───────────────────────────────────────────────

def frame(src: str, dst: str) -> bool:
    """Кадр на первой секунде (у коротких — первый), не шире 720."""
    for at in ("1", "0"):
        res = subprocess.run(
            ["nice", "-n", "19", "ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", at, "-i", src,
             "-frames:v", "1", "-vf", "scale='min(720,iw)':-2", "-q:v", "4", "-y", dst],
            capture_output=True, timeout=90)
        if res.returncode == 0 and os.path.exists(dst) and os.path.getsize(dst) > 1000:
            return True
    return False


class Superuser:
    """Временный суперюзер на время прохода — заводится, только когда есть работа."""

    def __enter__(self):
        self.email = "tmp-thumbs-%s@x.local" % secrets.token_hex(3)
        password = secrets.token_urlsafe(16)
        subprocess.run([PB_DIR + "/pocketbase", "superuser", "create", self.email, password],
                       cwd=PB_DIR, check=True, capture_output=True)
        req = urllib.request.Request(
            PB + "/api/collections/_superusers/auth-with-password",
            data=json.dumps({"identity": self.email, "password": password}).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            self.token = json.load(r)["token"]
        return self

    def __exit__(self, *exc):
        subprocess.run([PB_DIR + "/pocketbase", "superuser", "delete", self.email],
                       cwd=PB_DIR, check=False, capture_output=True)


def upload(token: str, path: str, uid: str, group_id: str) -> str:
    """Кадр → запись `media` вида `memories`, как кладёт телефон; ссылка `pb://`."""
    boundary = "----thumbs" + secrets.token_hex(8)
    body = b""
    for k, v in (("uid", uid), ("group_id", group_id), ("kind", "memories")):
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode()
    body += ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"thumb.jpg\"\r\n"
             "Content-Type: image/jpeg\r\n\r\n" % boundary).encode()
    with open(path, "rb") as f:
        body += f.read()
    body += ("\r\n--%s--\r\n" % boundary).encode()
    req = urllib.request.Request(PB + "/api/collections/media/records", data=body, method="POST", headers={
        "Authorization": token, "Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=60) as r:
        rec = json.load(r)
    return "pb://media/%s/%s" % (rec["id"], rec["file"])


def own_videos(limit: int, since_days, dry: bool) -> int:
    sys.path.insert(0, TOOLS)
    from pb_storage import Source  # noqa: E402 — живёт рядом на сервере

    try:
        failed = set(json.load(open(STATE)))
    except (OSError, ValueError):
        failed = set()
    rows = [r for r in candidates(True, limit * 3, since_days) if r[0] not in failed][:limit]
    if not rows:
        return 0
    if dry:
        for r in rows[:10]:
            print("  было бы: кадр для %s из %s" % (r[0], r[3]))
        return len(rows)
    done = []
    with Superuser() as su, tempfile.TemporaryDirectory(prefix="mthumb_") as tmp:
        for rec_id, group_id, uid, video in rows:
            ref = pb_ref(video)
            ok = False
            if ref:
                with Source(*ref) as src:
                    jpg = os.path.join(tmp, rec_id + ".jpg")
                    if src.path and frame(src.path, jpg):
                        try:
                            done.append((rec_id, upload(su.token, jpg, uid, group_id)))
                            ok = True
                        except Exception as e:  # noqa: BLE001 — запись остаётся без обложки
                            print("  заливка %s: %s" % (rec_id, e), file=sys.stderr)
            if not ok:
                failed.add(rec_id)
    write(done, False)
    with open(STATE, "w") as f:
        json.dump(sorted(failed), f)
    return len(done)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--links", action="store_true", help="ссылки на ролики")
    ap.add_argument("--videos", type=int, default=0, help="сколько своих видео за проход")
    ap.add_argument("--all", action="store_true", help="вся история, а не последние сутки")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    since = None if a.all else 2
    t0 = time.time()
    links = 0
    if a.links:
        rows = []
        for rec_id, _, _, video in candidates(False, 100000, since):
            img = link_thumb(video)
            if img:
                rows.append((rec_id, img))
        links = write(rows, a.dry_run)
    vids = own_videos(a.videos, since, a.dry_run) if a.videos else 0
    if links or vids or a.dry_run:
        print("%s ссылки: %d, свои видео: %d, %.1f с" % (now_pb(), links, vids, time.time() - t0))


if __name__ == "__main__":
    main()
