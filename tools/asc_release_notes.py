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
import re
import sys
import unicodedata

# Путь считаем от самого файла: скрипт зовут и из корня (релизный прогон), и
# из каталога tools (тесты).
NOTES_DIR = pathlib.Path(__file__).resolve().parent.parent / "distribution" / "whatsnew"


def strip_unsupported(text: str) -> str:
    """Убирает символы, которых App Store Connect не принимает.

    Эмодзи в «Что нового» Apple отвергает целиком: заявка 1.26.0 упала со
    словами «What's New in This Version can’t contain the following
    character(s): 🫦». Тире, кавычки и типографику оставляем — их принимает.
    """
    kept = []
    for ch in text:
        if ch in "\n\t":
            kept.append(ch)
            continue
        # Категория So — «прочие символы»: эмодзи, пиктограммы, значки.
        if unicodedata.category(ch) in ("So", "Cs"):
            continue
        # Модификаторы тона кожи, «склейка» составных эмодзи и вариативные
        # селекторы сами по себе печатного следа не оставляют.
        if 0x1F3FB <= ord(ch) <= 0x1F3FF or ord(ch) in (0x200D, 0xFE0F, 0xFE0E):
            continue
        kept.append(ch)

    cleaned = "".join(kept)
    # После вырезанного символа остаются двойные пробелы и пустые строки в
    # начале — Apple их примет, но человек увидит дыру.
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned)
    lines = [line.strip() for line in cleaned.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def notes_for(locale: str) -> str:
    candidates = [locale, locale.split("-")[0], "en-US", "en"]
    for name in candidates:
        for path in sorted(NOTES_DIR.glob(f"whatsnew-{name}*")):
            text = strip_unsupported(path.read_text(encoding="utf-8"))
            if text:
                return text
    raise SystemExit(f"нет заметок ни для {locale}, ни для английского")


def build_localizations(primary: str) -> list:
    """Заметки для заявки — только для основной локали приложения.

    Заводить новую локаль нельзя: у неё Apple тут же требует описание,
    ключевые слова и адрес поддержки, а без них версия становится невалидной
    («You must provide a value for the attribute description»). Ровно так
    сорвалась третья попытка отправить 1.26.0, когда рядом с русской завелась
    пустая английская страница. Основная локаль уже заполнена целиком, и
    трогать её безопасно.
    """
    locale = (primary or "en-US").strip()
    return [{"locale": locale, "whats_new": notes_for(locale)}]


def main() -> None:
    primary = sys.argv[1] if len(sys.argv) > 1 else "en-US"
    json.dump(build_localizations(primary), sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
