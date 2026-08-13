#!/usr/bin/env python3
"""Заметки «Что нового» для заявки в App Store, JSON-списком по локалям.

Apple отвергает заявку, если у ОСНОВНОЙ локали приложения нет `whatsNew`:
«You must provide a value for the attribute whatsNew» — на этом свалилась
первая автоматическая отправка 1.26.0, где текст был только для `ru`. Поэтому
основную локаль спрашиваем у App Store Connect и заполняем её всегда.

Тексты лежат в `distribution/whatsnew/whatsnew-<локаль>`; если файла для
локали нет, берём язык без региона, а в последнюю очередь — английский.

Использование: `python3 tools/asc_release_notes.py en-US > localizations.json`
"""

import json
import pathlib
import sys

NOTES_DIR = pathlib.Path("distribution/whatsnew")


def notes_for(locale: str) -> str:
    candidates = [locale, locale.split("-")[0], "en-US", "en"]
    for name in candidates:
        for path in sorted(NOTES_DIR.glob(f"whatsnew-{name}*")):
            text = path.read_text(encoding="utf-8").strip()
            if text:
                return text
    raise SystemExit(f"нет заметок ни для {locale}, ни для английского")


def main() -> None:
    primary = (sys.argv[1] if len(sys.argv) > 1 else "en-US").strip()
    # Порядок важен только для читаемости: dict.fromkeys снимает повторы,
    # когда основная локаль совпала с русской или английской.
    locales = list(dict.fromkeys([primary, "ru", "en-US"]))
    payload = [
        {"locale": locale, "whats_new": notes_for(locale)} for locale in locales
    ]
    json.dump(payload, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
