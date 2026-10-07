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

  * TikTok, ВК и известные площадки (07.10.2026): адрес обложки берётся
    снаружи — oEmbed TikTok через посредника, данные плеера ВК, og:image
    страницы, — а кадр ложится записью `media`, как у своего видео.

Запуск на сервере (cron, раз в 10 минут, своими видео по 12 штук за проход):
  memory_thumbs.py --links --videos 12 --tiktok 20
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
import urllib.error
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


# ── TikTok: обложка через oEmbed ─────────────────────────────────────────────

def is_tiktok(url: str) -> bool:
    try:
        u = urllib.parse.urlparse((url or "").strip())
    except ValueError:
        return False
    host = (u.hostname or "").lower()
    return u.scheme in ("http", "https") and (host == "tiktok.com" or host.endswith(".tiktok.com"))


def tiktok_is_short(url: str) -> bool:
    host = (urllib.parse.urlparse(url or "").hostname or "").lower()
    return host in ("vm.tiktok.com", "vt.tiktok.com")


def tiktok_canonical(location: str) -> str:
    """Куда ведёт короткая ссылка → адрес ролика без хвоста; удалённый ролик
    ведёт на главную TikTok — тогда ''."""
    try:
        u = urllib.parse.urlparse(location or "")
    except ValueError:
        return ""
    m = re.match(r"^/(@[^/]*)/(video|photo)/(\d{6,25})", u.path)
    if not m or not is_tiktok(location):
        return ""
    return "https://www.tiktok.com/%s/%s/%s" % m.groups()


def tiktok_oembed_url(url: str) -> str:
    """Адрес для oEmbed: фото-пост по /photo/ он не отдаёт (400), а по
    /video/ с тем же номером — отдаёт. Короткая ссылка идёт как есть."""
    full = tiktok_canonical(url)
    return full.replace("/photo/", "/video/") if full else url


def unblur(url: str) -> str:
    """Яндекс Видео отдаёт обложку с размытием (`blur`, `shower`) — снимаем."""
    u = urllib.parse.urlparse(url)
    if not (u.hostname or "").endswith("avatars.mds.yandex.net"):
        return url
    q = [(k, v) for k, v in urllib.parse.parse_qsl(u.query, keep_blank_values=True) if k not in ("blur", "shower")]
    return urllib.parse.urlunparse(u._replace(query=urllib.parse.urlencode(q, safe="-")))


def tiktok_thumb_of(oembed) -> str:
    """Адрес обложки из ответа oEmbed — только https и только сеть TikTok:
    по нему сервер пойдёт качать картинку, внутренний адрес туда не пустим."""
    url = oembed.get("thumbnail_url") if isinstance(oembed, dict) else None
    if not isinstance(url, str):
        return ""
    try:
        u = urllib.parse.urlparse(url)
    except ValueError:
        return ""
    host = (u.hostname or "").lower()
    ok = re.search(r"(^|\.)tiktokcdn(-[a-z]+)?\.com$", host) or re.search(r"(^|\.)tiktok\.com$", host)
    return url if u.scheme == "https" and ok else ""


# ── ВК Видео: обложка из встраиваемого плеера ───────────────────────────────

_VK_HOST = re.compile(r"(^|\.)(vk\.com|vk\.ru|vkvideo\.ru)$")
_VK_PATH = re.compile(r"/(?:video|clip)(-?\d+)_(\d+)")
_VK_Z = re.compile(r"(?:video|clip)(-?\d+)_(\d+)")


