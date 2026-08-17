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
import fcntl
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import sqlite3
import threading
import time

import asyncpg
import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import ORJSONResponse, JSONResponse, Response

log = logging.getLogger("hotpath")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# httpx пишет INFO на КАЖДЫЙ запрос, а публикаций в Centrifugo идёт под сотню
# в секунду: полмиллиона строк в час уходили в journald, тот пишет их на диск
# синхронно и отъедает процессор ровно на пике. Отказы публикации видно и на
# уровне WARNING, а поток «200 OK» не говорит ничего.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

PG_DSN = os.environ["HOTPATH_PG_DSN"]
PB_DB = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
CENT_API = os.environ.get("CENTRIFUGO_API", "http://127.0.0.1:9000/api")
CENT_KEY = os.environ.get("CENTRIFUGO_API_KEY", "")
APNS_RELAY = os.environ.get("APNS_RELAY", "http://127.0.0.1:8096/push")
FCM_RELAY = os.environ.get("FCM_RELAY", "http://127.0.0.1:8100/push")
LISTEN_PORT = int(os.environ.get("HOTPATH_PORT", "8120"))
# Окно «человек на связи» для пушей. Ровно как свежесть присутствия у клиента
# (PresenceLiveness.freshness = 45 с при ударе раз в 20 с) плюс запас на дрожание
# сети. Прежние две минуты давали тишину: приложение закрыли, интерфейс партнёра
# уже показывал офлайн, а пуши всё ещё считались лишними — отсюда «уведомление
# приходит через три-пять минут» (17.08.2026). Три пропущенных удара подряд
# означают, что человека действительно нет.
ONLINE_WINDOW_MS = 60 * 1000

