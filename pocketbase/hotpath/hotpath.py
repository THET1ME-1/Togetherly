#!/usr/bin/env python3
"""Togetherly hotpath — PB-совместимый API горячих коллекций поверх Postgres.

Зачем: единственный писатель PocketBase упирался в ~6 записей/с (цепочка хуков
живёт на пути записи), и очередь клала весь прод — регистрацию, профиль, коды.
Горячие коллекции вынесены сюда: Caddy заворачивает их маршруты
`/api/collections/<имя>/records*` на 127.0.0.1:8120, приложение разницы не
видит — формы запросов и ответов повторяют PocketBase один в один, вплоть до
`Value must be unique` (на неё смотрит `alreadyExists` в pb_errors.dart).

Хранение — Postgres из self-hosted Supabase (127.0.0.1:5433, база togetherly).
Realtime — публикация в Centrifugo в канал `pair:<group_id>` тем же телом
`{event, collection, record}`, что шлёт centrifugo.pb.js.

Аутентификация: подпись токена PocketBase проверяется ЗДЕСЬ, тем же ключом,
что использует сам PB, — HS256 с ключом `users.tokenKey + authToken.secret`
коллекции (формула из core/record_tokens.go, живьём проверена смоуком:
PB принимает токен, подписанный этим же способом). tokenKey и `group_ids`
читаются напрямую из SQLite PocketBase в read-only: ходить в REST PB нельзя
по двум причинам — его очередь записи в коллапсе и есть цель от неё не
зависеть, а `group_ids` — скрытое поле, REST его не отдаёт даже владельцу.
Членством в группе проверяются все операции — ровно как правила коллекций
после миграции 13.08 (`@request.auth.group_ids.id ?= group_id`). Кэш на две
минуты; протухание tokenKey (выход из аккаунта) подхватывается на промахе.

Что повторено из серверной обвязки PB для вынесенных коллекций:
  • страж чата (chat_guard.pb.js): не-автор правит только `reactions` и
    `voice_heard_at`, жёсткое удаление — автору;
  • счётчик `groups.messages_count` (counters.pb.js): +1 на создание, −1 на
    жёсткое удаление; пишется прямо в SQLite PB фоновым воркером с батчингом;
  • пуши (push_apns.pb.js + apns_push.js): чат и настроение — тем же релеям
    APNs/FCM, с теми же текстами, порогом «на связи» и чисткой мёртвых токенов;
  • колонка `updated` (autodate PB): заполняется здесь, формат PB
    `YYYY-MM-DD HH:MM:SS.mmmZ` — по ней ходит водяной знак синхронизации.
"""

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import sqlite3
import time

import asyncpg
import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

log = logging.getLogger("hotpath")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

PG_DSN = os.environ["HOTPATH_PG_DSN"]
PB_DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
CENT_API = os.environ.get("CENTRIFUGO_API", "http://127.0.0.1:9000/api")
CENT_KEY = os.environ.get("CENTRIFUGO_API_KEY", "")
APNS_RELAY = os.environ.get("APNS_RELAY", "http://127.0.0.1:8096/push")
FCM_RELAY = os.environ.get("FCM_RELAY", "http://127.0.0.1:8100/push")
LISTEN_PORT = int(os.environ.get("HOTPATH_PORT", "8120"))
ONLINE_WINDOW_MS = 2 * 60 * 1000

# Типы колонок: text | num | bool | json | auto (updated, ведём сами).
COLLECTIONS = {
    "canvas_strokes": {
        "collection_id": os.environ.get("CID_CANVAS_STROKES", ""),
        "columns": {
            "canvas_id": "text", "group_id": "text", "order_index": "num",
            "deleted": "bool", "data": "json",
        },
        "sortable": {"order_index", "id"},
        "filterable": {"id", "group_id", "canvas_id", "deleted"},
        "create_owner_field": None,
        "guard": None,
        "delete_guard": None,
        "after_create": None,
        "after_delete": None,
        "default_sort": "order_index ASC, id ASC",
    },
    "chat_messages": {
        "collection_id": os.environ.get("CID_CHAT_MESSAGES", "pbc_102036695"),
        "columns": {
            "color": "num", "deleted": "bool", "edited_ts": "num", "face": "text",
            "face_x": "num", "face_y": "num", "group_id": "text", "pin_id": "text",
            "pin_thumb": "text", "pin_title": "text", "reactions": "json",
            "reply_to_id": "text", "reply_to_name": "text", "reply_to_text": "text",
            "text": "text", "ts": "num", "user_name": "text", "user_uid": "text",
            "updated": "auto", "text_color": "num", "voice_url": "text",
            "voice_ms": "num", "voice_peaks": "text", "voice_heard_at": "num",
        },
        "sortable": {"ts", "updated", "id"},
        "filterable": {"id", "group_id", "user_uid", "deleted", "ts", "updated"},
        "create_owner_field": None,
        "guard": "chat",
        "delete_guard": "author",
        "after_create": "chat",
        "after_delete": "chat",
        "default_sort": "id ASC",
    },
    "memories": {
        "collection_id": os.environ.get("CID_MEMORIES", "pbc_1337100956"),
        "columns": {
            "author_avatar": "text", "author_name": "text", "author_uid": "text",
            "created_at": "date", "data": "json", "deleted": "bool",
            "edited_at": "date", "group_id": "text", "is_pinned": "bool",
            "type": "text", "updated": "auto", "tz": "text", "added_at": "date",
        },
        "sortable": {"created_at", "updated", "added_at", "id"},
        "filterable": {"id", "group_id", "author_uid", "deleted", "type",
                       "created_at", "updated", "is_pinned"},
        "create_owner_field": "author_uid",   # createRule: автор — только сам
        "guard": None,
        "delete_guard": None,
        "after_create": "memory",
        "after_delete": "memory",
        "default_sort": "id ASC",
    },
    "widget_data": {
        "collection_id": os.environ.get("CID_WIDGET_DATA", "pbc_3321224104"),
        "columns": {
            "avatar_url": "text", "data": "json", "display_name": "text",
            "gender": "text", "group_id": "text", "message": "text",
            "mood_emoji": "text", "mood_label": "text", "music_artist": "text",
            "music_cover_url": "text", "music_title": "text", "music_url": "text",
            "photo_for_partner_url": "text", "photo_for_partner_urls": "json",
            "photo_grid_count": "num", "photo_grid_urls": "json",
            "photo_url": "text", "status": "text", "updated_at": "date",
            "user_uid": "text", "updated": "auto", "plus": "bool",
        },
        "sortable": {"updated", "updated_at", "id"},
        "filterable": {"id", "group_id", "user_uid", "updated"},
        "create_owner_field": "user_uid",
        "guard": None,
        "delete_guard": None,
        "after_create": "widget",
        "after_delete": None,
        "default_sort": "id ASC",
    },
    "canvas_meta": {
        "collection_id": os.environ.get("CID_CANVAS_META", "pbc_2121884867"),
        "columns": {
            "bg_color": "num", "canvas_id": "text", "canvas_rotation": "num",
            "clear_version": "num", "group_id": "text", "updated_at": "date",
            "coloring_id": "text", "coloring_mode": "text",
            "coloring_done": "json", "coloring_swap": "bool",
        },
        "sortable": {"updated_at", "id"},
        "filterable": {"id", "group_id", "canvas_id"},
        "create_owner_field": None,
        "guard": None,
        "delete_guard": None,
        "after_create": None,
        "after_delete": None,
        "default_sort": "id ASC",
    },
    "mood_entries": {
        "collection_id": os.environ.get("CID_MOOD_ENTRIES", "pbc_1148030965"),
        "columns": {
            "group_id": "text", "image_path": "text", "label": "text",
            "mood_id": "text", "timestamp": "date", "user_uid": "text",
            "updated": "auto", "tz": "text",
        },
        "sortable": {"updated", "timestamp", "id"},
        "filterable": {"id", "group_id", "user_uid", "mood_id", "timestamp", "updated"},
        "create_owner_field": None,
        "guard": None,
        "delete_guard": None,
        "after_create": "mood",
        "after_delete": None,
        "default_sort": "id ASC",
    },
}

