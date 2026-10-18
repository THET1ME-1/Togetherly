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
if not blocks:
    sys.exit(0)

backup = f"{path}.bak-before-love-mascots-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(path, backup)
text = text.replace(ANCHOR, blocks + ANCHOR, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
print(f"маршруты вставлены, копия прежнего файла: {backup}")