# Где лежит ИСТОЧНИК ПРАВДЫ по записи пары: пока «sqlite» — правит PocketBase,
# hotpath только читает; «pg» — правит hotpath, а в SQLite уходит зеркало.
# Флаг отделён от маршрута Caddy намеренно: код выкатывается и проверяется
# заранее, а переключение остаётся отдельным движением, которое можно отменить.
GROUPS_SRC = os.environ.get("HOTPATH_GROUPS", "sqlite")

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
    "user_presence": {
        "collection_id": os.environ.get("CID_USER_PRESENCE", "pbc_1624121044"),
        "columns": {"seen_at": "num", "user_uid": "text"},
        "sortable": {"seen_at", "id"},
        "filterable": {"id", "user_uid", "seen_at"},
        # listRule у presence — просто «залогинен»: партнёрское присутствие
        # читают по user_uid, группы тут ни при чём.
        "scope": "authed",
        "create_owner_field": "user_uid",
        "update_owner_field": "user_uid",
        "channel": "user",          # публикуем в user:<user_uid>
        "guard": None, "delete_guard": None,
        "after_create": None, "after_delete": None,
        "default_sort": "id ASC",
    },
    "chat_typing": {
        "collection_id": os.environ.get("CID_CHAT_TYPING", "pbc_1175427710"),
        "columns": {"group_id": "text", "typing_at": "num", "user_uid": "text"},
        "sortable": {"typing_at", "id"},
        "filterable": {"id", "group_id", "user_uid"},
        "create_owner_field": "user_uid",
        "guard": None, "delete_guard": None,
        "after_create": None, "after_delete": None,
        "default_sort": "id ASC",
    },
    "chat_reads": {
        "collection_id": os.environ.get("CID_CHAT_READS", "pbc_932032954"),
        "columns": {
            "group_id": "text", "last_read_ts": "num", "updated_at": "date",
            "user_uid": "text", "updated": "auto",
        },
        "sortable": {"updated", "id"},
        "filterable": {"id", "group_id", "user_uid", "updated"},
        "create_owner_field": "user_uid",
        "guard": None, "delete_guard": None,
        "after_create": None, "after_delete": None,
        "default_sort": "id ASC",
    },
    "live_location": {
        "collection_id": os.environ.get("CID_LIVE_LOCATION", "pbc_1895612750"),
        "columns": {"channel": "text", "data": "json", "user_uid": "text"},
        "sortable": {"id"},
        "filterable": {"id", "channel", "user_uid"},
        # канал — либо личный (содержит свой uid), либо id своей пары.
        "scope": "channel",
        "create_owner_field": "user_uid",
        "update_owner_field": "user_uid",
        "channel": "loc",           # публикуем в loc:<channel>
        "guard": None, "delete_guard": None,
        "after_create": None, "after_delete": None,
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
    # «Скучаю» и его собратья. Самая горячая запись вечера 14.08.2026: люди жали
    # кнопку 58 раз в секунду с полусотни устройств, каждый тап открывал в
    # PocketBase транзакцию, очередь к SQLite выросла до семи тысяч и вместе с
    # ней встала регистрация. В Postgres такой поток — обычное дело.
    "miss_you": {
        "collection_id": os.environ.get("CID_MISS_YOU", "pbc_1227645100"),
        "columns": {
            "group_id": "text", "user_uid": "text", "count": "num",
            "updated_at": "text", "last_vibe": "text", "last_vibe_text": "text",
            # ВНИМАНИЕ: отдаём эти две карты СТРОКОЙ, а не объектом. В
            # PocketBase поле было text, и выпущенные сборки читают его как
            # строку: `miss?['by_weekday'] as String?` в профиле партнёра
            # падает на объекте прямо внутри setState, экран остаётся с
            # вечным спиннером (жалоба 15.08.2026). Форму ответа менять
            # нельзя, пока живы старые сборки.
            "by_weekday": "jsontext", "by_vibe": "jsontext", "updated": "auto",
        },
        "sortable": {"updated", "id"},
        "filterable": {"id", "group_id", "user_uid", "updated"},
        "create_owner_field": None,
        "guard": None,
        "delete_guard": None,
        "after_create": None,
        "after_delete": None,
        "default_sort": "id ASC",
    },
    # Запись пары. Отличий от прочих три, и все существенные:
    # 1) ключ доступа — не колонка group_id, а членство в самой строке
    #    (правило PB у всех пяти действий одно: members ?~ @request.auth.id);
    # 2) id записи И ЕСТЬ id пары, поэтому канал — pair:<id>, а не pair:<group_id>;
    # 3) событие уходит ещё и в личные каналы обоих: иначе приглашающий не
    #    увидит появление пары до перезапуска приложения (разбор 02.08.2026).
    "groups": {
        "collection_id": os.environ.get("CID_GROUPS", "pbc_3346940990"),
        "columns": {
            "members": "json", "member_names": "json", "member_avatars": "json",
            "member_birthdays": "json", "member_moods": "json",
            "member_ailments": "json", "max_members": "num",
            "relationship_type": "text", "custom_relationship_label": "text",
            "custom_relationship_emoji": "text",
            "custom_relationship_types": "json", "start_date": "text",
            "anniversary_date": "text", "first_kiss_date": "text",
            "current_status": "json", "custom_statuses": "json",
            "memories_count": "num", "drawings_count": "num",
            "messages_count": "num", "xp": "num", "streak_days": "num",
            "streak_last_opened_date": "text", "streak_pending_date": "text",
            "streak_pending_uid": "text", "daily_tasks": "json",
            "active_mascot_id": "text", "mascot_position_x": "num",
            "mascot_position_y": "num", "mascot_scale": "num",
            "mascots": "json", "mascot_streaks": "json", "timers": "json",
            "active_session": "json", "owned_features": "json",
            "waiting_mode": "bool", "placeholder_name": "text",
            "placeholder_avatar": "text", "return_date": "text",
            "claim_token": "text", "claim_uid": "text", "claim_name": "text",
            "claim_at": "num", "disbanded": "bool", "disbanded_at": "text",
            "created_at": "text", "updated": "auto",
        },
        "sortable": {"updated", "id"},
        "filterable": {"id", "members", "disbanded", "updated", "claim_token"},
        "scope": "members",
        "channel": "group_record",
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

app = FastAPI(openapi_url=None, docs_url=None, redoc_url=None,
              default_response_class=ORJSONResponse)
pg: asyncpg.Pool | None = None
cent_client: httpx.AsyncClient | None = None
push_client: httpx.AsyncClient | None = None
pb_client: httpx.AsyncClient | None = None   # проксирование редких записей в PocketBase
lite: sqlite3.Connection | None = None      # read-only: auth, группы, presence
lite_rw: sqlite3.Connection | None = None   # счётчики групп и чистка токенов
_bg_lock_fd: int | None = None             # замок роли фоновых задач
auth_secret = ""
_lite_lock = asyncio.Lock()
# Соединение записи в SQLite ОДНО на процесс, а пишущих задач несколько:
# зеркало пар, списки групп, счётчики, отметки присутствия, чистка токенов.
# Они живут в разных потоках (asyncio.to_thread), и без общего замка их
# транзакции наезжают друг на друга: «cannot start a transaction within a
# transaction», после чего правка молча не доезжает до SQLite.
_lite_rw_lock = threading.Lock()
_counter_deltas: dict = {}                 # (group_id, поле) -> дельта

# ── совместимость с PocketBase: время и ошибки ───────────────────────────────


def now_pb() -> str:
    t = time.time()
    return time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(t)) + f".{int(t * 1000) % 1000:03d}Z"


def _err(code: int, message: str, data: dict | None = None) -> ORJSONResponse:
    return ORJSONResponse(
        {"code": code, "message": message, "data": data or {}}, status_code=code
    )


# ── аутентификация ───────────────────────────────────────────────────────────

_AUTH_TTL = 120.0
_AUTH_CACHE_MAX = 30000
_auth_cache: dict[str, tuple[float, str]] = {}

# Список пар человека живёт отдельно от подписи токена и обновляется быстро.
#
# Пока он лежал в общем кэше на две минуты, только что принятый в пару видел
# ПУСТОЙ чат и пустую ленту: правила фильтруют записи по group_id, а сервер эти
# две минуты помнил прежний состав. Ровно так же работало и наоборот — вышедший
# из пары ещё две минуты читал чужую переписку. Дорогая часть проверки (HMAC по
# токену) кэшируется по-прежнему надолго, состав пар — на несколько секунд:
# это один SELECT по первичному ключу в SQLite, он дешевле переспросить.
_GROUPS_TTL = 5.0
_GROUPS_CACHE_MAX = 30000
_groups_cache: dict[str, tuple[float, frozenset]] = {}
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


async def _группы_человека(uid: str, now: float) -> frozenset:
    """Список пар человека — из SQLite, с коротким кэшем.

    Живёт отдельно от подписи токена: состав пар меняется, пока человек сидит
    с тем же токеном (его приняли в пару, он вышел из пары), и правила доступа
    обязаны догонять это за секунды, а не за две минуты.
    """
    hit = _groups_cache.get(uid)
    if hit and hit[0] > now:
        return hit[1]
    found = await asyncio.to_thread(_lite_user, uid)
    groups = found[1] if found else frozenset()
    if len(_groups_cache) >= _GROUPS_CACHE_MAX:
        _groups_cache.clear()
    _groups_cache[uid] = (now + _GROUPS_TTL, groups)
    return groups


async def _auth(request: Request) -> tuple[str, frozenset] | None:
    """Токен -> (uid, группы) или None. Подпись сверяется локально — той же
    формулой, что у PocketBase: HS256(tokenKey записи + секрет коллекции)."""
    token = request.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not token:
        return None
    now = time.monotonic()
    hit = _auth_cache.get(token)
    if hit and hit[0] > now:
        return hit[1], await _группы_человека(hit[1], now)

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
    _auth_cache[token] = (now + _AUTH_TTL, uid)
    if len(_groups_cache) >= _GROUPS_CACHE_MAX:
        _groups_cache.clear()
    _groups_cache[uid] = (now + _GROUPS_TTL, groups)
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
        elif kind == "jsontext":
            # json в базе, строка в ответе — ради совместимости со сборками
            if v is None:
                out[field] = ""
            elif isinstance(v, str):
                out[field] = v
            else:
                out[field] = json.dumps(v, ensure_ascii=False)
        else:
            out[field] = v if v is not None else ""
    return out


_COND = re.compile(
    r"""^\s*\(*\s*(\w+)\s*(!=|>=|<=|=|>|<|~)\s*"""
    r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|(true|false)|(-?\d+(?:\.\d+)?))"""
    r"""\s*\)*\s*$"""
)
# `~` у PocketBase — поиск подстроки, но приложение шлёт его ровно в одном
# смысле: `members ~ '<uid>'`, то есть «состоит ли человек в паре». На jsonb
# это containment, он же идёт по индексу; для остальных колонок оператор не
# принимаем, чтобы случайный LIKE не превратился в скан 22 тысяч строк.
_OPS = {"=": "=", "!=": "<>", ">": ">", "<": "<", ">=": ">=", "<=": "<=",
        "~": "@>"}


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
        if op == "~":
            # только по json-колонке и только строкой: members ~ '<uid>'
            if not isinstance(val, str):
                raise ValueError(part)
            val = json.dumps([val])
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
    # Каналы те же, что раздаёт сборка PocketBase (centChannels в main.go):
    # присутствие в user:<uid>, геопозиция в loc:<channel>, запись пары — в
    # pair:<id> И в личные каналы обоих участников, остальное в pair:<group_id>.
    kind = COLLECTIONS[col].get("channel", "pair")
    if kind == "user":
        chans = ["user:" + (record.get("user_uid") or "")]
    elif kind == "loc":
        chans = ["loc:" + (record.get("channel") or "")]
    elif kind == "group_record":
        chans = ["pair:" + (record.get("id") or "")]
        участники = record.get("members")
        if isinstance(участники, list):
            chans += ["user:" + str(m) for m in участники if m]
    else:
        chans = ["pair:" + (record.get("group_id") or "")]
    chans = [c for c in chans if not c.endswith(":")]
    if not chans or not CENT_KEY:
        return
    data = {"event": event, "collection": col, "record": record}
    for chan in chans:
        try:
            await cent_client.post(
                "/publish",
                json={"channel": chan, "data": data},
                headers={"X-API-Key": CENT_KEY},
            )
        except httpx.HTTPError:
            pass  # realtime — best effort, как и в хуке


def _push_candidates(group_id: str, author_uid: str,
                     members: list | None = None) -> list[dict]:
    """Участники группы с их токенами. Токены живут в users, то есть в SQLite
    PocketBase, всегда. Состав пары приходит параметром, когда источник правды
    уже переехал в Postgres; иначе читается тут же, рядом с токенами.
    Кто сейчас на связи, решается отдельно: присутствие живёт в Postgres."""
    if members is None:
        g = lite.execute(
            "SELECT members, disbanded FROM groups WHERE id = ?", (group_id,)
        ).fetchone()
        if g is None or g[1]:
            return []
        try:
            members = json.loads(g[0] or "[]") or []
        except ValueError:
            members = []
    out = []
    for uid in members:
        uid = str(uid or "")
        if not uid or uid == author_uid:
            continue
        u = lite.execute(
            "SELECT apns_token, apns_sandbox, fcm_token, apns_bg_ms, "
            "notif_chat, notif_mood, notif_new_memory, notif_miss_you "
            "FROM users WHERE id = ?",
            (uid,),
        ).fetchone()
        if u is None:
            continue
        out.append({"uid": uid, "apns": u[0] or "", "sandbox": bool(u[1]),
                    "fcm": u[2] or "", "bg_ms": int(u[3] or 0),
                    # Выключатели уведомлений из приложения — их читает
                    # `_уведомление_разрешено` перед отправкой.
                    "notif_chat": u[4], "notif_mood": u[5],
                    "notif_new_memory": u[6], "notif_miss_you": u[7]})
    return out


async def _online_uids(uids: list[str]) -> set:
    """Кто из них на связи — по presence в Postgres (окно две минуты)."""
    if not uids:
        return set()
    edge = int(time.time() * 1000) - ONLINE_WINDOW_MS
    try:
        async with pg.acquire() as c:
            rows = await c.fetch(
                "SELECT user_uid FROM user_presence WHERE user_uid = ANY($1) AND seen_at > $2",
                uids, float(edge))
        return {r["user_uid"] for r in rows}
    except Exception as e:
        log.warning("presence lookup: %s", e)
        return set()   # не знаем — лучше прислать пуш, чем промолчать


async def _members_pg(group_id: str) -> list | None:
    """Состав живой пары из Postgres. None — пары нет или она распущена."""
    async with pg.acquire() as c:
        row = await c.fetchrow(
            "SELECT members, disbanded FROM groups WHERE id = $1", group_id)
    if row is None or row["disbanded"]:
        return None
    m = row["members"]
    if isinstance(m, str):
        try:
            m = json.loads(m)
        except ValueError:
            m = []
    return [str(x) for x in (m or []) if x]


async def _push_targets(group_id: str, author_uid: str) -> list[dict]:
    """Кому слать: участники группы, кроме автора и тех, кто сейчас на связи."""
    members = None
    if GROUPS_SRC == "pg":
        members = await _members_pg(group_id)
        if members is None:
            return []
    cand = await asyncio.to_thread(_push_candidates, group_id, author_uid, members)
    if not cand:
        return []
    online = await _online_uids([t["uid"] for t in cand])
    return [t for t in cand if t["uid"] not in online]


def _forget_token(uid: str, field: str) -> None:
    try:
        with _lite_rw_lock:
            lite_rw.execute(f"UPDATE users SET {field} = '' WHERE id = ?", (uid,))
            lite_rw.commit()
    except sqlite3.Error:
        pass  # попробуем в следующий раз


async def _notify_group(group_id: str, author_uid: str, title: str, body: str,
                        thread: str) -> int:
    """Пуш всем в группе, кроме автора — как notifyGroup в apns_push.js.

    Возвращает, сколько пушей реально ушло. Это нужно гейту частоты: отметку
    «уже отправляли» нельзя ставить, когда адресатов не осталось (например, все
    сейчас в приложении), иначе проглоченная попытка крадёт следующую минуту.
    """
    try:
        targets = await _push_targets(group_id, author_uid)
    except Exception as e:
        log.warning("push targets %s: %s", group_id, e)
        return 0
    отправлено = 0
    for t in targets:
        # Человек выключил этот вид уведомлений в приложении — молчим.
        # Переключатели доезжали до сервера с самого начала, но их не читал
        # никто: «Скучаю» было выключено у 16 507 человек, и все получали его
        # по-прежнему (жалоба 16.08.2026).
        if not _уведомление_разрешено(thread, t):
            continue
        if t["apns"]:
            try:
                r = await push_client.post(APNS_RELAY, json={
                    "token": t["apns"], "title": title, "body": body,
                    "thread": thread, "sandbox": t["sandbox"], "data": {"kind": thread},
                })
                if (r.json() or {}).get("gone"):
                    await asyncio.to_thread(_forget_token, t["uid"], "apns_token")
                else:
                    отправлено += 1
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
                else:
                    отправлено += 1
            except Exception as e:
                log.warning("fcm %s: %s", t["uid"], e)
    return отправлено


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
        targets = await _push_targets(group_id, author_uid)
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


# Вид уведомления → колонка выключателя в users. Пустое поле означает
# «включено»: у старых аккаунтов этих колонок нет вовсе, и молчать им нельзя.
ВЫКЛЮЧАТЕЛИ = {
    "chat": "notif_chat",
    "mood": "notif_mood",
    "memory": "notif_new_memory",
    "miss": "notif_miss_you",
}


def _уведомление_разрешено(вид: str, человек: dict) -> bool:
    """Не выключил ли человек этот вид уведомлений в приложении.

    Переключатели доезжали до сервера с самого начала, но их никто не читал:
    пуши уходили всем подряд. На 16.08.2026 «Скучаю» было выключено у 16 507
    человек — и все они его получали (жалоба «уведомления не выключаются»).
    """
    колонка = ВЫКЛЮЧАТЕЛИ.get(вид)
    if колонка is None:
        return True
    значение = человек.get(колонка)
    if значение is None:
        return True
    return bool(значение)


# Когда паре последний раз уходил пуш «Скучаю» — чтобы серия нажатий не
# превратилась в лавину уведомлений. Держим в памяти процесса: точность тут не
# нужна, важно снять поток.
_МОЛЧАНИЕ_MISS_MS = 60_000
_последний_miss: dict[str, int] = {}


def _можно_слать_miss(group_id: str, теперь_мс: int) -> bool:
    """Не чаще раза в минуту на пару — только проверка, без отметки.

    Человек жмёт сердце подряд, клиент копит нажатия и шлёт их пачками по
    двадцать — и на каждую пачку уходило отдельное уведомление. Со стороны
    партнёра это «уведомления без остановки» (жалоба 16.08.2026). Счёт при
    этом прибавляется весь, теряется только шум в шторке.

    Отметка вынесена в [_отметить_miss] и ставится ПОСЛЕ фактической отправки.
    Пока она стояла здесь, минуту крала любая попытка, даже когда пуш никому не
    ушёл: партнёр закрыл приложение, но его отметка присутствия ещё свежая —
    адресатов ноль, зато следующее сердце уже молчит. Отсюда жалобы «приходит с
    задержкой три-пять минут, а иногда вообще нет» (17.08.2026).
    """
    было = _последний_miss.get(group_id)
    return было is None or теперь_мс - было >= _МОЛЧАНИЕ_MISS_MS


def _отметить_miss(group_id: str, теперь_мс: int) -> None:
    """Запомнить, что пуш этой паре ушёл."""
    _последний_miss[group_id] = теперь_мс
    # Карта не должна расти без края: чистим давние записи пачкой.
    if len(_последний_miss) > 20_000:
        порог = теперь_мс - _МОЛЧАНИЕ_MISS_MS
        for k in [k for k, v in _последний_miss.items() if v < порог]:
            _последний_miss.pop(k, None)


def _miss_you_push_text(вайб_текст: str | None) -> str:
    """Тело уведомления об импульсе «Скучаю».

    Повторяет прежний хук `push_apns.pb.js` слово в слово: своё пожелание
    человека, а если его нет — «Обними в ответ». Длинное режем, как в чате:
    в шторке всё равно видно только начало.
    """
    текст = (вайб_текст or "").strip()
    if not текст:
        return "Обними в ответ"
    return текст[:117] + "…" if len(текст) > 120 else текст


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


async def _after_update(col: str, rec: dict) -> None:
    """Что делать после правки записи.

    Пока это только настроение. Отметка за день у человека одна: первый раз
    она создаётся, дальше правится — и уведомление уходило лишь на первую.
    Человек менял настроение днём, а партнёр об этом не узнавал вовсе
    (жалоба 16.08.2026). Антидребезг общий с «Скучаю»: подряд перебирать
    эмоции — обычное дело, но шторка от этого захлёбываться не должна.
    """
    if COLLECTIONS[col]["after_create"] != "mood":
        return
    group_id = rec.get("group_id") or ""
    if not group_id:
        return
    теперь_мс = int(time.time() * 1000)
    if not _можно_слать_miss("mood:" + group_id, теперь_мс):
        return
    label = (rec.get("label") or "").strip()
    ушло = await _notify_group(
        group_id, rec.get("user_uid") or "", "Настроение партнёра",
        f"Сегодня: {label}" if label else "Партнёр отметил настроение", "mood")
    if ушло:
        _отметить_miss("mood:" + group_id, теперь_мс)


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
    with _lite_rw_lock:
        _flush_counters_пишем(deltas)


def _flush_counters_пишем(deltas: dict) -> None:
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


ЗЕРКАЛО_ОТМЕТКА = "/opt/hotpath/.groups_mirror_at"
ЗЕРКАЛО_ПАЧКА = 1000


def _прочитать_отметку() -> str:
    try:
        with open(ЗЕРКАЛО_ОТМЕТКА, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def _записать_отметку(v: str) -> None:
    try:
        with open(ЗЕРКАЛО_ОТМЕТКА, "w", encoding="utf-8") as f:
            f.write(v)
    except OSError as e:
        log.warning("отметка зеркала не записалась: %s", e)


def _чужие_правки_sync(ids: list) -> dict:
    """Время правки этих пар в SQLite — чтобы понять, не писал ли туда кто-то
    ещё. Любой писатель через PocketBase двигает autodate-поле updated, и это
    единственный способ увидеть писателя, о котором мы не знали."""
    out = {}
    for i in range(0, len(ids), 500):
        кусок = ids[i:i + 500]
        места = ",".join("?" * len(кусок))
        for gid, upd in lite.execute(
                f"SELECT id, COALESCE(updated,'') FROM `groups` WHERE id IN ({места})",
                кусок):
            out[gid] = upd
    return out


async def _зеркало_воркер() -> None:
    """Раз в две минуты складывает свежие пары из Postgres обратно в SQLite.

    Пачкой, а не потоком: в этом вся выгода переезда. Отдельно — защита от
    потери: если в SQLite строка оказалась СВЕЖЕЕ, значит её правил кто-то,
    кого мы не перевели (хук, старый путь). Такую строку зеркало НЕ затирает,
    а поднимает в Postgres и пишет тревогу в журнал.
    """
    while True:
        await asyncio.sleep(120)
        if GROUPS_SRC != "pg":
            continue
        try:
            отметка = _прочитать_отметку()
            if not отметка:
                # Первый запуск: историю гнать незачем — базы уже сверены
                # переносом, а проход по всем парам пачками только зря
                # нагрузил бы запись в SQLite.
                _записать_отметку(now_pb())
                continue
            async with pg.acquire() as c:
                строки = await c.fetch(
                    "SELECT * FROM groups WHERE updated > $1 "
                    "ORDER BY updated LIMIT $2", отметка, ЗЕРКАЛО_ПАЧКА)
            if not строки:
                continue
            свои = await asyncio.to_thread(
                _чужие_правки_sync, [r["id"] for r in строки])
            к_зеркалу, чужие = [], []
            for r in строки:
                было = свои.get(r["id"], "")
                if было and было > (r["updated"] or ""):
                    чужие.append(r["id"])
                else:
                    к_зеркалу.append(r)
            if к_зеркалу:
                await asyncio.to_thread(_зеркало_группы_sync, к_зеркалу)
            if чужие:
                log.warning(
                    "ТРЕВОГА: %d пар правлены мимо Postgres (%s) — поднимаю "
                    "их в Postgres, зеркало их не затирает", len(чужие),
                    ", ".join(чужие[:5]))
                await _поднять_из_sqlite(чужие)
            _записать_отметку(строки[-1]["updated"] or отметка)
        except Exception as e:  # воркер не должен умирать
            log.warning("зеркало пар: %s", e)


def _строки_из_sqlite(ids: list) -> list:
    места = ",".join("?" * len(ids))
    поля = ", ".join(ЗЕРКАЛО_КОЛОНКИ)
    return lite.execute(
        f"SELECT id, {поля} FROM `groups` WHERE id IN ({места})", ids).fetchall()


async def _поднять_из_sqlite(ids: list) -> None:
    """Залить в Postgres строки, которые кто-то поправил в SQLite мимо нас."""
    строки = await asyncio.to_thread(_строки_из_sqlite, ids)
    if not строки:
        return
    поля = ", ".join(ЗЕРКАЛО_КОЛОНКИ)
    места = ", ".join(f"${i + 2}" for i in range(len(ЗЕРКАЛО_КОЛОНКИ)))
    обнов = ", ".join(f"{c} = EXCLUDED.{c}" for c in ЗЕРКАЛО_КОЛОНКИ)
    async with pg.acquire() as c:
        for row in строки:
            значения = []
            for idx, имя in enumerate(ЗЕРКАЛО_КОЛОНКИ, start=1):
                v = row[idx]
                kind = COLLECTIONS["groups"]["columns"][имя]
                if kind == "json":
                    s = v if isinstance(v, str) or v is None else json.dumps(v)
                    значения.append(s if (s or "").strip() else None)
                elif kind == "num":
                    значения.append(float(v or 0))
                elif kind == "bool":
                    значения.append(bool(v))
                else:
                    значения.append(str(v) if v is not None else "")
            await c.execute(
                f"INSERT INTO groups (id, {поля}) VALUES ($1, {места}) "
                f"ON CONFLICT (id) DO UPDATE SET {обнов}", row[0], *значения)


async def _flush_counters_pg(deltas: dict) -> None:
    """То же, но в Postgres, где строка пары и лежит.

    Тут ограничение «раз в минуту» ни к чему: это обычный UPDATE в своей базе,
    он никому не протухает снапшоты. Поэтому при переехавших группах счётчик
    сбрасывается каждые пять секунд и цифра в профиле почти не отстаёт.
    """
    отметка = now_pb()
    async with pg.acquire() as c:
        async with c.transaction():
            for (gid, field), d in deltas.items():
                # updated двигаем намеренно: по нему зеркало понимает, какие
                # пары нести обратно в SQLite, а счётчики нужны отчётам.
                await c.execute(
                    f"UPDATE groups SET {field} = GREATEST(0, COALESCE({field}, 0) + $1), "
                    "updated = $2 WHERE id = $3", float(d), отметка, gid)


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
        await asyncio.sleep(5 if GROUPS_SRC == "pg" else 60)
        if not _counter_deltas:
            continue
        batch, _counter_deltas = _counter_deltas, {}
        try:
            if GROUPS_SRC == "pg":
                await _flush_counters_pg(batch)
            else:
                await asyncio.to_thread(_flush_counters_sync, batch)
        except (sqlite3.Error, asyncpg.PostgresError, OSError) as e:
            log.warning("counters отложены (%s)", e)
            for key, d in batch.items():  # вернуть в очередь
                _counter_deltas[key] = _counter_deltas.get(key, 0) + d


# ── зеркало присутствия в SQLite (для аналитики) ─────────────────────────────


def _mirror_presence_sync(rows: list) -> None:
    """Складывает свежие отметки присутствия обратно в SQLite PocketBase.

    Зачем: когорты удержания и вкладка «Доход» джойнят `users` с
    `user_presence` одним SQL — а users остались в PB. Держим там теневую
    копию: одна пачка раз в пять минут вместо сотни отдельных записей в
    минуту, которые эту базу и душили."""
    with _lite_rw_lock:
        lite_rw.execute("BEGIN IMMEDIATE")
        try:
            lite_rw.executemany(
                "INSERT INTO user_presence (id, user_uid, seen_at) VALUES (?,?,?) "
                "ON CONFLICT(user_uid) DO UPDATE SET seen_at = excluded.seen_at",
                rows)
            lite_rw.commit()
        except BaseException:
            lite_rw.rollback()
            raise


async def _presence_mirror_worker() -> None:
    last = 0.0
    while True:
        await asyncio.sleep(300)
        try:
            async with pg.acquire() as c:
                rows = await c.fetch(
                    "SELECT id, user_uid, seen_at FROM user_presence WHERE seen_at > $1",
                    last)
            if not rows:
                continue
            last = max(float(r["seen_at"]) for r in rows)
            await asyncio.to_thread(
                _mirror_presence_sync,
                [(r["id"], r["user_uid"], int(r["seen_at"])) for r in rows])
            log.info("присутствие: зеркало %d строк", len(rows))
        except Exception as e:
            log.warning("зеркало присутствия отложено: %s", e)


# ── маршруты ─────────────────────────────────────────────────────────────────


@app.get("/healthz")
async def healthz():
    async with pg.acquire() as c:
        await c.fetchval("SELECT 1")
    return {"ok": True}


@app.post("/api/group/miss-you")
async def miss_you(request: Request):
    """Импульс «Скучаю»: один запрос — одна строка вверх.

    В PocketBase это был read-modify-write в транзакции: находим запись,
    считаем новое значение, сохраняем. При 58 нажатиях в секунду очередь к
    SQLite выросла до семи тысяч ожидающих. Здесь то же самое делает Postgres
    одним `INSERT … ON CONFLICT DO UPDATE`: счётчик и обе карты прибавляются
    прямо в базе, читать перед записью не нужно.

    Форма ответа и канал рассылки повторяют прежний хук `groups.pb.js`, чтобы
    приложению не пришлось ничего знать о переезде.
    """
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid_auth, groups = auth

    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad params")

    group_id = str(body.get("groupId") or "").strip()
    uid = str(body.get("uid") or "").strip()
    vibe = str(body.get("vibe") or "miss_you")
    text = str(body.get("text") or "")
    if not group_id or not uid:
        return _err(400, "bad params")
    if group_id not in groups:
        return ORJSONResponse({"ok": False, "error": "not a member"}, status_code=403)

    # Клиент копит частые тапы и шлёт их одним запросом; потолок двадцать —
    # дальше это зажатый палец, а не человек.
    try:
        times = int(body.get("count"))
    except Exception:
        times = 1
    if not 1 <= times <= 20:
        times = 1

    # День недели присылает клиент (1=пн … 7=вс): сервер живёт в UTC, и ночные
    # нажатия попадали бы во вчерашний день.
    try:
        weekday = int(body.get("weekday"))
    except Exception:
        weekday = 0
    if not 1 <= weekday <= 7:
        weekday = (time.gmtime().tm_wday + 1)
    wd = str(weekday)

    # Свои типы импульсов; чужое имя не должно растить карту без края.
    vibe_key = vibe if vibe in ("miss_you", "thinking_of_you", "want_hug", "custom") else "miss_you"

    now_iso = now_pb()
    rid = _new_id()
    row = await pg.fetchrow(
        """
        INSERT INTO miss_you (id, group_id, user_uid, count, updated_at,
                              last_vibe, last_vibe_text, by_weekday, by_vibe, updated)
        VALUES ($1, $2, $3, $4::double precision, $5, $6, $7,
                jsonb_build_object($8::text, to_jsonb($4::double precision)),
                jsonb_build_object($9::text, to_jsonb($4::double precision)), $5)
        ON CONFLICT (group_id, user_uid) DO UPDATE SET
            count = miss_you.count + $4::double precision,
            updated_at = $5,
            updated = $5,
            last_vibe = $6,
            last_vibe_text = $7,
            by_weekday = jsonb_set(
                COALESCE(miss_you.by_weekday, '{}'::jsonb), ARRAY[$8::text],
                to_jsonb(COALESCE((miss_you.by_weekday->>$8::text)::double precision, 0)
                         + $4::double precision)),
            by_vibe = jsonb_set(
                COALESCE(miss_you.by_vibe, '{}'::jsonb), ARRAY[$9::text],
                to_jsonb(COALESCE((miss_you.by_vibe->>$9::text)::double precision, 0)
                         + $4::double precision))
        RETURNING *
        """,
        rid, group_id, uid, float(times), now_iso, vibe, text, wd, vibe_key,
    )

    rec = _record_json("miss_you", row)
    await _publish("miss_you", "update", rec)
    # Уведомление второму. При переезде коллекции в hotpath оно пропало: пуш
    # слал хук PocketBase на update записи, а хуки переехавших коллекций
    # больше не срабатывают. Счётчик при этом обновлялся, и со стороны это
    # выглядело как «сердечко прилетело, а телефон молчит» (жалоба 16.08.2026).
    теперь_мс = int(time.time() * 1000)
    if _можно_слать_miss(group_id, теперь_мс):
        ушло = await _notify_group(group_id, uid, "Скучает по тебе",
                                   _miss_you_push_text(text), "miss")
        if ушло:
            _отметить_miss(group_id, теперь_мс)
    return ORJSONResponse({"ok": True, "count": _num(row["count"])})


# ── Разгрузка PocketBase: частые вопросы с редким ответом ────────────────────
#
# Вечер 14.08.2026: 400 запросов в секунду, из них 26 пишущих, а SQLite с
# цепочкой JS-обработчиков вытягивает около восьми. Разница копилась в очередь,
# и регистрация висела по тридцать секунд.
#
# Два самых частых пишущих запроса почти всегда ничего не меняют: «заходил
# сегодня» приходит на каждый запуск приложения (9 в секунду), а день
# засчитывается один раз; «дай ежедневную монетку» — тоже на каждый запуск
# (5 в секунду), а бонус даётся раз в двадцать часов. Отвечаем на них здесь,
# читая ответ прямо из базы PocketBase в режиме только чтения — это дёшево и
# не занимает соединение записи. Настоящее изменение уходит в PocketBase как
# раньше: логика серии дней и начисления остаётся там, где была.

def _lite_group_streak(group_id: str) -> tuple[str, str] | None:
    """(участники, дата последнего общего дня) из SQLite PocketBase."""
    try:
        row = lite.execute(
            "SELECT members, COALESCE(streak_last_opened_date, '') FROM `groups` WHERE id = ?",
            (group_id,),
        ).fetchone()
        return (row[0] or "", row[1] or "") if row else None
    except sqlite3.Error:
        return None


def _lite_user_bonus(uid: str) -> tuple[int, int] | None:
    """(время прошлого бонуса в мс, монеты) из SQLite PocketBase."""
    try:
        row = lite.execute(
            "SELECT COALESCE(last_daily_bonus_ms, 0), COALESCE(coins, 0) FROM users WHERE id = ?",
            (uid,),
        ).fetchone()
        return (int(row[0] or 0), int(row[1] or 0)) if row else None
    except (sqlite3.Error, TypeError, ValueError):
        return None


async def _proxy_to_pb(path: str, request: Request, body: dict) -> Response:
    """Отдать запрос PocketBase как есть и вернуть его ответ."""
    try:
        r = await pb_client.post(
            path, json=body,
            headers={"Authorization": request.headers.get("authorization", "")},
        )
        return Response(content=r.content, status_code=r.status_code,
                        media_type=r.headers.get("content-type", "application/json"))
    except httpx.HTTPError as e:
        log.warning("прокси в PocketBase не удался: %s %s", path, e)
        return _err(503, "Try again later.")


@app.post("/api/group/record-activity")
async def record_activity(request: Request):
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid_auth, groups = auth

    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad params")

    group_id = str(body.get("groupId") or "").strip()
    today = str(body.get("today") or "").strip()
    if not group_id or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", today):
        return _err(400, "bad params")
    if group_id not in groups:
        return ORJSONResponse({"ok": False, "error": "not a member"}, status_code=403)

    if GROUPS_SRC != "pg":
        row = await asyncio.to_thread(_lite_group_streak, group_id)
        if row is not None and row[1] == today:
            # День уже отмечен — PocketBase тут делать нечего.
            return ORJSONResponse({"ok": True, "already": True})
        return await _proxy_to_pb("/api/group/record-activity", request, body)

    uid = str(body.get("uid") or "").strip() or uid_auth
    return await _record_activity_pg(group_id, uid_auth, uid, today)


def _общий_день(сегодня: str, ждём: str) -> bool:
    """Считать ли отметку партнёра тем же общим днём.

    Дату «сегодня» присылает клиент по своим часам, и у пары из разных поясов
    она расходится каждый вечер: у неё уже 17-е, у него ещё 16-е. Полное
    совпадение строк такую пару не засчитывало НИКОГДА — второй заход просто
    перезаписывал ожидание своей датой. По живой базе 16.08.2026 в разных
    поясах живут 22% активных пар (1799 из 8162), а серия дольше недели была
    всего у 252 пар из 31 780.

    Поэтому соседний день тоже считается общим — ровно на разницу поясов.
    Дальше суток не идём: иначе «серия» перестанет значить «мы оба тут».
    """
    if not сегодня or not ждём:
        return False
    if сегодня == ждём:
        return True
    try:
        a = time.mktime(time.strptime(сегодня, "%Y-%m-%d"))
        b = time.mktime(time.strptime(ждём, "%Y-%m-%d"))
    except ValueError:
        return False
    return abs(round((a - b) / 86400)) == 1


def _день_подряд(сегодня: str, прошлый: str) -> bool:
    """Прошлый общий день был ровно вчера (иначе серия начинается заново)."""
    if not прошлый:
        return False
    try:
        a = time.mktime(time.strptime(сегодня, "%Y-%m-%d"))
        b = time.mktime(time.strptime(прошлый, "%Y-%m-%d"))
    except ValueError:
        return False
    return round((a - b) / 86400) == 1


def _record_streak_sqlite(group_id: str, mascot_id: str, streak: int) -> None:
    """Рекорд серии живёт в коллекции mascots, а она осталась в PocketBase.
    Событие редкое — общий день засчитывается паре раз в сутки."""
    try:
      with _lite_rw_lock:
        lite_rw.execute(
            "UPDATE mascots SET record_streak = ? "
            "WHERE group_id = ? AND mascot_id = ? AND COALESCE(record_streak, 0) < ?",
            (streak, group_id, mascot_id, streak))
        lite_rw.commit()
    except sqlite3.Error:
        pass  # рекорд не критичен, серия уже записана


async def _record_activity_pg(group_id: str, auth_uid: str, uid: str,
                              today: str):
    """Отметка общего дня целиком в Postgres.

    Прежний путь открывал транзакцию PocketBase на КАЖДЫЙ заход в приложение
    (восемь запросов в секунду вечером), и почти все впустую занимали
    единственное соединение записи. Здесь блокируется одна строка пары, а не
    вся база, поэтому пары не мешают друг другу вовсе.
    """
    async with pg.acquire() as c:
        async with c.transaction():
            row = await c.fetchrow(
                "SELECT members, streak_days, streak_last_opened_date, "
                "streak_pending_date, streak_pending_uid, active_mascot_id, "
                "mascot_streaks FROM groups WHERE id = $1 FOR UPDATE", group_id)
            if row is None:
                return ORJSONResponse({"ok": False, "error": "not a member"},
                                      status_code=403)
            члены = row["members"]
            if isinstance(члены, str):
                try:
                    члены = json.loads(члены)
                except ValueError:
                    члены = []
            if auth_uid not in [str(m) for m in (члены or [])]:
                return ORJSONResponse({"ok": False, "error": "not a member"},
                                      status_code=403)

            прошлый = row["streak_last_opened_date"] or ""
            if прошлый == today:
                return ORJSONResponse({"ok": True, "already": True})

            ждёт_дату = row["streak_pending_date"] or ""
            ждёт_кого = row["streak_pending_uid"] or ""
            # Соседний день тоже общий: у пары из разных поясов даты не
            # совпадают никогда (см. `_общий_день`).
            оба_сегодня = (bool(ждёт_кого) and ждёт_кого != uid
                           and _общий_день(today, ждёт_дату))
            if not оба_сегодня:
                if not _общий_день(today, ждёт_дату) or not ждёт_кого:
                    await c.execute(
                        "UPDATE groups SET streak_pending_date = $1, "
                        "streak_pending_uid = $2, updated = $3 WHERE id = $4",
                        today, uid, now_pb(), group_id)
                return ORJSONResponse({"ok": True, "pending": True})

            # Оба были сегодня — день засчитан.
            серия = (int(row["streak_days"] or 0) + 1
                     if _день_подряд(today, прошлый) else 1)
            маскот = row["active_mascot_id"] or ""
            карта = row["mascot_streaks"]
            if isinstance(карта, str):
                try:
                    карта = json.loads(карта)
                except ValueError:
                    карта = {}
            карта = карта if isinstance(карта, dict) else {}
            серия_маскота = 0
            if маскот:
                прежнее = карта.get(маскот) if isinstance(карта.get(маскот), dict) else {}
                серия_маскота = (int(прежнее.get("s") or 0) + 1
                                 if _день_подряд(today, str(прежнее.get("d") or ""))
                                 else 1)
                карта[маскот] = {"s": серия_маскота, "d": today}
            await c.execute(
                "UPDATE groups SET streak_days = $1, streak_last_opened_date = $2, "
                "mascot_streaks = $3, updated = $4 WHERE id = $5",
                float(серия), today, json.dumps(карта), now_pb(), group_id)

    if маскот and серия_маскота:
        await asyncio.to_thread(_record_streak_sqlite, group_id, маскот,
                                серия_маскота)
    return ORJSONResponse({"ok": True, "streak": серия,
                           "mascotStreak": серия_маскота})


КАРТЫ_УЧАСТНИКОВ = ("member_moods", "member_names", "member_avatars",
                    "member_ailments")


def _членство_в_sqlite(uids: list) -> None:
    """Пересчитать users.group_ids по составу пар — то, что делал хук
    groups_membership.pb.js на событиях коллекции groups.

    Список ведём в SQLite: правила доступа ВСЕХ коллекций, оставшихся в
    PocketBase, читают relation users.group_ids, и пустой список закрывает
    человеку запись начисто (наступали 13.08.2026). Считаем по зеркалу groups
    в SQLite — оно обновляется той же секундой, что и Postgres.
    """
    if not uids:
        return
    try:
      with _lite_rw_lock:
        for uid in uids:
            lite_rw.execute(
                "UPDATE users SET group_ids = COALESCE((SELECT json_group_array(g.id) "
                "FROM `groups` g WHERE EXISTS (SELECT 1 FROM json_each("
                "CASE WHEN json_valid(g.members) THEN g.members ELSE '[]' END) je "
                "WHERE je.value = ?)), '[]') WHERE id = ?", (uid, uid))
        lite_rw.commit()
    except sqlite3.Error as e:
        log.warning("группы участника не пересчитались (%s): %s", uids, e)


ЗЕРКАЛО_КОЛОНКИ = [c for c in COLLECTIONS["groups"]["columns"]]


def _зеркало_группы_sync(строки: list) -> int:
    """Положить строки пар из Postgres обратно в SQLite PocketBase.

    Зеркало нужно не ради красоты: правила доступа всех коллекций, оставшихся
    в PocketBase, ходят через relation users.group_ids -> groups, отчёты
    админки джойнят пары с пользователями, а хуки читают запись пары напрямую.
    Пустая или устаревшая таблица тут означает закрытую запись у живых людей.
    """
    if not строки:
        return 0
    # Одним upsert'ом, а не «UPDATE, не вышло — INSERT»: рабочих процессов у
    # hotpath несколько, и двое, взявшись за одну пару, ловили друг у друга
    # UNIQUE constraint failed.
    вставка = ", ".join(["id"] + [f"`{c}`" for c in ЗЕРКАЛО_КОЛОНКИ])
    места = ", ".join(["?"] * (len(ЗЕРКАЛО_КОЛОНКИ) + 1))
    поля = ", ".join(f"`{c}` = excluded.`{c}`" for c in ЗЕРКАЛО_КОЛОНКИ)
    with _lite_rw_lock:
        return _зеркало_группы_пишем(строки, вставка, места, поля)


def _зеркало_группы_пишем(строки, вставка, места, поля) -> int:
    сделано = 0
    # BEGIN только если своей транзакции ещё нет: питоновский sqlite3 открывает
    # её сам перед первой правкой, и явный BEGIN поверх падает с «cannot start
    # a transaction within a transaction» — зеркало тогда молча не обновляется.
    своя = not lite_rw.in_transaction
    if своя:
        lite_rw.execute("BEGIN IMMEDIATE")
    try:
        for row in строки:
            значения = []
            for c in ЗЕРКАЛО_КОЛОНКИ:
                v = row[c]
                kind = COLLECTIONS["groups"]["columns"][c]
                if kind == "json":
                    значения.append(v if isinstance(v, str) or v is None
                                    else json.dumps(v, ensure_ascii=False))
                elif kind == "bool":
                    значения.append(1 if v else 0)
                elif kind == "num":
                    значения.append(float(v or 0))
                else:
                    значения.append(v if v is not None else "")
            lite_rw.execute(
                f"INSERT INTO `groups` ({вставка}) VALUES ({места}) "
                f"ON CONFLICT(id) DO UPDATE SET {поля}",
                (row["id"], *значения))
            сделано += 1
        lite_rw.commit()
    except BaseException:
        lite_rw.rollback()
        raise
    return сделано


async def _после_правки_пары(group_id: str, участники: list | None = None,
                             событие: str = "update") -> None:
    """Разослать событие пары и, если состав менялся, обновить зеркало и группы.

    Порядок важен: сперва зеркало, потом пересчёт users.group_ids — иначе
    пересчёт прочитает в SQLite прежний состав и вернёт человеку права на
    пару, из которой он только что вышел.
    """
    async with pg.acquire() as c:
        row = await c.fetchrow("SELECT * FROM groups WHERE id = $1", group_id)
    if row is None:
        return
    rec = _record_json("groups", row)
    await _publish("groups", событие, rec)
    if участники:
        for попытка in range(3):
            try:
                await asyncio.to_thread(_зеркало_группы_sync, [row])
                break
            except sqlite3.Error as e:
                if попытка == 2:
                    # Не беда: строку подберёт периодическое зеркало, а список
                    # групп человека — подметальщик sweep_group_ids раз в минуту.
                    log.warning("зеркало пары %s не обновилось: %s", group_id, e)
                else:
                    await asyncio.sleep(0.4 * (попытка + 1))
        await asyncio.to_thread(_членство_в_sqlite, участники)
        # Свой кэш состава сбрасываем сразу: этот воркер отдаёт новые права с
        # первого же запроса. Соседним процессам хватит короткого TTL.
        for uid in участники:
            _groups_cache.pop(str(uid), None)


@app.post("/api/group/patch-map")
async def patch_map(request: Request):
    """Правка карты участника: настроение, имя, аватар, недомогание.

    Было чтение записи, правка карты в памяти и запись обратно внутри
    транзакции PocketBase. Стало одно выражение над jsonb: гонки двух телефонов
    больше нет в принципе, а строка блокируется на время самого UPDATE.
    """
    if GROUPS_SRC != "pg":
        return await _proxy_to_pb("/api/group/patch-map", request,
                                  await request.json())
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    auth_uid, _ = auth
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad params")

    group_id = str(body.get("groupId") or "").strip()
    field = str(body.get("field") or "").strip()
    uid = str(body.get("uid") or "").strip()
    if not group_id or not uid or field not in КАРТЫ_УЧАСТНИКОВ:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)

    значение = body.get("value")
    if значение is None:
        sql = (f"UPDATE groups SET {field} = COALESCE({field}, '{{}}'::jsonb) - $1, "
               "updated = $2 WHERE id = $3 AND members @> $4::jsonb RETURNING id")
        args = [uid, now_pb(), group_id, json.dumps([auth_uid])]
    else:
        sql = (f"UPDATE groups SET {field} = jsonb_set("
               f"COALESCE({field}, '{{}}'::jsonb), ARRAY[$1], $2::jsonb, true), "
               "updated = $3 WHERE id = $4 AND members @> $5::jsonb RETURNING id")
        args = [uid, json.dumps(значение), now_pb(), group_id,
                json.dumps([auth_uid])]
    async with pg.acquire() as c:
        got = await c.fetchval(sql, *args)
    if got is None:
        return ORJSONResponse({"ok": False, "error": "not a member"}, status_code=403)
    asyncio.get_running_loop().create_task(_после_правки_пары(group_id))
    return ORJSONResponse({"ok": True})


@app.post("/api/group/increment")
async def increment_field(request: Request):
    """Счётчик опыта пары. Остальные счётчики ведёт сервер по факту записи,
    поэтому старым сборкам отвечаем «сделано» и ничего не трогаем."""
    if GROUPS_SRC != "pg":
        return await _proxy_to_pb("/api/group/increment", request,
                                  await request.json())
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    auth_uid, _ = auth
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad params")

    field = str(body.get("field") or "").strip()
    if field in ("drawings_count", "memories_count"):
        return ORJSONResponse({"ok": True, "value": 0, "noop": True})
    group_id = str(body.get("groupId") or "").strip()
    try:
        by = float(body.get("by"))
    except (TypeError, ValueError):
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)
    if not group_id or field != "xp":
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)

    async with pg.acquire() as c:
        value = await c.fetchval(
            "UPDATE groups SET xp = COALESCE(xp, 0) + $1, updated = $2 "
            "WHERE id = $3 AND members @> $4::jsonb RETURNING xp",
            by, now_pb(), group_id, json.dumps([auth_uid]))
    if value is None:
        return ORJSONResponse({"ok": False, "error": "not a member"}, status_code=403)
    asyncio.get_running_loop().create_task(_после_правки_пары(group_id))
    return ORJSONResponse({"ok": True, "value": _num(value)})


@app.post("/api/group/leave")
async def leave_group(request: Request):
    """Выход из пары: убрать человека из состава и из всех карт, а опустевшую
    пару пометить распущенной. Записи пары остаются на месте — вернувшийся по
    коду второго места находит историю там же, где оставил."""
    if GROUPS_SRC != "pg":
        return await _proxy_to_pb("/api/group/leave", request,
                                  await request.json())
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    auth_uid, _ = auth
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad params")

    group_id = str(body.get("groupId") or "").strip()
    uid = str(body.get("uid") or "").strip()
    if not group_id or not uid:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)

    карты = ", ".join(
        f"{f} = COALESCE({f}, '{{}}'::jsonb) - $1" for f in КАРТЫ_УЧАСТНИКОВ)
    async with pg.acquire() as c:
        row = await c.fetchrow(
            "UPDATE groups SET members = COALESCE(members, '[]'::jsonb) - $1, "
            f"{карты}, "
            "disbanded = (jsonb_array_length(COALESCE(members, '[]'::jsonb) - $1) = 0), "
            "disbanded_at = CASE WHEN jsonb_array_length("
            "  COALESCE(members, '[]'::jsonb) - $1) = 0 THEN $2 ELSE disbanded_at END, "
            "updated = $2 WHERE id = $3 AND members @> $4::jsonb "
            "RETURNING members",
            uid, now_pb(), group_id, json.dumps([auth_uid]))
    if row is None:
        return ORJSONResponse({"ok": False, "error": "not a member"}, status_code=403)
    остались = row["members"]
    if isinstance(остались, str):
        try:
            остались = json.loads(остались)
        except ValueError:
            остались = []
    # Ушедшему группы пересчитываем тоже — иначе его правила доступа будут
    # помнить пару, из которой он вышел.
    затронуты = [str(m) for m in (остались or []) if m] + [uid]
    asyncio.get_running_loop().create_task(
        _после_правки_пары(group_id, затронуты))
    return ORJSONResponse({"ok": True})


@app.post("/api/coins/daily-bonus")
async def daily_bonus(request: Request):
    COOLDOWN_MS = 20 * 60 * 60 * 1000
    try:
        auth = await _auth(request)
    except Exception:
        return _err(429, "Try again later.")
    if auth is None:
        return _err(401, "The request requires valid record authorization token.")
    uid, _groups = auth

    seen = await asyncio.to_thread(_lite_user_bonus, uid)
    if seen is not None:
        last, coins = seen
        if last and int(time.time() * 1000) - last < COOLDOWN_MS:
            return ORJSONResponse({"ok": False, "cooldown": True, "coins": coins})
    return await _proxy_to_pb("/api/coins/daily-bonus", request, {})


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
    if col == "groups":
        # у пары событие идёт вместе с пересчётом членства и зеркалом
        участники = rec.get("members") if isinstance(rec.get("members"), list) else []
        asyncio.get_running_loop().create_task(
            _после_правки_пары(rid, [str(m) for m in участники], событие="create"))
    else:
        asyncio.get_running_loop().create_task(_publish(col, "create", rec))
    asyncio.get_running_loop().create_task(_after_create(col, rec))
    return rec


@app.post("/internal/group-write")
async def internal_group_write(request: Request):
    """Правка записи пары для серверной кухни: хуки PocketBase, скрипты.

    Нужен потому, что после переезда пары событий коллекции `groups` в
    PocketBase больше не происходит: хук, сохраняющий запись у себя, попадёт в
    зеркало, а зеркало односторонее. Поэтому все, кто раньше звал
    findRecordById + save, зовут этот маршрут и пишут прямо в Postgres.

    Тело: {group_id, mode: patch|create, set, inc, map_set, map_del, arr_add,
    members_changed}. Доступ только с самой машины — наружу /internal Caddy не
    маршрутизирует, но проверяем и здесь.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")

    group_id = str(body.get("group_id") or "").strip()
    if not group_id:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)
    колонки = COLLECTIONS["groups"]["columns"]

    def тип(f):
        return колонки.get(f)

    sets, args = [], []

    def добавить(v):
        args.append(v)
        return f"${len(args)}"

    for f, v in (body.get("set") or {}).items():
        k = тип(f)
        if k is None or k == "auto":
            continue
        if k == "json":
            sets.append(f"{f} = {добавить(json.dumps(v) if v is not None else None)}::jsonb")
        elif k == "num":
            sets.append(f"{f} = {добавить(float(v or 0))}")
        elif k == "bool":
            sets.append(f"{f} = {добавить(bool(v))}")
        else:
            sets.append(f"{f} = {добавить(str(v) if v is not None else '')}")
    for f, v in (body.get("inc") or {}).items():
        if тип(f) == "num":
            sets.append(f"{f} = GREATEST(0, COALESCE({f}, 0) + {добавить(float(v or 0))})")
    for f, карта in (body.get("map_set") or {}).items():
        if тип(f) != "json" or not isinstance(карта, dict):
            continue
        выражение = f"COALESCE({f}, '{{}}'::jsonb)"
        for ключ, значение in карта.items():
            выражение = (f"jsonb_set({выражение}, ARRAY[{добавить(str(ключ))}], "
                         f"{добавить(json.dumps(значение))}::jsonb, true)")
        sets.append(f"{f} = {выражение}")
    for f, ключи in (body.get("map_del") or {}).items():
        if тип(f) != "json" or not isinstance(ключи, list):
            continue
        выражение = f"COALESCE({f}, '{{}}'::jsonb)"
        for ключ in ключи:
            выражение = f"({выражение} - {добавить(str(ключ))})"
        sets.append(f"{f} = {выражение}")
    for f, значения in (body.get("arr_add") or {}).items():
        if тип(f) != "json" or not isinstance(значения, list):
            continue
        выражение = f"COALESCE({f}, '[]'::jsonb)"
        for знач in значения:
            один = добавить(json.dumps([знач]))
            выражение = (f"(CASE WHEN {выражение} @> {один}::jsonb THEN {выражение} "
                         f"ELSE {выражение} || {один}::jsonb END)")
        sets.append(f"{f} = {выражение}")

    sets.append(f"updated = {добавить(now_pb())}")
    режим = str(body.get("mode") or "patch")
    async with pg.acquire() as c:
        if режим == "create":
            есть = await c.fetchval("SELECT 1 FROM groups WHERE id = $1", group_id)
            if not есть:
                await c.execute(
                    "INSERT INTO groups (id, created_at, updated) VALUES ($1, $2, $2)",
                    group_id, now_pb())
        row = await c.fetchrow(
            f"UPDATE groups SET {', '.join(sets)} WHERE id = ${len(args) + 1} "
            "RETURNING *", *args, group_id)
    if row is None:
        return ORJSONResponse({"ok": False, "error": "no group"}, status_code=404)

    rec = _record_json("groups", row)
    участники = rec.get("members") if body.get("members_changed") else None
    участники = [str(m) for m in участники] if isinstance(участники, list) else None
    if body.get("members_changed"):
        # состав пары трогали — зеркало и списки групп людей обязаны догнать
        # немедленно, от них зависят правила доступа в PocketBase
        добавочные = [str(u) for u in (body.get("also_recount") or []) if u]
        try:
            await asyncio.to_thread(_зеркало_группы_sync, [row])
        except sqlite3.Error as e:
            log.warning("зеркало пары %s: %s", group_id, e)
        await asyncio.to_thread(_членство_в_sqlite,
                                (участники or []) + добавочные)
    asyncio.get_running_loop().create_task(_publish("groups", "update", rec))
    return ORJSONResponse({"ok": True, "record": rec})


