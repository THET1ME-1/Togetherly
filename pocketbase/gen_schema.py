#!/usr/bin/env python3
"""Генератор схемы коллекций PocketBase (Этап 3 миграции Firebase→PocketBase).

Чертёж — supabase/*.sql (плоские таблицы с group_id). Здесь они переносятся в
коллекции PocketBase v0.39.4 по дизайну из памяти проекта:

  • Firebase-id (переопределяем системное поле id, чтобы принять id из Firebase:
    смешанный регистр, '_' в mood-id, до 50 симв.):
        groups, memories, mood_entries, chat_messages, canvas_strokes,
        memory_comments, catalog_items(id=slug), migration_flags(id=group_id),
        app_config(id="1"), iap_purchases(id=purchase_token, длинный → max 255).
  • Авто-id PB + составной UNIQUE-индекс (нет одиночного fb-id, ключ составной):
        widget_data(group_id,user_uid), miss_you(group_id,user_uid),
        canvas_meta(group_id,canvas_id), canvas_catalogue(group_id,canvas_id),
        mascots(group_id,mascot_id), chat_reads(group_id,user_uid).
  • users — отдельной коллекции тут НЕТ: это дефолтная auth-коллекция PB, её
    поля дописываются PATCH-ом (см. apply_schema.py), а не пересоздаются.
    id у users тоже override (внешний id мигрированного юзера = прежний uid;
    новым — авто-id). Отдельного uid-поля нет: данные ссылаются на users.id.

Имена полей — snake_case, как в Supabase: маппинг Firebase→snake_case уже есть
в коде (_sb.*), переиспользуем его на Этапе 5 (импорт данных).

Типы: TEXT→text, INT/BIGINT/DOUBLE/REAL→number, BOOLEAN→bool,
TIMESTAMPTZ→date, JSONB→json. Колонка-генератор `gc` из canvas.* отброшена —
её роль (составной индекс) выполняет прямой индекс по (group_id,canvas_id,...).

Запуск:  python3 pocketbase/gen_schema.py  →  pocketbase/collections_schema.json
"""
import json
import os

# ── хелперы полей ───────────────────────────────────────────────────────────
def t(name, required=False):      # text
    return {"name": name, "type": "text", "required": required}

def num(name, required=False):    # number (int/bigint/double/real)
    return {"name": name, "type": "number", "required": required}

def b(name):                      # bool
    return {"name": name, "type": "bool", "required": False}

def d(name, required=False):      # date (timestamptz)
    return {"name": name, "type": "date", "required": required}

def j(name):                      # json (jsonb)
    return {"name": name, "type": "json", "required": False, "maxSize": 5000000}

def fid(max_len=50):
    """Переопределённое системное поле id под Firebase-id (проверено на проде)."""
    return {
        "name": "id", "type": "text", "primaryKey": True, "required": True,
        "system": True, "pattern": "^[A-Za-z0-9_-]+$", "min": 1, "max": max_len,
        "autogeneratePattern": "",
    }

def uidx(table, cols, unique=True):
    kind = "UNIQUE INDEX" if unique else "INDEX"
    name = f"idx_{table}_" + "_".join(cols)
    colsql = ", ".join(f"`{c}`" for c in cols)
    return f"CREATE {kind} `{name}` ON `{table}` ({colsql})"

# ── коллекции с Firebase-id (переопределяем id) ───────────────────────────────
fb_collections = []

def fb(name, fields, indexes=None, id_max=50):
    fb_collections.append({
        "name": name, "type": "base",
        "fields": [fid(id_max)] + fields,
        "indexes": indexes or [],
    })

fb("groups", [
    j("members"), j("member_names"), j("member_avatars"), num("max_members"),
    t("relationship_type"), t("custom_relationship_label"),
    t("custom_relationship_emoji"), j("custom_relationship_types"),
    d("start_date"), d("anniversary_date"), d("first_kiss_date"),
    j("member_birthdays"), j("member_moods"), j("current_status"),
    j("custom_statuses"), num("memories_count"), num("drawings_count"),
    j("active_session"), d("created_at"), b("disbanded"), d("disbanded_at"),
    j("timers"), j("mascots"), num("xp"), t("active_mascot_id"),
    num("mascot_position_x"), num("mascot_position_y"), num("mascot_scale"),
    num("streak_days"), t("streak_last_opened_date"), t("streak_pending_date"),
    t("streak_pending_uid"),
])

fb("memories", [
    t("group_id", True), t("type"), t("author_uid"), t("author_name"),
    t("author_avatar"), d("created_at"), d("edited_at"), j("data"),
    b("is_pinned"), b("deleted"),
], indexes=[uidx("memories", ["group_id", "created_at"], unique=False)])

fb("mood_entries", [
    t("group_id", True), t("user_uid", True), t("mood_id"), t("image_path"),
    t("label"), d("timestamp", True),
], indexes=[uidx("mood_entries", ["group_id", "user_uid", "timestamp"], unique=False)])

