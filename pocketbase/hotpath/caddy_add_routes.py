#!/usr/bin/env python3
"""Вставить в Caddyfile маршруты переехавших коллекций (19.10.2026).

Блоки встают перед маршрутом записи пары, тем же видом, что у прочих
коллекций hotpath. Повторный запуск ничего не дублирует. Копия прежнего
файла кладётся рядом с меткой времени.

    python3 caddy_add_routes.py /etc/caddy/Caddyfile 10.10.0.1:8120   # точка входа
    python3 caddy_add_routes.py /etc/caddy/Caddyfile 127.0.0.1:8120   # основной сервер
"""

import shutil
import sys
import time

COLLECTIONS = [
    ("love_tests", "Тест «Умение любить» — в hotpath (Postgres). 19.10.2026."),
    ("mascots", "Маскоты пары — в hotpath (Postgres). 19.10.2026."),
    ("cycle_entries", "Отметки цикла — в hotpath (Postgres). 19.10.2026."),
    ("wishes", "Желания пары — в hotpath (Postgres). 19.10.2026."),
    ("wish_categories", "Категории желаний — в hotpath (Postgres). 19.10.2026."),
    ("app_config", "Настройки приложения — копия в hotpath. 19.10.2026."),
    ("gifts", "Подарки: чтение из SQLite в hotpath, запись у PocketBase. 19.10.2026."),
]
# Сюда идёт только чтение (GET): записи с файлами, хуками и рассылкой
# остаются за PocketBase, hotpath читает те же строки из SQLite.
READ_ONLY_ROUTES = [
    ("watch_history", "История просмотров: чтение из SQLite в hotpath. 19.10.2026."),
    ("canvas_catalogue", "Каталог холстов: чтение из SQLite в hotpath. 19.10.2026."),
    ("memory_comments", "Комментарии: чтение из SQLite в hotpath. 19.10.2026."),
    ("watch_videos", "Свои ролики: чтение из SQLite в hotpath. 19.10.2026."),
    ("custom_moods", "Свои настроения: чтение из SQLite в hotpath. 19.10.2026."),
    ("catalog_items", "Каталог: чтение из SQLite в hotpath. 19.10.2026."),
    ("users", "Свой профиль: чтение из SQLite в hotpath, вход и правки у PocketBase. 19.10.2026."),
]
ANCHOR = "\thandle /api/collections/groups/records* {"

path, upstream = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    text = f.read()
if ANCHOR not in text:
    sys.exit(f"не нашёл место вставки: {ANCHOR.strip()}")

blocks = ""
for name, note in COLLECTIONS:
    if f"handle /api/collections/{name}/records*" in text:
        print(f"{name}: маршрут уже есть")
        continue
    blocks += (
        f"\thandle /api/collections/{name}/records* {{\n"
        f"\t\t# {note}\n"
        f"\t\treverse_proxy {upstream} {{\n"
        "\t\t\ttransport http {\n"
        "\t\t\t\tkeepalive 30s\n"
        "\t\t\t\tkeepalive_idle_conns 256\n"
        "\t\t\t\tkeepalive_idle_conns_per_host 256\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n\n"
    )
PATH_ROUTES = [
    ("/api/user/card", "Карточка партнёра — в hotpath. 19.10.2026."),
    ("/api/centrifugo/connection-token", "Токен подключения Centrifugo — в hotpath. 19.10.2026."),
    ("/api/centrifugo/subscription-token", "Пропуск в канал Centrifugo — в hotpath. 19.10.2026."),
]
for path_, note in PATH_ROUTES:
    if f"handle {path_} {{" in text:
        print(f"{path_}: маршрут уже есть")
        continue
    blocks += (
        f"\thandle {path_} {{\n"
        f"\t\t# {note}\n"
        f"\t\treverse_proxy {upstream} {{\n"
        "\t\t\ttransport http {\n"
        "\t\t\t\tkeepalive 30s\n"
        "\t\t\t\tkeepalive_idle_conns 256\n"
        "\t\t\t\tkeepalive_idle_conns_per_host 256\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n\n"
    )
for name, note in READ_ONLY_ROUTES:
    if f"@{name}_read" in text:
        print(f"{name}: маршрут чтения уже есть")
        continue
    blocks += (
        f"\t@{name}_read {{\n"
        "\t\tmethod GET\n"
        f"\t\tpath /api/collections/{name}/records*\n"
        "\t}\n"
        f"\thandle @{name}_read {{\n"
        f"\t\t# {note}\n"
        f"\t\treverse_proxy {upstream} {{\n"
        "\t\t\ttransport http {\n"
        "\t\t\t\tkeepalive 30s\n"
        "\t\t\t\tkeepalive_idle_conns 256\n"
        "\t\t\t\tkeepalive_idle_conns_per_host 256\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n\n"
    )
if not blocks:
    sys.exit(0)

backup = f"{path}.bak-before-love-mascots-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(path, backup)
text = text.replace(ANCHOR, blocks + ANCHOR, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
print(f"маршруты вставлены, копия прежнего файла: {backup}")