def vk_video_ids(url: str):
    """Ссылка на ролик ВК → (владелец, номер, ключ доступа); иначе None."""
    try:
        u = urllib.parse.urlparse((url or "").strip())
    except ValueError:
        return None
    if u.scheme not in ("http", "https") or not _VK_HOST.search((u.hostname or "").lower()):
        return None
    q = urllib.parse.parse_qs(u.query)
    if u.path.rstrip("/").endswith("video_ext.php"):
        oid, vid = (q.get("oid") or [""])[0], (q.get("id") or [""])[0]
        if re.fullmatch(r"-?\d+", oid) and vid.isdigit():
            return oid, vid, re.sub(r"[^A-Za-z0-9]", "", (q.get("hash") or [""])[0])
        return None
    m = _VK_PATH.search(u.path) or _VK_Z.search((q.get("z") or [""])[0])
    return (m.group(1), m.group(2), "") if m else None


def vk_poster_of(html: str) -> str:
    """Обложка из данных плеера: поле `image` — список размеров. Берём без
    полей по краям и самый маленький не уже 720 (4096 точек — лишние
    мегабайты). `first_frame` не годится: у ролика с затемнения он чёрный."""
    dec = json.JSONDecoder()
    best = None
    for m in re.finditer(r'"image":\[', html or ""):
        try:
            arr, _ = dec.raw_decode(html[m.end() - 1:])
        except ValueError:
            continue
        for x in arr if isinstance(arr, list) else []:
            if not isinstance(x, dict):
                continue
            url, w = x.get("url"), x.get("width") or 0
            host = (urllib.parse.urlparse(url).hostname or "") if isinstance(url, str) else ""
            if not re.search(r"(^|\.)(vkuserphoto\.ru|userapi\.com|vkuser\.net|vk\.me)$", host):
                continue
            # У старых роликов обложка только с полями по краям — берём и её,
            # но после любой обложки без полей.
            key = (1 if x.get("with_padding") else 0,) + ((0, w) if w >= 720 else (1, -w))
            if best is None or key < best[0]:
                best = (key, url)
    return best[1] if best else ""


# ── прочие площадки: og:image страницы ──────────────────────────────────────
#
# Только известные площадки: у пиратских кинотеатров og:image — реклама или
# логотип, а страницы тянутся медленно и с чужими скриптами.

_PAGE_HOSTS = re.compile(
    r"(^|\.)(kinopoisk\.ru|music\.yandex\.ru|pin\.it|pinterest\.[a-z.]+|twitch\.tv|ok\.ru|dzen\.ru|"
    r"vimeo\.com|dailymotion\.com|rutube\.ru)$")


def page_thumb_host(url: str) -> bool:
    try:
        u = urllib.parse.urlparse((url or "").strip())
    except ValueError:
        return False
    host = (u.hostname or "").lower()
    if u.scheme not in ("http", "https"):
        return False
    if re.search(r"(^|\.)yandex\.ru$", host) and host != "music.yandex.ru":
        return u.path.startswith("/video")
    return bool(_PAGE_HOSTS.search(host))