fb("chat_messages", [
    t("group_id", True), t("user_uid"), t("user_name"), t("text"),
    num("ts", True), num("edited_ts"), j("reactions"), t("pin_id"),
    t("pin_title"), t("pin_thumb"), b("deleted"), t("face"), num("color"),
    num("face_x"), num("face_y"), t("reply_to_id"), t("reply_to_name"),
    t("reply_to_text"),
], indexes=[uidx("chat_messages", ["group_id", "ts"], unique=False)])

fb("canvas_strokes", [
    t("group_id", True), t("canvas_id", True), num("order_index"), j("data"),
    b("deleted"),
], indexes=[uidx("canvas_strokes", ["group_id", "canvas_id", "order_index"], unique=False)])

fb("memory_comments", [
    t("group_id", True), t("memory_id", True), t("author_uid"),
    t("author_name"), t("author_avatar"), t("text"), d("created_at"),
    b("deleted"),
], indexes=[uidx("memory_comments", ["group_id", "memory_id", "created_at"], unique=False)])

fb("catalog_items", [
    t("kind", True), t("name_ru"), t("name_en"), b("is_free"), t("min_app"),
    num("sort"), j("data"), b("enabled"), d("updated_at"),
], indexes=[uidx("catalog_items", ["kind"], unique=False)])

# purchase_token бывает длинным (Google Play) → max 255
fb("iap_purchases", [
    t("user_uid", True), t("product_id"), num("amount"), d("at"),
], id_max=255)

fb("migration_flags", [
    num("data_version"), num("media_version"), d("updated_at"),
])

# app_config — синглтон (id="1"), источник min_build для PB-версии приложения
fb("app_config", [
    num("min_build"), d("updated_at"),
])

# ── коллекции с авто-id PB + составной UNIQUE ────────────────────────────────
auto_collections = []

def auto(name, fields, unique_cols, extra_indexes=None):
    idx = [uidx(name, unique_cols, unique=True)]
    if extra_indexes:
        idx += extra_indexes
    auto_collections.append({
        "name": name, "type": "base", "fields": fields, "indexes": idx,
    })

auto("widget_data", [
    t("group_id", True), t("user_uid", True), t("display_name"),
    t("avatar_url"), t("gender"), t("status"), t("mood_emoji"),
    t("mood_label"), t("message"), t("music_title"), t("music_artist"),
    t("music_url"), t("music_cover_url"), t("photo_url"), j("data"),
    d("updated_at"), t("photo_for_partner_url"), j("photo_for_partner_urls"),
    num("photo_grid_count"), j("photo_grid_urls"),
], ["group_id", "user_uid"])

auto("miss_you", [
    t("group_id", True), t("user_uid", True), num("count"), d("updated_at"),
    # тип последнего вайба и кастом-текст — чтобы SSE-событие у партнёра несло
    # содержимое уведомления (miss_you/thinking_of_you/want_hug/custom)
    t("last_vibe"), t("last_vibe_text"),
], ["group_id", "user_uid"], extra_indexes=[uidx("miss_you", ["group_id"], unique=False)])

auto("canvas_meta", [
    t("group_id", True), t("canvas_id", True), num("bg_color"),
    num("clear_version"), num("canvas_rotation"), d("updated_at"),
], ["group_id", "canvas_id"])

auto("canvas_catalogue", [
    t("group_id", True), t("canvas_id", True), t("name"), num("created_at"),
    num("updated_at"), t("created_by"),
], ["group_id", "canvas_id"])

# в SQL mascots.id — это id маскота (не PK строки), переименован в mascot_id,
# т.к. системное поле id у PB занято авто-PK
auto("mascots", [
    t("group_id", True), t("mascot_id", True), t("name"), t("image_url"),
    t("default_asset"), t("created_by"), d("created_at"), b("is_default"),
    num("record_streak"),
], ["group_id", "mascot_id"], extra_indexes=[uidx("mascots", ["group_id"], unique=False)])

auto("chat_reads", [
    t("group_id", True), t("user_uid", True), num("last_read_ts"),
    d("updated_at"),
], ["group_id", "user_uid"])

# ── MEDIA (PB Storage): файлы крепятся к записям через file-поле ─────────────
# Замена Firebase Storage. Один блоб = одна запись; URL отдаётся PB как
# /api/files/media/<recordId>/<filename>. В текстовые поля сущностей
# (photo_url/image_url/...) кладём этот URL (или схему pb://media/<id>/<file>).
def file_field(name, max_mb=50):
    return {"name": name, "type": "file", "required": False,
            "maxSelect": 1, "maxSize": max_mb * 1024 * 1024, "mimeTypes": []}

media_collection = {
    "name": "media", "type": "base",
    "fields": [file_field("file"), t("uid"), t("group_id"), t("kind")],
    "indexes": [uidx("media", ["group_id"], unique=False)],
}

# ── вывод ────────────────────────────────────────────────────────────────────
collections = fb_collections + auto_collections + [media_collection]
out = {"collections": collections, "deleteMissing": False}

path = os.path.join(os.path.dirname(__file__), "collections_schema.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)

print(f"Сгенерировано коллекций: {len(collections)}")
for c in collections:
    kind = "fb-id" if c is fb_collections[0] or c in fb_collections else "auto-id"
    print(f"  {c['name']:18} {kind:7} полей={len(c['fields'])} индексов={len(c['indexes'])}")
print(f"→ {path}")