def _поля_пары_из_sqlite(group_id: str, поля: list) -> tuple | None:
    строка = ", ".join(f"`{f}`" for f in поля)
    return lite.execute(
        f"SELECT {строка}, COALESCE(updated,'') FROM `groups` WHERE id = ?",
        (group_id,)).fetchone()


@app.post("/internal/group-sync")
async def internal_group_sync(request: Request):
    """Подтянуть в Postgres поля пары, которые только что записал хук PocketBase.

    Хуки (приём приглашения, дни рождения, покупки, пара с пустым местом)
    остались работать со своей записью в PocketBase: так сохраняются их
    транзакции, событие realtime и пересчёт users.group_ids. Здесь мы лишь
    переносим ИЗМЕНЁННЫЕ поля в Postgres, откуда их теперь читает приложение.

    Переносим точечно, а не строку целиком: между сохранением хука и этим
    вызовом приложение могло поправить в Postgres что-то своё (настроение,
    счётчик), и полная заливка стёрла бы эту правку.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")

    group_id = str(body.get("group_id") or "").strip()
    колонки = COLLECTIONS["groups"]["columns"]
    поля = [f for f in (body.get("fields") or [])
            if f in колонки and колонки[f] != "auto"]
    if not group_id or not поля:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)

    row = await asyncio.to_thread(_поля_пары_из_sqlite, group_id, поля)
    if row is None:
        return ORJSONResponse({"ok": False, "error": "no group"}, status_code=404)

    значения, sets = [], []
    for i, f in enumerate(поля):
        v = row[i]
        kind = колонки[f]
        if kind == "json":
            s = v if isinstance(v, str) or v is None else json.dumps(v)
            значения.append(s if (s or "").strip() else None)
            sets.append(f"{f} = ${len(значения)}::jsonb")
        elif kind == "num":
            значения.append(float(v or 0))
            sets.append(f"{f} = ${len(значения)}")
        elif kind == "bool":
            значения.append(bool(v))
            sets.append(f"{f} = ${len(значения)}")
        else:
            значения.append(str(v) if v is not None else "")
            sets.append(f"{f} = ${len(значения)}")
    # Время правки берём из SQLite: тогда зеркало видит, что базы согласованы,
    # и не понесёт строку обратно.
    значения.append(row[len(поля)] or now_pb())
    sets.append(f"updated = ${len(значения)}")
    значения.append(group_id)

    async with pg.acquire() as c:
        готово = await c.fetchval(
            f"UPDATE groups SET {', '.join(sets)} WHERE id = ${len(значения)} "
            "RETURNING id", *значения)
        if готово is None:
            # Пара только что заведена хуком — заносим её в Postgres целиком.
            все_поля = list(колонки)
            полная = await asyncio.to_thread(
                _поля_пары_из_sqlite, group_id,
                [f for f in все_поля if f != "updated"])
            if полная is None:
                return ORJSONResponse({"ok": False, "error": "no group"},
                                      status_code=404)
            await _поднять_из_sqlite([group_id])
    return ORJSONResponse({"ok": True})


АЗБУКА_КОДА = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _новый_код() -> str:
    return "".join(secrets.choice(АЗБУКА_КОДА) for _ in range(8))


@app.get("/internal/groups-of")
async def internal_groups_of(request: Request, uid: str = "", live: int = 1):
    """Пары человека — тем же смыслом, что фильтр members ~ uid у PocketBase."""
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    if not uid:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)
    условие = " AND disbanded = false" if live else ""
    async with pg.acquire() as c:
        rows = await c.fetch(
            f"SELECT * FROM groups WHERE members @> $1::jsonb{условие} "
            "ORDER BY updated DESC LIMIT 20", json.dumps([uid]))
    return ORJSONResponse({"ok": True,
                           "items": [_record_json("groups", r) for r in rows]})


@app.post("/internal/waiting-create")
async def internal_waiting_create(request: Request):
    """Завести пару, где второго ещё нет: его место держит заглушка.

    Проверка «живой пары ещё нет» и выдача свободного кода делаются здесь же,
    одной транзакцией: иначе два быстрых нажатия заводили две пары.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")
    uid = str(body.get("uid") or "").strip()
    имя_заглушки = str(body.get("placeholder_name") or "").strip()[:60]
    if not uid or not имя_заглушки:
        return ORJSONResponse({"success": False, "message": "Впишите имя"},
                              status_code=400)

    async with pg.acquire() as c:
        async with c.transaction():
            свои = await c.fetch(
                "SELECT members, claim_token FROM groups WHERE members @> $1::jsonb "
                "AND disbanded = false LIMIT 5", json.dumps([uid]))
            for r in свои:
                состав = r["members"]
                if isinstance(состав, str):
                    try:
                        состав = json.loads(состав)
                    except ValueError:
                        состав = []
                if len(состав or []) > 1 or (r["claim_token"] or ""):
                    return ORJSONResponse(
                        {"success": False, "message": "У вас уже есть пара"},
                        status_code=400)
            код = ""
            for _ in range(12):
                кандидат = _новый_код()
                занят = await c.fetchval(
                    "SELECT 1 FROM groups WHERE claim_token = $1", кандидат)
                if not занят:
                    код = кандидат
                    break
            if not код:
                return ORJSONResponse(
                    {"success": False, "message": "Не удалось выдать код"},
                    status_code=500)
            gid = _new_id()
            сейчас = now_pb()
            await c.execute(
                "INSERT INTO groups (id, members, member_names, member_avatars, "
                "max_members, relationship_type, custom_relationship_types, "
                "memories_count, drawings_count, start_date, created_at, "
                "disbanded, waiting_mode, placeholder_name, placeholder_avatar, "
                "return_date, claim_token, updated) VALUES "
                "($1, $2::jsonb, $3::jsonb, $4::jsonb, 2, 'couple', '[]'::jsonb, "
                "0, 0, $5, $5, false, true, $6, $7, $8, $9, $5)",
                gid, json.dumps([uid]),
                json.dumps({uid: str(body.get("my_name") or "")}),
                json.dumps({uid: str(body.get("my_avatar") or "")}),
                сейчас, имя_заглушки, str(body.get("placeholder_avatar") or ""),
                str(body.get("return_date") or ""), код)
    await _после_правки_пары(gid, [uid], событие="create")
    return ORJSONResponse({"success": True, "pairId": gid, "code": код})