app = FastAPI(openapi_url=None, docs_url=None, redoc_url=None)
pg: asyncpg.Pool | None = None
cent_client: httpx.AsyncClient | None = None
push_client: httpx.AsyncClient | None = None
lite: sqlite3.Connection | None = None      # read-only: auth, группы, presence
lite_rw: sqlite3.Connection | None = None   # счётчики групп и чистка токенов
auth_secret = ""
_lite_lock = asyncio.Lock()
_counter_deltas: dict = {}                 # (group_id, поле) -> дельта

# ── совместимость с PocketBase: время и ошибки ───────────────────────────────


def now_pb() -> str:
    t = time.time()
    return time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t)) + f".{int(t * 1000) % 1000:03d}Z"


def _err(code: int, message: str, data: dict | None = None) -> JSONResponse:
    return JSONResponse(
        {"code": code, "message": message, "data": data or {}}, status_code=code
    )


# ── аутентификация ───────────────────────────────────────────────────────────

_AUTH_TTL = 120.0
_AUTH_CACHE_MAX = 30000
_auth_cache: dict[str, tuple[float, str, frozenset]] = {}
_USERS_COLLECTION_ID = "_pb_users_auth_"


def _jwt_payload(token: str) -> dict:
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part))
    except Exception:
        return {}


def _user_has_plus(uid: str) -> bool:
    try:
        row = lite.execute("SELECT plus FROM users WHERE id = ?", (uid,)).fetchone()
        return bool(row and row[0])
    except sqlite3.Error:
        return False


def _lite_user(uid: str) -> tuple[str, frozenset] | None:
    """tokenKey и группы юзера из SQLite PocketBase (read-only, WAL пускает
    читателей всегда). group_ids хранится json-текстом, бывает и голой строкой."""
    row = lite.execute(
        "SELECT tokenKey, group_ids FROM users WHERE id = ?", (uid,)
    ).fetchone()
    if row is None:
        return None
    raw = row[1]
    groups: list = []
    if isinstance(raw, str) and raw:
        try:
            parsed = json.loads(raw)
            groups = parsed if isinstance(parsed, list) else [parsed]
        except ValueError:
            groups = [raw]
    return row[0], frozenset(str(g) for g in groups if g)


async def _auth(request: Request) -> tuple[str, frozenset] | None:
    """Токен -> (uid, группы) или None. Подпись сверяется локально — той же
    формулой, что у PocketBase: HS256(tokenKey записи + секрет коллекции)."""
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not token:
        return None
    now = time.monotonic()
    hit = _auth_cache.get(token)
    if hit and hit[0] > now:
        return hit[1], hit[2]

    payload = _jwt_payload(token)
    uid = str(payload.get("id") or "")
    if (
        not uid
        or payload.get("type") != "auth"
        or payload.get("collectionId") != _USERS_COLLECTION_ID
        or not isinstance(payload.get("exp"), int)
        or payload["exp"] <= int(time.time())
    ):
        return None
    found = await asyncio.to_thread(_lite_user, uid)
    if found is None:
        return None
    token_key, groups = found
    head, body, sig = token.split(".")
    want = base64.urlsafe_b64encode(
        hmac.new((token_key + auth_secret).encode(),
                 f"{head}.{body}".encode(), hashlib.sha256).digest()
    ).rstrip(b"=").decode()
    if not hmac.compare_digest(want, sig):
        return None
    if len(_auth_cache) >= _AUTH_CACHE_MAX:
        _auth_cache.clear()
    _auth_cache[token] = (now + _AUTH_TTL, uid, groups)
    return uid, groups


# ── записи: сериализация и разбор фильтров ───────────────────────────────────


def _new_id() -> str:
    # У PB тут дефолт 'r' || hex(randomblob(7)) — 15 символов.
    return "r" + secrets.token_hex(7)


