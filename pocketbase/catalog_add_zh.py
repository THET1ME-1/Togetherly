#!/usr/bin/env python3
"""Новый язык в серверном каталоге: названия и подписи значков, рамок,
подарков, сундуков и фона главной. Китайский (`zh`) завели первым, отсюда
имя файла; украинский (`uk`) идёт тем же путём.

Тексты каталога лежат в `catalog_items.data` словарями по языкам
(`{"ru": …, "en": …, "de": …}`). Скрипт находит каждый такой словарь без
нужного языка, берёт перевод из `catalog_<язык>.json` по английской строке и
сохраняет запись через API — `updated` сдвигается, и приложение подтянет
каталог заново. Строку без перевода не трогает и называет в отчёте.

Запускать НА VPS рядом с upload_badges.py (API суперюзера снаружи закрыт):
    python3 catalog_add_zh.py                      что изменится, ничего не пишет
    python3 catalog_add_zh.py --commit             записать китайский
    python3 catalog_add_zh.py --lang uk --commit   записать украинский
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, "/opt/pocketbase/tools")
from upload_badges import PB, drop_superuser, send, superuser_token  # noqa: E402


def load_translations(lang: str) -> dict[str, str]:
    path = Path(__file__).parent / f"catalog_{lang}.json"
    return json.loads(path.read_text("utf-8"))


def add_lang(node, lang: str, translations: dict[str, str],
             missing: list[str]) -> int:
    """Дописывает [lang] во все языковые словари внутри [node], отдаёт число правок."""
    changed = 0
    if isinstance(node, dict):
        is_lang = "en" in node and "ru" in node and all(
            isinstance(v, str) for v in node.values())
        if is_lang:
            if lang in node:
                return 0
            text = translations.get(node["en"])
            if text is None:
                missing.append(node["en"])
                return 0
            node[lang] = text
            return 1
        for v in node.values():
            changed += add_lang(v, lang, translations, missing)
    elif isinstance(node, list):
        for v in node:
            changed += add_lang(v, lang, translations, missing)
    return changed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true")
    ap.add_argument("--lang", default="zh")
    args = ap.parse_args()
    translations = load_translations(args.lang)

    email, token = superuser_token()
    try:
        req = urllib.request.Request(
            f"{PB}/api/collections/catalog_items/records?perPage=500",
            headers={"Authorization": token})
        with urllib.request.urlopen(req) as r:
            items = json.load(r)["items"]
        missing: list[str] = []
        total = 0
        for it in items:
            data = it.get("data")
            if isinstance(data, str):
                try:
                    data = json.loads(data or "{}")
                except ValueError:
                    continue
            if not isinstance(data, dict):
                continue
            n = add_lang(data, args.lang, translations, missing)
            if not n:
                continue
            total += n
            print(f"{it['id']}: +{n}")
            if args.commit:
                send("PATCH", f"{PB}/api/collections/catalog_items/records/{it['id']}",
                     token, json.dumps({"data": data}).encode(), "application/json")
        print(f"\nсловарей дополнено: {total}" + ("" if args.commit else " (сухой прогон)"))
        if missing:
            print("без перевода:", sorted(set(missing)))
    finally:
        drop_superuser(email)


if __name__ == "__main__":
    main()