@app.post("/internal/waiting-reset")
async def internal_waiting_reset(request: Request):
    """Выдать новый код второго места (код утёк, расставание).

    Занятое место кодом не освобождается: это отдельное решение и отдельная
    кнопка — роспуск пары.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")
    group_id = str(body.get("group_id") or "").strip()
    uid = str(body.get("uid") or "").strip()
    if not group_id or not uid:
        return ORJSONResponse({"success": False, "message": "Не указана пара"},
                              status_code=400)

    async with pg.acquire() as c:
        async with c.transaction():
            row = await c.fetchrow(
                "SELECT members FROM groups WHERE id = $1 FOR UPDATE", group_id)
            if row is None:
                return ORJSONResponse({"success": False, "message": "Пара не найдена"},
                                      status_code=404)
            состав = row["members"]
            if isinstance(состав, str):
                try:
                    состав = json.loads(состав)
                except ValueError:
                    состав = []
            состав = [str(m) for m in (состав or []) if m]
            if uid not in состав:
                return ORJSONResponse({"success": False, "message": "Это не ваша пара"},
                                      status_code=403)
            if len(состав) > 1:
                return ORJSONResponse({"success": False, "message": "Место уже занято"},
                                      status_code=400)
            код = ""
            for _ in range(12):
                кандидат = _новый_код()
                занят = await c.fetchval(
                    "SELECT 1 FROM groups WHERE claim_token = $1", кандидат)
                if not занят:
                    код = кандидат
                    break
            if not код:
                return ORJSONResponse({"success": False, "message": "Не удалось выдать код"},
                                      status_code=500)
            await c.execute(
                "UPDATE groups SET claim_token = $1, claim_uid = '', claim_name = '', "
                "claim_at = 0, waiting_mode = true, updated = $2 WHERE id = $3",
                код, now_pb(), group_id)
    asyncio.get_running_loop().create_task(_после_правки_пары(group_id))
    return ORJSONResponse({"success": True, "code": код})


@app.get("/internal/group-read")
async def internal_group_read(request: Request, id: str = "", claim_token: str = ""):
    """Запись пары для серверной кухни: по id или по коду второго места.

    Хуки читают пару отсюда, а не из SQLite: зеркало отстаёт на минуты, и
    решение, принятое по нему (место занято, заявка уже есть), было бы принято
    по вчерашним данным.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    if id:
        sql, args = "SELECT * FROM groups WHERE id = $1", [id]
    elif claim_token:
        # Код второго места ищем только у живых пар: у распущенных он остаётся
        # формально годным и уводил вернувшегося в пару без участников.
        sql = ("SELECT * FROM groups WHERE claim_token = $1 AND disbanded = false "
               "LIMIT 1")
        args = [claim_token]
    else:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)
    async with pg.acquire() as c:
        row = await c.fetchrow(sql, *args)
    if row is None:
        return ORJSONResponse({"ok": False, "error": "no group"}, status_code=404)
    return ORJSONResponse({"ok": True, "record": _record_json("groups", row)})