def _num(v):
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def _record_json(col: str, row) -> dict:
    meta = COLLECTIONS[col]
    out = {
        "id": row["id"],
        "collectionId": meta["collection_id"],
        "collectionName": col,
    }
    for field, kind in meta["columns"].items():
        v = row[field]
        if kind == "num":
            out[field] = _num(v if v is not None else 0)
        elif kind == "bool":
            out[field] = bool(v)
        elif kind == "json":
            if isinstance(v, str):
                try:
                    v = json.loads(v)
                except ValueError:
                    v = None
            out[field] = v
        else:
            out[field] = v if v is not None else ""
    return out


_COND = re.compile(
    r"""^\s*\(*\s*(\w+)\s*(!=|>=|<=|=|>|<)\s*"""
    r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|(true|false)|(-?\d+(?:\.\d+)?))"""
    r"""\s*\)*\s*$"""
)
_OPS = {"=": "=", "!=": "<>", ">": ">", "<": "<", ">=": ">=", "<=": "<="}


def _parse_filter(expr: str, allowed: set) -> list[tuple[str, str, object]]:
    """Разбирает конъюнкцию условий `f = 'v' && f2 > 'w' && f3 != true` —
    ровно то подмножество синтаксиса PB, которым пользуется приложение
    (включая водяной знак `updated > '...'`). Неразбираемое — ValueError."""
    out = []
    if not expr:
        return out
    for part in expr.split("&&"):
        m = _COND.match(part)
        if not m:
            raise ValueError(part)
        field, op, v_sq, v_dq, v_bool, v_numlit = m.groups()
        if field not in allowed:
            raise ValueError(field)
        if v_bool is not None:
            val: object = v_bool == "true"
        elif v_numlit is not None:
            val = float(v_numlit)
        else:
            raw = v_sq if v_sq is not None else (v_dq or "")
            val = raw.replace("\\'", "'").replace('\\"', '"')
        out.append((field, _OPS[op], val))
    return out


def _coerce(col: str, field: str, val: object) -> object:
    """Значение фильтра к типу колонки: сравнение с num-колонкой числом."""
    kind = COLLECTIONS[col]["columns"].get(field)
    if kind == "num" and isinstance(val, str):
        try:
            return float(val)
        except ValueError:
            return val
    if kind == "bool" and isinstance(val, str):
        return val == "true"
    return val


# ── realtime и пуши ──────────────────────────────────────────────────────────


async def _publish(col: str, event: str, record: dict) -> None:
    gid = record.get("group_id") or ""
    if not gid or not CENT_KEY:
        return
    try:
        await cent_client.post(
            "/publish",
            json={
                "channel": f"pair:{gid}",
                "data": {"event": event, "collection": col, "record": record},
            },
            headers={"X-API-Key": CENT_KEY},
        )
    except httpx.HTTPError:
        pass  # realtime — best effort, как и в хуке


def _push_targets(group_id: str, author_uid: str) -> list[dict]:
    """Кому слать пуш: участники группы, кроме автора и тех, кто на связи.
    Всё читается из SQLite PB одним заходом (тот же источник, что у хука)."""
    g = lite.execute(
        "SELECT members, disbanded FROM groups WHERE id = ?", (group_id,)
    ).fetchone()
    if g is None or g[1]:
        return []
    try:
        members = json.loads(g[0] or "[]") or []
    except ValueError:
        members = []
    now_ms = int(time.time() * 1000)
    out = []
    for uid in members:
        uid = str(uid or "")
        if not uid or uid == author_uid:
            continue
        seen = lite.execute(
            "SELECT seen_at FROM user_presence WHERE user_uid = ?", (uid,)
        ).fetchone()
        if seen and seen[0]:
            raw = str(seen[0])
            try:
                ms = int(float(raw))
            except ValueError:
                try:
                    ms = int(time.mktime(time.strptime(raw[:19], "%Y-%m-%d %H:%M:%S")) * 1000)
                except ValueError:
                    ms = 0
            if ms and now_ms - ms < ONLINE_WINDOW_MS:
                continue  # на связи — баннер нарисует живое приложение
        u = lite.execute(
            "SELECT apns_token, apns_sandbox, fcm_token, apns_bg_ms FROM users WHERE id = ?",
            (uid,),
        ).fetchone()
        if u is None:
            continue
        out.append({"uid": uid, "apns": u[0] or "", "sandbox": bool(u[1]),
                    "fcm": u[2] or "", "bg_ms": int(u[3] or 0)})
    return out


def _forget_token(uid: str, field: str) -> None:
    try:
        lite_rw.execute(f"UPDATE users SET {field} = '' WHERE id = ?", (uid,))
        lite_rw.commit()
    except sqlite3.Error:
        pass  # попробуем в следующий раз


async def _notify_group(group_id: str, author_uid: str, title: str, body: str, thread: str) -> None:
    """Пуш всем в группе, кроме автора — как notifyGroup в apns_push.js."""
    try:
        targets = await asyncio.to_thread(_push_targets, group_id, author_uid)
    except Exception as e:
        log.warning("push targets %s: %s", group_id, e)
        return
    for t in targets:
        if t["apns"]:
            try:
                r = await push_client.post(APNS_RELAY, json={
                    "token": t["apns"], "title": title, "body": body,
                    "thread": thread, "sandbox": t["sandbox"], "data": {"kind": thread},
                })
                if (r.json() or {}).get("gone"):
                    await asyncio.to_thread(_forget_token, t["uid"], "apns_token")
            except Exception as e:
                log.warning("apns %s: %s", t["uid"], e)
        if t["fcm"]:
            try:
                r = await push_client.post(FCM_RELAY, json={
                    "token": t["fcm"], "title": title, "body": body,
                    # Одна строка на вид события — как в apns_push.js.
                    "tag": thread, "data": {"kind": thread},
                })
                if (r.json() or {}).get("gone"):
                    await asyncio.to_thread(_forget_token, t["uid"], "fcm_token")
            except Exception as e:
                log.warning("fcm %s: %s", t["uid"], e)


MIN_WAKE_GAP_MS = 15 * 60 * 1000


def _mark_woke(uid: str, now_ms: int) -> None:
    try:
        lite_rw.execute("UPDATE users SET apns_bg_ms = ? WHERE id = ?", (now_ms, uid))
        lite_rw.commit()
    except sqlite3.Error:
        pass  # отметка не критична: в худшем случае разбудим раньше


async def _wake_group(group_id: str, author_uid: str, kind: str = "widgets") -> None:
    """Тихий пуш «проснись и обнови виджеты» — перенос wakeGroup/wakeUp из
    apns_push.js. Apple лимитирует такие пуши, поэтому будим не чаще раза в
    15 минут на устройство и только тех, кто сейчас не на связи."""
    try:
        targets = await asyncio.to_thread(_push_targets, group_id, author_uid)
    except Exception as e:
        log.warning("wake targets %s: %s", group_id, e)
        return
    now_ms = int(time.time() * 1000)
    for t in targets:
        if not t["apns"] and not t["fcm"]:
            continue
        if t["bg_ms"] and now_ms - t["bg_ms"] < MIN_WAKE_GAP_MS:
            continue
        woke = False
        if t["apns"]:
            try:
                r = await push_client.post(APNS_RELAY, json={
                    "token": t["apns"], "silent": True,
                    "sandbox": t["sandbox"], "data": {"kind": kind}})
                a = r.json() or {}
                if a.get("gone"):
                    await asyncio.to_thread(_forget_token, t["uid"], "apns_token")
                elif a.get("ok"):
                    woke = True
            except Exception as e:
                log.warning("apns wake %s: %s", t["uid"], e)
        if t["fcm"]:
            try:
                r = await push_client.post(FCM_RELAY, json={
                    "token": t["fcm"], "silent": True, "data": {"kind": kind}})
                a = r.json() or {}
                if a.get("gone"):
                    await asyncio.to_thread(_forget_token, t["uid"], "fcm_token")
                elif a.get("ok"):
                    woke = True
            except Exception as e:
                log.warning("fcm wake %s: %s", t["uid"], e)
        if woke:
            await asyncio.to_thread(_mark_woke, t["uid"], now_ms)


def _chat_push_text(rec: dict) -> str:
    text = (rec.get("text") or "").strip()
    if text:
        return text[:117] + "…" if len(text) > 120 else text
    return "Голосовое сообщение" if rec.get("voice_url") else "Сообщение"


async def _after_create(col: str, rec: dict) -> None:
    kind = COLLECTIONS[col]["after_create"]
    if kind == "chat":
        if not rec.get("deleted"):
            _count(rec.get("group_id") or "", +1)
            await _notify_group(
                rec.get("group_id") or "", rec.get("user_uid") or "",
                (rec.get("user_name") or "Партнёр"), _chat_push_text(rec), "chat")
    elif kind == "memory":
        if not rec.get("deleted"):
            _count(rec.get("group_id") or "", +1, field="memories_count")
            await _notify_group(
                rec.get("group_id") or "", rec.get("author_uid") or "",
                (rec.get("author_name") or "Партнёр"), "Добавил воспоминание", "memory")
    elif kind == "widget":
        # Тихий пуш «обнови виджеты» — как wakeGroup в apns_push.js.
        await _wake_group(rec.get("group_id") or "", rec.get("user_uid") or "")
    elif kind == "mood":
        label = (rec.get("label") or "").strip()
        await _notify_group(
            rec.get("group_id") or "", rec.get("user_uid") or "",
            "Настроение партнёра",
            f"Сегодня: {label}" if label else "Партнёр отметил настроение", "mood")


def _after_delete(col: str, rec: dict) -> None:
    kind = COLLECTIONS[col]["after_delete"]
    if kind == "chat":
        _count(rec.get("group_id") or "", -1)
    elif kind == "memory":
        _count(rec.get("group_id") or "", -1, field="memories_count")


# ── счётчик групп: батч-воркер поверх SQLite PB ──────────────────────────────


def _count(group_id: str, delta: int, field: str = "messages_count") -> None:
    if group_id:
        key = (group_id, field)
        _counter_deltas[key] = _counter_deltas.get(key, 0) + delta


def _flush_counters_sync(deltas: dict) -> None:
    # BEGIN IMMEDIATE: наша транзакция только пишет, деферред-снапшот ей не
    # нужен, а мгновенный захват замка сводит окно к миллисекундам.
    lite_rw.execute("BEGIN IMMEDIATE")
    try:
        for (gid, field), d in deltas.items():
            lite_rw.execute(
                f"UPDATE groups SET {field} = MAX(0, COALESCE({field}, 0) + ?) "
                "WHERE id = ?", (d, gid),
            )
        lite_rw.commit()
    except BaseException:
        lite_rw.rollback()
        raise


async def _counter_worker() -> None:
    """Копит дельты messages_count и раз в минуту пишет одной транзакцией.

    Раз в МИНУТУ, а не чаще, намеренно: каждый посторонний коммит в SQLite
    протухает деферред-снапшоты письменных транзакций самого PocketBase — тот
    уходит в лесенку ретраев по ~50 секунд, и регистрация с профилем виснут
    (поймано живьём 14.08: сброс раз в 2с давал константные 48с на любую
    запись PB при свободном замке). Свежесть счётчика столько не стоит:
    couple_stats и так считает чат из Postgres."""
    global _counter_deltas
    while True:
        await asyncio.sleep(60)
        if not _counter_deltas:
            continue
        batch, _counter_deltas = _counter_deltas, {}
        try:
            await asyncio.to_thread(_flush_counters_sync, batch)
        except sqlite3.Error as e:
            log.warning("counters отложены (%s)", e)
            for key, d in batch.items():  # вернуть в очередь
                _counter_deltas[key] = _counter_deltas.get(key, 0) + d


# ── маршруты ─────────────────────────────────────────────────────────────────


@app.get("/healthz")
async def healthz():
    async with pg.acquire() as c:
        await c.fetchval("SELECT 1")
    return {"ok": True}


@app.get("/internal/count")
async def internal_count(col: str, group_id: str = "", mode: str = ""):
    """Счётчики для серверной кухни (couple_stats.pb.js, insights_aggregate.py).

    Без параметров — «сколько групп пользуются» (DISTINCT group_id, живые
    записи), mode=rows — «сколько всего строк» (как COUNT(*) в прежнем SQLite).
    Наружу не выходит: сервис слушает 127.0.0.1, а Caddy маршрутизирует сюда
    только /api/collections/<горячие>/records*.
    """
    if col not in COLLECTIONS:
        return _err(404, "The requested resource wasn't found.")
    has_deleted = "deleted" in COLLECTIONS[col]["columns"]
    not_deleted = "AND NOT deleted" if has_deleted else ""
    async with pg.acquire() as c:
        if group_id:
            n = await c.fetchval(
                f"SELECT COUNT(*) FROM {col} WHERE group_id = $1 {not_deleted}",
                group_id,
            )
        elif mode == "rows":
            n = await c.fetchval(f"SELECT COUNT(*) FROM {col}")
        else:
            n = await c.fetchval(
                f"SELECT COUNT(DISTINCT group_id) FROM {col} WHERE TRUE {not_deleted}"
            )
    return {"n": n}


# Локальное время автора отметки: UTC + пояс из `tz` (пустой пояс у легаси
# означает «в строке уже часы автора» — сдвиг не нужен). Повтор moodLocal
# из couple_stats.pb.js на диалекте Postgres.
_TS_OK = r"timestamp ~ '^\d{4}-\d{2}-\d{2}'"
_TS_UTC = "replace(replace(timestamp,'T',' '),'Z','')::timestamp"
_MOOD_LOCAL = (
    f"({_TS_UTC} + CASE WHEN tz ~ '^[+-][0-9]{{2}}:[0-9]{{2}}$' "
    "THEN tz::interval ELSE interval '0' END)"
)
_UTC_NOW = "(now() at time zone 'utc')"


@app.post("/internal/record")
async def internal_record(request: Request):
    """Серверная запись без токена: для хуков PB, которые сами кладут записи
    в вынесенные коллекции (салют из gifts.pb.js создаёт воспоминание).
    Наружу закрыто — Caddy сюда не маршрутизирует, слушаем только петлю."""
    try:
        body = await request.json()
        col = str(body.pop("collection", ""))
        assert col in COLLECTIONS
    except Exception:
        return _err(400, "Failed to create record.")
    meta = COLLECTIONS[col]
    rid = str(body.get("id") or "") or _new_id()
    cols, vals = ["id"], [rid]
    for field, kind in meta["columns"].items():
        v = body.get(field)
        cols.append(field)
        if kind == "auto":
            vals.append(now_pb())
        elif kind == "json":
            vals.append(json.dumps(v) if not isinstance(v, (str, type(None))) else v)
        elif kind == "num":
            vals.append(float(v or 0))
        elif kind == "bool":
            vals.append(bool(v))
        elif kind == "date":
            vals.append(str(v).replace("T", " ") if v else "")
        else:
            vals.append(str(v) if v is not None else "")
    ph = ", ".join(f"${i + 1}" for i in range(len(vals)))
    async with pg.acquire() as c:
        try:
            row = await c.fetchrow(
                f"INSERT INTO {col} ({', '.join(cols)}) VALUES ({ph}) RETURNING *", *vals)
        except asyncpg.UniqueViolationError:
            return _err(400, "Failed to create record.", {
                "id": {"code": "validation_not_unique", "message": "Value must be unique."}})
    rec = _record_json(col, row)
    asyncio.get_running_loop().create_task(_publish(col, "create", rec))
    asyncio.get_running_loop().create_task(_after_create(col, rec))
    return rec


@app.get("/internal/profiles")
async def internal_profiles(group_ids: str = "", limit: int = 60, offset: int = 0):
    """Лента профилей для админки (`/modapi/pb-profiles` в moderation.pb.js).

    Фильтр по группам приходит уже развёрнутым списком: разворачивать огрызок id
    по таблице groups остаётся на стороне PB — она живёт в SQLite."""
    limit = max(1, min(200, limit))
    offset = max(0, offset)
    gids = [g for g in group_ids.split(",") if g]
    async with pg.acquire() as c:
        if group_ids and not gids:
            return {"items": [], "total": 0}
        where, args = "TRUE", []
        if gids:
            args.append(gids)
            where = "group_id = ANY($1)"
        rows = await c.fetch(
            "SELECT group_id, user_uid, display_name, status, message, mood_label, "
            f"music_title, music_artist, avatar_url, updated FROM widget_data WHERE {where} "
            f"ORDER BY updated DESC LIMIT {limit} OFFSET {offset}", *args)
        total = await c.fetchval(f"SELECT COUNT(*) FROM widget_data WHERE {where}", *args)
    return {"items": [dict(r) for r in rows], "total": total}


@app.get("/internal/product-stats")
async def internal_product_stats():
    """Продуктовые срезы по вынесенным коллекциям — для insights_aggregate.py."""
    async with pg.acquire() as c:
        async def val(sql):
            return await c.fetchval(sql) or 0
        moods = await c.fetch(
            "SELECT mood_label AS k, COUNT(*)::int AS c FROM widget_data "
            "WHERE mood_label <> '' GROUP BY 1 ORDER BY c DESC LIMIT 30")
        return {
            "memory_authors": await val(
                "SELECT COUNT(DISTINCT author_uid) FROM memories WHERE NOT deleted"),
            "memories_rows": await val("SELECT COUNT(*) FROM memories"),
            "memories_groups": await val(
                "SELECT COUNT(DISTINCT group_id) FROM memories WHERE NOT deleted"),
            "widget_rows": await val("SELECT COUNT(*) FROM widget_data"),
            "widget_groups": await val("SELECT COUNT(DISTINCT group_id) FROM widget_data"),
            "widget_with_photo": await val(
                "SELECT COUNT(*) FROM widget_data WHERE photo_url <> ''"),
            "widget_with_message": await val(
                "SELECT COUNT(*) FROM widget_data WHERE message <> ''"),
            "widget_with_music": await val(
                "SELECT COUNT(*) FROM widget_data WHERE music_title <> ''"),
            "widget_with_mood": await val(
                "SELECT COUNT(*) FROM widget_data WHERE mood_label <> ''"),
            "widget_with_status": await val(
                "SELECT COUNT(*) FROM widget_data WHERE status <> ''"),
            "mood_labels": [dict(r) for r in moods],
        }


@app.get("/internal/couple-agg")
async def couple_agg(group_id: str):
    """Агрегаты чата и настроений для couple_stats.pb.js — одним ответом.

    Повторяют прежние SQLite-запросы хука один в один (включая недельный ритм
    с воскресеньем-нулём и месяцы по локальному времени автора отметки)."""
    if not group_id:
        return _err(400, "Something went wrong while processing your request.")
    ml = _MOOD_LOCAL
    async with pg.acquire() as c:
        async def val(sql, *a):
            return await c.fetchval(sql, *a) or 0

        async def rows(sql, *a):
            return [dict(r) for r in await c.fetch(sql, *a)]

        out = {
            "memories_total": await val(
                "SELECT COUNT(*) FROM memories WHERE group_id=$1 AND NOT deleted", group_id),
            "by_member_memories": await rows(
                "SELECT author_uid AS uid, COUNT(*)::int AS c FROM memories "
                "WHERE group_id=$1 AND NOT deleted GROUP BY 1", group_id),
            "timeline_memories": await rows(
                "SELECT substr(created_at,1,7) AS m, COUNT(*)::int AS c FROM memories "
                "WHERE group_id=$1 AND NOT deleted "
                f"AND replace(replace(created_at,'T',' '),'Z','')::timestamp >= {_UTC_NOW} - interval '12 months' "
                "GROUP BY 1 ORDER BY 1", group_id),
            "weekday_memories": await rows(
                "SELECT extract(dow from replace(replace(created_at,'T',' '),'Z','')::timestamp)::int AS d, "
                "COUNT(*)::int AS c FROM memories WHERE group_id=$1 AND NOT deleted "
                "AND created_at ~ '^\\d{4}-\\d{2}-\\d{2}' GROUP BY 1", group_id),
            "memory_types": await rows(
                "SELECT COALESCE(type,'') AS k, COUNT(*)::int AS c FROM memories "
                "WHERE group_id=$1 AND NOT deleted GROUP BY 1 ORDER BY c DESC", group_id),
            "memories30": await val(
                "SELECT COUNT(*) FROM memories WHERE group_id=$1 AND NOT deleted "
                f"AND replace(replace(created_at,'T',' '),'Z','')::timestamp >= {_UTC_NOW} - interval '30 days'",
                group_id),
            "memories90": await val(
                "SELECT COUNT(*) FROM memories WHERE group_id=$1 AND NOT deleted "
                f"AND replace(replace(created_at,'T',' '),'Z','')::timestamp >= {_UTC_NOW} - interval '90 days'",
                group_id),
            "first_memory": await val(
                "SELECT MIN(created_at) FROM memories WHERE group_id=$1 AND NOT deleted",
                group_id) or "",
            "canvases": await val(
                "SELECT COUNT(DISTINCT canvas_id) FROM canvas_meta WHERE group_id=$1", group_id),
            "messages": await val(
                "SELECT COUNT(*) FROM chat_messages WHERE group_id=$1 AND NOT deleted", group_id),
            "moods": await val(
                "SELECT COUNT(*) FROM mood_entries WHERE group_id=$1", group_id),
            "by_member_messages": await rows(
                "SELECT user_uid AS uid, COUNT(*)::int AS c FROM chat_messages "
                "WHERE group_id=$1 AND NOT deleted GROUP BY 1", group_id),
            "by_member_moods": await rows(
                "SELECT user_uid AS uid, COUNT(*)::int AS c FROM mood_entries "
                "WHERE group_id=$1 GROUP BY 1", group_id),
            "timeline_messages": await rows(
                "SELECT to_char(to_timestamp(ts/1000) at time zone 'utc','YYYY-MM') AS m, "
                "COUNT(*)::int AS c FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "AND ts >= (extract(epoch from now()) - 31536000)*1000 "
                "GROUP BY 1 ORDER BY 1", group_id),
            "timeline_moods": await rows(
                f"SELECT to_char({ml},'YYYY-MM') AS m, COUNT(*)::int AS c FROM mood_entries "
                f"WHERE group_id=$1 AND {_TS_OK} AND {_TS_UTC} >= {_UTC_NOW} - interval '12 months' "
                "GROUP BY 1 ORDER BY 1", group_id),
            "weekday_messages": await rows(
                "SELECT extract(dow from to_timestamp(ts/1000) at time zone 'utc')::int AS d, "
                "COUNT(*)::int AS c FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "GROUP BY 1", group_id),
            "hour_messages": await rows(
                "SELECT extract(hour from to_timestamp(ts/1000) at time zone 'utc')::int AS h, "
                "COUNT(*)::int AS c FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "GROUP BY 1", group_id),
            "mood_daily": await rows(
                f"SELECT to_char({ml},'YYYY-MM-DD') AS d, user_uid AS uid, mood_id AS id, "
                f"COUNT(*)::int AS c FROM mood_entries WHERE group_id=$1 AND {_TS_OK} "
                f"AND {_TS_UTC} >= {_UTC_NOW} - interval '90 days' "
                "GROUP BY 1, 2, 3 ORDER BY 1", group_id),
            "mood_top": await rows(
                "SELECT mood_id AS id, user_uid AS uid, COUNT(*)::int AS c FROM mood_entries "
                "WHERE group_id=$1 GROUP BY 1, 2 ORDER BY c DESC LIMIT 24", group_id),
            "messages30": await val(
                "SELECT COUNT(*) FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "AND ts >= (extract(epoch from now()) - 2592000)*1000", group_id),
            "messages90": await val(
                "SELECT COUNT(*) FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "AND ts >= (extract(epoch from now()) - 7776000)*1000", group_id),
            "moods30": await val(
                f"SELECT COUNT(*) FROM mood_entries WHERE group_id=$1 AND {_TS_OK} "
                f"AND {_TS_UTC} >= {_UTC_NOW} - interval '30 days'", group_id),
            "active_days30_count": await val(
                "SELECT COUNT(DISTINCT d) FROM ("
                "  SELECT to_char(to_timestamp(ts/1000) at time zone 'utc','YYYY-MM-DD') AS d "
                "  FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "  AND ts >= (extract(epoch from now()) - 2592000)*1000 "
                f" UNION SELECT to_char({ml},'YYYY-MM-DD') FROM mood_entries "
                f" WHERE group_id=$1 AND {_TS_OK} AND {_TS_UTC} >= {_UTC_NOW} - interval '30 days' "
                "  UNION SELECT substr(created_at,1,10) FROM memories "
                "  WHERE group_id=$1 AND NOT deleted "
                f" AND replace(replace(created_at,'T',' '),'Z','')::timestamp >= {_UTC_NOW} - interval '30 days'"
                ") q", group_id),
            "active_days30": [r["d"] for r in await rows(
                "SELECT DISTINCT to_char(to_timestamp(ts/1000) at time zone 'utc','YYYY-MM-DD') AS d "
                "FROM chat_messages WHERE group_id=$1 AND NOT deleted "
                "AND ts >= (extract(epoch from now()) - 2592000)*1000 "
                f"UNION SELECT DISTINCT to_char({ml},'YYYY-MM-DD') FROM mood_entries "
                f"WHERE group_id=$1 AND {_TS_OK} AND {_TS_UTC} >= {_UTC_NOW} - interval '30 days'",
                group_id)],
        }
    return out


@app.get("/api/collections/{col}/records")
async def list_records(col: str, request: Request):
    meta = COLLECTIONS.get(col)
    if meta is None:
        return _err(404, "The requested resource wasn't found.")
    try:
        auth = await _auth(request)
    except Exception:
        # Икота слоя аутентификации (SQLite занят) — пусть клиент повторит.
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    _, groups = auth

    q = request.query_params
    try:
        page = max(1, int(q.get("page", "1")))
        per_page = min(1000, max(1, int(q.get("perPage", "30"))))
    except ValueError:
        return _err(400, "Something went wrong while processing your request.")
    skip_total = q.get("skipTotal", "") in ("1", "true", "True")

    try:
        conds = _parse_filter(q.get("filter", ""), meta["filterable"])
    except ValueError:
        return _err(400, "Something went wrong while processing your request.")

    where, args = [], []
    filtered_group = None
    for field, op, val in conds:
        args.append(_coerce(col, field, val))
        where.append(f"{field} {op} ${len(args)}")
        if field == "group_id" and op == "=":
            filtered_group = val
    # listRule PB: видны только группы из своего group_ids. Чужая группа в
    # фильтре -> пустой список, фильтр без группы -> ограничение своими.
    if filtered_group is not None:
        if filtered_group not in groups:
            return {
                "page": page, "perPage": per_page,
                "totalItems": -1 if skip_total else 0,
                "totalPages": -1 if skip_total else 0,
                "items": [],
            }
    else:
        args.append(list(groups))
        where.append(f"group_id = ANY(${len(args)})")

    order = meta["default_sort"]
    sort = q.get("sort", "")
    if sort:
        keys = []
        for k in sort.split(","):
            k = k.strip()
            desc = k.startswith("-")
            name = k.lstrip("+-")
            if name in meta["sortable"]:
                keys.append(f"{name} {'DESC' if desc else 'ASC'}")
        if keys:
            order = ", ".join(keys) + ", id ASC"

    where_sql = " AND ".join(where) or "TRUE"
    sql = (
        f"SELECT * FROM {col} WHERE {where_sql} "
        f"ORDER BY {order} LIMIT {per_page} OFFSET {(page - 1) * per_page}"
    )
    async with pg.acquire() as c:
        rows = await c.fetch(sql, *args)
        if skip_total:
            total = -1
            pages = -1
        else:
            total = await c.fetchval(
                f"SELECT COUNT(*) FROM {col} WHERE {where_sql}", *args
            )
            pages = (total + per_page - 1) // per_page
    return {
        "page": page, "perPage": per_page, "totalItems": total,
        "totalPages": pages, "items": [_record_json(col, r) for r in rows],
    }


@app.post("/api/collections/{col}/records")
async def create_record(col: str, request: Request):
    meta = COLLECTIONS.get(col)
    if meta is None:
        return _err(404, "The requested resource wasn't found.")
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid, groups = auth

    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "Failed to create record.")

    gid = str(body.get("group_id") or "")
    if gid not in groups:
        # createRule не прошёл — PB в этом случае тоже отвечает 400.
        return _err(400, "Failed to create record.")
    owner_field = meta.get("create_owner_field")
    if owner_field and str(body.get(owner_field) or "") != uid:
        # У memories и widget_data createRule требует авторства записи.
        return _err(400, "Failed to create record.")

    rid = str(body.get("id") or "") or _new_id()
    if col == "widget_data":
        # widget_plus.pb.js: значок Togetherly+ на карточке ставит СЕРВЕР,
        # иначе его можно приписать себе голым API.
        body["plus"] = await asyncio.to_thread(_user_has_plus, uid)
    cols, vals = ["id"], [rid]
    for field, kind in meta["columns"].items():
        if kind == "auto":
            cols.append(field)
            vals.append(now_pb())
            continue
        v = body.get(field)
        cols.append(field)
        if kind == "json":
            vals.append(json.dumps(v) if v is not None else None)
        elif kind == "num":
            vals.append(float(v or 0))
        elif kind == "bool":
            vals.append(bool(v))
        elif kind == "date":
            # PB нормализует дату к «YYYY-MM-DD HH:MM:SS.mmmZ» — клиент шлёт
            # ISO с «T» (PairTime.write), подстрочные срезы ждут пробел.
            vals.append(str(v).replace("T", " ") if v else "")
        else:
            vals.append(str(v) if v is not None else "")
    ph = ", ".join(f"${i + 1}" for i in range(len(vals)))
    async with pg.acquire() as c:
        try:
            row = await c.fetchrow(
                f"INSERT INTO {col} ({', '.join(cols)}) VALUES ({ph}) RETURNING *",
                *vals,
            )
        except asyncpg.UniqueViolationError:
            # Идемпотентный повтор из очереди: клиент читает это как «уже есть».
            return _err(400, "Failed to create record.", {
                "id": {"code": "validation_not_unique", "message": "Value must be unique."}
            })
    rec = _record_json(col, row)
    asyncio.get_running_loop().create_task(_publish(col, "create", rec))
    asyncio.get_running_loop().create_task(_after_create(col, rec))
    return rec


@app.patch("/api/collections/{col}/records/{rid}")
async def update_record(col: str, rid: str, request: Request):
    meta = COLLECTIONS.get(col)
    if meta is None:
        return _err(404, "The requested resource wasn't found.")
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid, groups = auth
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "Failed to update record.")

    # Страж чата (перенос chat_guard.pb.js): не-автор правит только реакции
    # и отметку «послушал». Смотрим ТЕЛО запроса, как и хук.
    if meta["guard"] == "chat":
        async with pg.acquire() as c:
            author = await c.fetchval(
                f"SELECT user_uid FROM {col} WHERE id = $1", rid
            )
        if author and author != uid:
            for f in body:
                if f not in ("reactions", "voice_heard_at", "id"):
                    return _err(403, "only the author can edit this message")

    if col == "widget_data" and "plus" in body:
        body["plus"] = await asyncio.to_thread(_user_has_plus, uid)
    sets, args = [], []
    for field, kind in meta["columns"].items():
        if kind == "auto":
            args.append(now_pb())
            sets.append(f"{field} = ${len(args)}")
            continue
        if field not in body:
            continue
        v = body[field]
        if kind == "json":
            args.append(json.dumps(v) if v is not None else None)
        elif kind == "num":
            args.append(float(v or 0))
        elif kind == "bool":
            args.append(bool(v))
        elif kind == "date":
            args.append(str(v).replace("T", " ") if v else "")
        else:
            args.append(str(v) if v is not None else "")
        sets.append(f"{field} = ${len(args)}")
    args.append(rid)
    args.append(list(groups))
    sql = (
        f"UPDATE {col} SET {', '.join(sets) or 'id = id'} "
        f"WHERE id = ${len(args) - 1} AND group_id = ANY(${len(args)}) RETURNING *"
    )
    async with pg.acquire() as c:
        row = await c.fetchrow(sql, *args)
    if row is None:
        # Чужое и несуществующее PB прячет одним 404.
        return _err(404, "The requested resource wasn't found.")
    rec = _record_json(col, row)
    asyncio.get_running_loop().create_task(_publish(col, "update", rec))
    return rec


@app.delete("/api/collections/{col}/records/{rid}")
async def delete_record(col: str, rid: str, request: Request):
    meta = COLLECTIONS.get(col)
    if meta is None:
        return _err(404, "The requested resource wasn't found.")
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid, groups = auth
    if meta["delete_guard"] == "author":
        async with pg.acquire() as c:
            author = await c.fetchval(f"SELECT user_uid FROM {col} WHERE id = $1", rid)
        if author and author != uid:
            return _err(403, "only the author can delete this message")
    async with pg.acquire() as c:
        row = await c.fetchrow(
            f"DELETE FROM {col} WHERE id = $1 AND group_id = ANY($2) RETURNING *",
            rid, list(groups),
        )
    if row is None:
        return _err(404, "The requested resource wasn't found.")
    rec = _record_json(col, row)
    asyncio.get_running_loop().create_task(_publish(col, "delete", rec))
    _after_delete(col, rec)
    return Response(status_code=204)


# ── запуск ───────────────────────────────────────────────────────────────────


@app.on_event("startup")
async def _startup():
    global pg, cent_client, push_client, lite, lite_rw, auth_secret
    pg = await asyncpg.create_pool(PG_DSN, min_size=2, max_size=10)
    cent_client = httpx.AsyncClient(base_url=CENT_API, timeout=3.0)
    push_client = httpx.AsyncClient(timeout=10.0)
    # read-only к базе PocketBase: tokenKey, group_ids, members, presence, токены.
    lite = sqlite3.connect(f"file:{PB_DB}?mode=ro", uri=True, check_same_thread=False)
    lite.execute("PRAGMA busy_timeout=5000")
    # запись — только точечные вещи: messages_count и чистка мёртвых пуш-токенов.
    lite_rw = sqlite3.connect(PB_DB, timeout=10, check_same_thread=False)
    lite_rw.execute("PRAGMA busy_timeout=10000")
    auth_secret = json.loads(
        lite.execute(
            "SELECT options FROM _collections WHERE name = 'users'"
        ).fetchone()[0]
    )["authToken"]["secret"]
    asyncio.get_running_loop().create_task(_counter_worker())


@app.on_event("shutdown")
async def _shutdown():
    if _counter_deltas:
        try:
            _flush_counters_sync(dict(_counter_deltas))
        except sqlite3.Error:
            pass
    await pg.close()
    await cent_client.aclose()
    await push_client.aclose()
    lite.close()
    lite_rw.close()


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=LISTEN_PORT, log_level="warning")