def og_image_of(html: str) -> str:
    import html as _html
    for pat in (r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)(?::url)?["\'][^>]*?content=["\']([^"\']+)',
                r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*?(?:property|name)=["\'](?:og:image|twitter:image)'):
        m = re.search(pat, html or "", re.I)
        if m:
            url = _html.unescape(m.group(1)).strip()
            if not url.startswith(("http://", "https://")):
                return ""
            # Логотип площадки вместо кадра (Rutube на плейлисте) — не обложка.
            if re.search(r"/static/.*logo|ogimglogo", url, re.I):
                return ""
            return url
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
        # Только буквы и цифры: пароль с дефисом впереди командная строка
        # PocketBase принимает за флаг, суперюзера не заводит и отвечает
        # кодом 0 — вход потом получал 400 (05.10.2026).
        password = secrets.token_hex(16)
        subprocess.run([PB_DIR + "/pocketbase", "superuser", "create", self.email, password],
                       cwd=PB_DIR, check=True, capture_output=True)
        try:
            req = urllib.request.Request(
                PB + "/api/collections/_superusers/auth-with-password",
                data=json.dumps({"identity": self.email, "password": password}).encode(),
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as r:
                self.token = json.load(r)["token"]
        except Exception:
            # __exit__ при сбое в __enter__ не зовётся — убираем за собой сами.
            self._drop()
            raise
        return self

    def _drop(self):
        subprocess.run([PB_DIR + "/pocketbase", "superuser", "delete", self.email],
                       cwd=PB_DIR, check=False, capture_output=True)

    def __exit__(self, *exc):
        self._drop()


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


# ── TikTok: кадр через oEmbed ───────────────────────────────────────────────
#
# Открытой обложки по номеру ролика у TikTok нет (07.10.2026, «нет превью на
# ТТ видео» — в базе ни у одной записи TikTok обложки не было). Адрес даёт
# oEmbed, но страницы и данные TikTok закрыты для российских адресов, поэтому
# oEmbed идёт через посредника на Contabo (там пускают только tiktok.com).
# Саму картинку CDN TikTok отдаёт в Россию напрямую. Адрес из oEmbed живёт
# двое суток (x-expires), поэтому кадр ложится к нам записью `media`, как
# кадр своего видео.

TT_PROXY = "http://169.58.6.158:8899"
TT_STATE = "/opt/pocketbase/pb_data/.memory_thumbs_tiktok.json"
TT_TRIES = 3
_UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36"


def _tt_oembed(url: str) -> dict:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({"https": TT_PROXY, "http": TT_PROXY}))
    req = urllib.request.Request(
        "https://www.tiktok.com/oembed?url=" + urllib.parse.quote(url, safe=""),
        headers={"User-Agent": _UA})
    with opener.open(req, timeout=20) as r:
        return json.loads(r.read(200_000).decode("utf-8", "replace"))


def _public_url(url: str) -> bool:
    """http(s) и только публичные адреса: обложку качает сервер, и адрес
    из чужой страницы не должен увести его во внутреннюю сеть."""
    import ipaddress
    import socket
    try:
        u = urllib.parse.urlparse(url)
        if u.scheme not in ("http", "https") or not u.hostname or u.port not in (None, 80, 443):
            return False
        for info in socket.getaddrinfo(u.hostname, None):
            if not ipaddress.ip_address(info[4][0]).is_global:
                return False
        return True
    except (ValueError, OSError):
        return False


class _CheckedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _public_url(newurl):
            raise urllib.error.URLError("redirect to non-public address")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _download(url: str, dst: str) -> bool:
    if not _public_url(url):
        return False
    opener = urllib.request.build_opener(_CheckedRedirect())
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    with opener.open(req, timeout=20) as r:
        data = r.read(5_000_001)
    if len(data) > 5_000_000 or len(data) < 1000:
        return False
    with open(dst, "wb") as f:
        f.write(data)
    return True


def _vk_embed(oid: str, vid: str, key: str) -> str:
    """Встраиваемый плеер ВК. Без кук он гоняет по перенаправлениям по кругу,
    поэтому куки держатся на время запроса."""
    import http.cookiejar
    q = "oid=%s&id=%s" % (oid, vid) + ("&hash=" + key if key else "")
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
                                         _CheckedRedirect())
    req = urllib.request.Request("https://vkvideo.ru/video_ext.php?" + q, headers={"User-Agent": _UA})
    with opener.open(req, timeout=20) as r:
        return r.read(3_000_000).decode("utf-8", "replace")


LINK_FETCHER = "http://127.0.0.1:8110/preview?url="


def _page(url: str) -> str:
    """Страница через link_fetcher: он сам разбирает перенаправления и не
    пускает во внутреннюю сеть (тот же сервис тянет карточки товаров)."""
    with urllib.request.urlopen(LINK_FETCHER + urllib.parse.quote(url, safe=""), timeout=30) as r:
        d = json.load(r)
    return d.get("html") or "" if d.get("ok") else ""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def _tt_resolve(short: str) -> str:
    """Куда ведёт короткая ссылка TikTok. Перенаправление отдаётся в Россию
    напрямую, посредник не нужен."""
    opener = urllib.request.build_opener(_NoRedirect())
    try:
        opener.open(urllib.request.Request(short, headers={"User-Agent": _UA}), timeout=15)
    except urllib.error.HTTPError as e:
        if e.code in (301, 302, 303, 307, 308):
            return tiktok_canonical(e.headers.get("Location", ""))
    return ""


def _tiktok_thumb(url: str) -> str:
    try:
        thumb = tiktok_thumb_of(_tt_oembed(tiktok_oembed_url(url)))
    except urllib.error.HTTPError as e:
        # Короткую ссылку oEmbed не понимает (400) — раскрываем и спрашиваем снова.
        if e.code != 400 or not tiktok_is_short(url):
            raise
        thumb = ""
    if not thumb and tiktok_is_short(url):
        full = _tt_resolve(url)
        if full:
            time.sleep(1)
            thumb = tiktok_thumb_of(_tt_oembed(tiktok_oembed_url(full)))
    return thumb


def remote_thumb(url: str) -> str:
    """Адрес обложки ролика с чужой площадки; '' — взять неоткуда."""
    if is_tiktok(url):
        return _tiktok_thumb(url)
    ids = vk_video_ids(url)
    if ids:
        return vk_poster_of(_vk_embed(*ids))
    if page_thumb_host(url):
        return unblur(og_image_of(_page(url)))
    return ""


def wants_remote(url: str) -> bool:
    return is_tiktok(url) or vk_video_ids(url) is not None or page_thumb_host(url)


def remote_videos(limit: int, since_days, dry: bool) -> int:
    """TikTok, ВК и известные площадки: адрес обложки берётся снаружи, а кадр
    ложится к нам записью `media` — чужие адреса картинок подписаны и живут
    от двух суток (TikTok) до неизвестно скольких."""
    try:
        tries = json.load(open(TT_STATE))
    except (OSError, ValueError):
        tries = {}
    rows = [r for r in candidates(False, 100000, since_days)
            if wants_remote(r[3]) and tries.get(r[0], 0) < TT_TRIES][:limit]
    if not rows:
        return 0
    if dry:
        for r in rows[:10]:
            print("  было бы: обложка для %s из %s" % (r[0], r[3]))
        return len(rows)
    done = []
    with Superuser() as su, tempfile.TemporaryDirectory(prefix="mthumb_ext_") as tmp:
        for i, (rec_id, group_id, uid, video) in enumerate(rows):
            if i:
                time.sleep(1.5)  # площадки режут частые запросы
            ok = False
            try:
                thumb = remote_thumb(video)
                raw = os.path.join(tmp, rec_id + ".raw")
                jpg = os.path.join(tmp, rec_id + ".jpg")
                if thumb and _download(thumb, raw) and frame(raw, jpg):
                    done.append((rec_id, upload(su.token, jpg, uid, group_id)))
                    ok = True
            except Exception as e:  # noqa: BLE001 — запись остаётся без обложки
                print("  обложка %s: %s" % (rec_id, e), file=sys.stderr)
            if ok:
                tries.pop(rec_id, None)
            else:
                tries[rec_id] = tries.get(rec_id, 0) + 1
    write(done, False)
    with open(TT_STATE, "w") as f:
        json.dump(tries, f)
    return len(done)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--links", action="store_true", help="ссылки на ролики")
    ap.add_argument("--videos", type=int, default=0, help="сколько своих видео за проход")
    # --tiktok — прежнее имя, им записан крон 07.10.2026.
    ap.add_argument("--remote", "--tiktok", dest="remote", type=int, default=0,
                    help="сколько роликов TikTok, ВК и других площадок за проход")
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
    ext = remote_videos(a.remote, since, a.dry_run) if a.remote else 0
    if links or vids or ext or a.dry_run:
        print("%s ссылки: %d, свои видео: %d, площадки: %d, %.1f с"
              % (now_pb(), links, vids, ext, time.time() - t0))


if __name__ == "__main__":
    main()