@app.post("/internal/pair-claim-approve")
async def internal_pair_claim_approve(request: Request):
    """Хозяйка пары подтверждает: «это он». Место занимается, код гасится.

    Атомарно по строке пары: два одновременных подтверждения не пустят в пару
    двоих, а повтор того же нажатия не задвоит участника.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")
    group_id = str(body.get("group_id") or "").strip()
    претендент = str(body.get("claim_uid") or "").strip()
    имя = str(body.get("claim_name") or "")
    аватар = str(body.get("claim_avatar") or "")
    if not group_id or not претендент:
        return ORJSONResponse({"ok": False, "error": "bad params"}, status_code=400)

    async with pg.acquire() as c:
        async with c.transaction():
            row = await c.fetchrow(
                "SELECT members, max_members FROM groups WHERE id = $1 FOR UPDATE",
                group_id)
            if row is None:
                return ORJSONResponse({"ok": False, "error": "no group"},
                                      status_code=404)
            состав = row["members"]
            if isinstance(состав, str):
                try:
                    состав = json.loads(состав)
                except ValueError:
                    состав = []
            состав = [str(m) for m in (состав or []) if m]
            if претендент not in состав:
                предел = int(row["max_members"] or 2) or 2
                if len(состав) >= предел:
                    return ORJSONResponse({"ok": False, "error": "full"},
                                          status_code=400)
                состав.append(претендент)
            await c.execute(
                "UPDATE groups SET members = $1::jsonb, "
                "member_names = jsonb_set(COALESCE(member_names, '{}'::jsonb), "
                "  ARRAY[$2], $3::jsonb, true), "
                "member_avatars = jsonb_set(COALESCE(member_avatars, '{}'::jsonb), "
                "  ARRAY[$2], $4::jsonb, true), "
                "waiting_mode = false, claim_token = '', claim_uid = '', "
                "claim_name = '', claim_at = 0, updated = $5 WHERE id = $6",
                json.dumps(состав), претендент, json.dumps(имя),
                json.dumps(аватар), now_pb(), group_id)
    await _после_правки_пары(group_id, состав)
    return ORJSONResponse({"ok": True, "members": состав})


@app.post("/internal/pair-accept")
async def internal_pair_accept(request: Request):
    """Приём кода приглашения целиком в Postgres.

    Раньше это жило в invite.pb.js и держалось на транзакциях PocketBase: они
    сериализовали параллельные приёмы на единственном соединении записи. В
    Postgres та же гарантия даётся блокировкой одной строки пары, поэтому
    приёмы разных пар больше не стоят друг за другом.

    Ветвление сохранено один в один: код привязан к паре → войти; у
    приглашающего есть живая пара с местом → войти; есть общая распущенная →
    поднять; иначе завести новую.
    """
    if (request.client.host if request.client else "") not in ("127.0.0.1", "::1"):
        return _err(404, "The requested resource wasn't found.")
    try:
        body = await request.json()
        assert isinstance(body, dict)
    except Exception:
        return _err(400, "bad body")

    хозяин = str(body.get("owner_uid") or "").strip()
    я = str(body.get("my_uid") or "").strip()
    код_группы = str(body.get("code_group_id") or "").strip()
    имена = {хозяин: str(body.get("owner_name") or "Partner"),
             я: str(body.get("my_name") or "")}
    аватары = {хозяин: str(body.get("owner_avatar") or ""),
               я: str(body.get("my_avatar") or "")}
    if not хозяин or not я or хозяин == я:
        return ORJSONResponse({"success": False, "message": "bad params"},
                              status_code=400)

    async with pg.acquire() as c:
        async with c.transaction():
            async def войти(gid: str):
                row = await c.fetchrow(
                    "SELECT members, max_members, disbanded FROM groups "
                    "WHERE id = $1 FOR UPDATE", gid)
                if row is None:
                    return None
                состав = row["members"]
                if isinstance(состав, str):
                    try:
                        состав = json.loads(состав)
                    except ValueError:
                        состав = []
                состав = [str(m) for m in (состав or []) if m]
                if я in состав:
                    # Повтор приёма своего же кода: пара уже собрана. Отвечаем
                    # успехом с тем же id — раньше человек ловил тут «Код не
                    # найден» поверх состоявшейся пары, 517 отказов за сутки.
                    return {"success": True, "message": "Connected!", "pairId": gid}
                предел = int(row["max_members"] or 2) or 2
                if len(состав) >= предел:
                    return {"success": False, "message": "Группа заполнена"}
                состав.append(я)
                await c.execute(
                    "UPDATE groups SET members = $1::jsonb, "
                    "member_names = jsonb_set(COALESCE(member_names, '{}'::jsonb), "
                    "  ARRAY[$2], $3::jsonb, true), "
                    "member_avatars = jsonb_set(COALESCE(member_avatars, '{}'::jsonb), "
                    "  ARRAY[$2], $4::jsonb, true), "
                    "disbanded = false, updated = $5 WHERE id = $6",
                    json.dumps(состав), я, json.dumps(имена[я]),
                    json.dumps(аватары[я]), now_pb(), gid)
                return {"success": True, "message": "Joined the group!",
                        "pairId": gid, "_members": состав}

            итог = None
            if код_группы:
                итог = await войти(код_группы)
            if итог is None:
                # живая пара приглашающего, где есть место
                строки = await c.fetch(
                    "SELECT id FROM groups WHERE members @> $1::jsonb "
                    "AND disbanded = false ORDER BY updated DESC LIMIT 5",
                    json.dumps([хозяин]))
                for r in строки:
                    итог = await войти(r["id"])
                    if итог and итог.get("success"):
                        break
                    итог = None
            if итог is None:
                # общая распущенная пара — поднимаем её со всей историей
                строка = await c.fetchrow(
                    "SELECT id FROM groups WHERE members @> $1::jsonb "
                    "AND members @> $2::jsonb ORDER BY updated DESC LIMIT 1",
                    json.dumps([хозяин]), json.dumps([я]))
                if строка is not None:
                    await c.execute(
                        "UPDATE groups SET members = $1::jsonb, "
                        "member_names = COALESCE(member_names, '{}'::jsonb) || $2::jsonb, "
                        "member_avatars = COALESCE(member_avatars, '{}'::jsonb) || $3::jsonb, "
                        "disbanded = false, disbanded_at = '', updated = $4 "
                        "WHERE id = $5",
                        json.dumps([хозяин, я]), json.dumps(имена),
                        json.dumps(аватары), now_pb(), строка["id"])
                    итог = {"success": True, "message": "Reconnected!",
                            "pairId": строка["id"], "restored": True,
                            "_members": [хозяин, я]}
            if итог is None:
                # заводим новую пару
                gid = _new_id()
                await c.execute(
                    "INSERT INTO groups (id, members, member_names, member_avatars, "
                    "max_members, relationship_type, custom_relationship_types, "
                    "memories_count, drawings_count, start_date, created_at, "
                    "disbanded, updated) VALUES ($1, $2::jsonb, $3::jsonb, $4::jsonb, "
                    "2, 'couple', '[]'::jsonb, 0, 0, $5, $5, false, $5)",
                    gid, json.dumps([хозяин, я]), json.dumps(имена),
                    json.dumps(аватары), now_pb())
                итог = {"success": True, "message": "Connected!", "pairId": gid,
                        "_members": [хозяин, я], "_new": True}

    участники = итог.pop("_members", None)
    новая = итог.pop("_new", False)
    if итог.get("success"):
        # Событие обязано быть «create» именно у новой пары: клиент
        # приглашающего ждёт появления записи, а правку существующей он
        # отфильтрует — и пара не появится у него до перезапуска приложения
        # (ровно та жалоба, что разбиралась 02.08.2026).
        await _после_правки_пары(итог["pairId"], участники or [хозяин, я],
                                 событие="create" if новая else "update")
    return ORJSONResponse(итог)


@app.get("/internal/online")
async def internal_online(uid: str):
    """На связи ли человек — присутствие живёт в Postgres с 14.08.2026.
    Спрашивает apns_push.js, чтобы не слать пуш тому, у кого открыт экран."""
    online = await _online_uids([uid]) if uid else set()
    return {"online": uid in online}


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
    uid, groups = auth

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
        if op == "@>":
            if meta["columns"].get(field) != "json":
                return _err(400, "Something went wrong while processing your request.")
            args.append(val)
            where.append(f"{field} @> ${len(args)}::jsonb")
            continue
        args.append(_coerce(col, field, val))
        where.append(f"{field} {op} ${len(args)}")
        if field == "group_id" and op == "=":
            filtered_group = val
    # listRule PB. По умолчанию — «только свои группы»; у presence правило
    # мягче (любой залогиненный), у геопозиции ключ не группа, а канал.
    scope = meta.get("scope", "group")
    empty = {
        "page": page, "perPage": per_page,
        "totalItems": -1 if skip_total else 0,
        "totalPages": -1 if skip_total else 0,
        "items": [],
    }
    if scope == "authed":
        pass  # ограничений нет
    elif scope == "members":
        # Правило записи пары: members ?~ @request.auth.id. Условие ставим
        # ВСЕГДА, даже когда клиент уже прислал такой фильтр сам, — дубль
        # безвреден (тот же индекс), а забытая проверка отдала бы чужую пару.
        args.append(json.dumps([uid]))
        where.append(f"members @> ${len(args)}::jsonb")
    elif scope == "channel":
        chan = next((v for f, op, v in conds if f == "channel" and op == "="), None)
        if chan is not None:
            if uid not in str(chan) and str(chan) not in groups:
                return empty
        else:
            # без явного канала отдаём только свои: личные плюс парные
            args.append(list(groups))
            where.append(f"(channel LIKE '%' || ${len(args) + 1} || '%' OR channel = ANY(${len(args)}))")
            args.append(uid)
    elif filtered_group is not None:
        if filtered_group not in groups:
            return empty
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


@app.get("/api/collections/{col}/records/{rid}")
async def get_record(col: str, rid: str, request: Request):
    """Чтение одной записи (getOne у клиента).

    Заведено ради записи пары: приём приглашения читает группу именно так
    (`collection('groups').getOne(pairId)`), и без этого маршрута ответом на
    вступление в пару приходил бы 404.
    """
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

    scope = meta.get("scope", "group")
    if scope == "authed":
        cond, args = "TRUE", [rid]
    elif scope == "members":
        cond, args = "members @> $2::jsonb", [rid, json.dumps([uid])]
    elif scope == "channel":
        cond, args = "(channel LIKE '%' || $2 || '%' OR channel = ANY($3))", [
            rid, uid, list(groups)]
    else:
        cond, args = "group_id = ANY($2)", [rid, list(groups)]
    async with pg.acquire() as c:
        row = await c.fetchrow(f"SELECT * FROM {col} WHERE id = $1 AND {cond}", *args)
    if row is None:
        # Чужое и несуществующее PocketBase прячет одним 404.
        return _err(404, "The requested resource wasn't found.")
    return _record_json(col, row)


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

    scope = meta.get("scope", "group")
    if scope == "group":
        if str(body.get("group_id") or "") not in groups:
            # createRule не прошёл — PB в этом случае тоже отвечает 400.
            return _err(400, "Failed to create record.")
    elif scope == "members":
        # Завести пару можно только с собой внутри — как createRule у PB.
        сам = body.get("members")
        if not isinstance(сам, list) or uid not in [str(m) for m in сам]:
            return _err(400, "Failed to create record.")
    elif scope == "channel":
        chan = str(body.get("channel") or "")
        if uid not in chan and chan not in groups:
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
        if kind in ("json", "jsontext"):
            if v is None:
                vals.append(None)
            elif kind == "jsontext" and isinstance(v, str):
                vals.append(v if v.strip() else None)
            else:
                vals.append(json.dumps(v))
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

    # Страж пары (перенос groups_guard.pb.js). Правило коллекции пускает
    # участника писать в запись любое поле, поэтому обычным PATCH можно было
    # вписать в пару третий аккаунт — и он получал переписку, ленту и карту.
    # Клиент состав только СОКРАЩАЕТ (выход из пары), добавляют серверные пути.
    if col == "groups":
        ЗАКРЫТЫЕ = ("claim_token", "claim_uid", "claim_name", "claim_at",
                    "waiting_mode")
        for f in ЗАКРЫТЫЕ:
            if f in body:
                # Код второго места и заявку на него пишет только сервер:
                # иначе участник подменит код своим и уведёт чужую заявку.
                return _err(403, f"read-only pairing field: {f}")
        if "members" in body:
            новый = body.get("members")
            if not isinstance(новый, list):
                return _err(403, "members must be a list")
            async with pg.acquire() as c:
                текущий = await c.fetchval(
                    "SELECT members FROM groups WHERE id = $1", rid)
            if isinstance(текущий, str):
                try:
                    текущий = json.loads(текущий)
                except ValueError:
                    текущий = []
            текущий = [str(m) for m in (текущий or [])]
            for m in новый:
                if str(m) not in текущий:
                    return _err(403, "cannot add members directly")

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
        if kind in ("json", "jsontext"):
            if v is None:
                args.append(None)
            elif kind == "jsontext" and isinstance(v, str):
                args.append(v if v.strip() else None)
            else:
                args.append(json.dumps(v))
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
    owner_upd = meta.get("update_owner_field")
    if owner_upd:
        args.append(uid)
        cond = f"{owner_upd} = ${len(args)}"
    elif meta.get("scope") == "members":
        args.append(json.dumps([uid]))
        cond = f"members @> ${len(args)}::jsonb"
    else:
        args.append(list(groups))
        cond = f"group_id = ANY(${len(args)})"
    sql = (
        f"UPDATE {col} SET {', '.join(sets) or 'id = id'} "
        f"WHERE id = ${len(args) - 1} AND {cond} RETURNING *"
    )
    async with pg.acquire() as c:
        row = await c.fetchrow(sql, *args)
    if row is None:
        # Чужое и несуществующее PB прячет одним 404.
        return _err(404, "The requested resource wasn't found.")
    rec = _record_json(col, row)
    if col == "groups" and "members" in body:
        # Состав пары сократили (человек вышел сам, когда серверный роут не
        # ответил) — зеркало и списки групп обязаны догнать сразу, иначе
        # правила доступа в PocketBase будут помнить прежнюю пару.
        участники = rec.get("members") if isinstance(rec.get("members"), list) else []
        asyncio.get_running_loop().create_task(
            _после_правки_пары(rid, [str(m) for m in участники] + [uid]))
    else:
        asyncio.get_running_loop().create_task(_publish(col, "update", rec))
        asyncio.get_running_loop().create_task(_after_update(col, rec))
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
    owner_del = meta.get("update_owner_field")
    async with pg.acquire() as c:
        if owner_del:
            row = await c.fetchrow(
                f"DELETE FROM {col} WHERE id = $1 AND {owner_del} = $2 RETURNING *", rid, uid)
        elif meta.get("scope") == "members":
            row = await c.fetchrow(
                f"DELETE FROM {col} WHERE id = $1 AND members @> $2::jsonb RETURNING *",
                rid, json.dumps([uid]))
        else:
            row = await c.fetchrow(
                f"DELETE FROM {col} WHERE id = $1 AND group_id = ANY($2) RETURNING *",
                rid, list(groups))
    if row is None:
        return _err(404, "The requested resource wasn't found.")
    rec = _record_json(col, row)
    asyncio.get_running_loop().create_task(_publish(col, "delete", rec))
    _after_delete(col, rec)
    return Response(status_code=204)


# ── запуск ───────────────────────────────────────────────────────────────────


def _claim_background_role() -> bool:
    """Фоновые задачи (счётчики, зеркало присутствия) должен вести ОДИН процесс.

    Сервис работает в несколько рабочих процессов — иначе один Python упирается
    в одно ядро, а через него идёт всё присутствие (поймано живьём 14.08.2026:
    процесс на 100% ядра, очередь запросов, 121 тысяча висящих потоков в Caddy).
    Роль забирает тот, кому достался файловый замок; остальные только отвечают
    на запросы."""
    global _bg_lock_fd
    try:
        _bg_lock_fd = os.open("/tmp/hotpath.bg.lock", os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(_bg_lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


@app.on_event("startup")
async def _startup():
    # Уровень ставится ЗДЕСЬ, а не рядом с basicConfig: uvicorn поднимает свою
    # конфигурацию логов уже после импорта модуля и сбрасывает выставленное
    # раньше. Публикаций в Centrifugo идёт под сотню в секунду, и поток
    # «HTTP Request … 200 OK» забивал journald полумиллионом строк в час.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    global pg, cent_client, push_client, pb_client, lite, lite_rw, auth_secret
    pg = await asyncpg.create_pool(PG_DSN, min_size=2, max_size=10)
    cent_client = httpx.AsyncClient(base_url=CENT_API, timeout=3.0)
    # Редкие записи уходят в PocketBase как есть. Таймаут щедрый: под
    # нагрузкой он отвечает секунды, и обрывать раньше клиента незачем.
    pb_client = httpx.AsyncClient(
        base_url=os.environ.get("PB_URL", "http://127.0.0.1:8090"), timeout=40.0)
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
    if _claim_background_role():
        log.info("этот процесс ведёт фоновые задачи (пары: %s)", GROUPS_SRC)
        asyncio.get_running_loop().create_task(_counter_worker())
        asyncio.get_running_loop().create_task(_presence_mirror_worker())
        asyncio.get_running_loop().create_task(_зеркало_воркер())


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
    # Рабочих процессов по числу ядер минус два (PocketBase и Caddy тоже едят).
    workers = int(os.environ.get("HOTPATH_WORKERS", "0")) or max(2, (os.cpu_count() or 4) - 2)
    uvicorn.run("hotpath:app", host="127.0.0.1", port=LISTEN_PORT,
                log_level="warning", workers=workers,
                # Быстрый цикл событий и разбор HTTP на C вместо чистого
                # Python: та же работа обходится примерно на четверть дешевле.
                loop="uvloop", http="httptools",
                # Держим соединение открытым дольше: Caddy переиспользует его
                # вместо того, чтобы плодить новые под каждый запрос.
                timeout_keep_alive=30)
