#!/usr/bin/env python3
"""Локализации версии App Store, которые нельзя отправить на ревью.

Страница, где заполнено только «Что нового», делает всю версию невалидной:
Apple требует у неё ещё описание и ключевые слова («You must provide a value
for the attribute description»). Такие страницы заводила ранняя версия
автоматической отправки — их надо снести, иначе заявка не создастся.

Читает JSON списка локализаций из stdin, печатает по строке «id локаль».
"""

import json
import sys


def incomplete(localizations: list) -> list:
    out = []
    for loc in localizations:
        attrs = loc.get("attributes") or {}
        description = (attrs.get("description") or "").strip()
        keywords = (attrs.get("keywords") or "").strip()
        if description and keywords:
            continue
        out.append((loc.get("id", ""), attrs.get("locale", "?")))
    return out


def main() -> None:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        data = [data]
    for loc_id, locale in incomplete(data):
        if loc_id:
            print(loc_id, locale)


if __name__ == "__main__":
    main()
