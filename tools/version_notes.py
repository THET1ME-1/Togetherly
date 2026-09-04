#!/usr/bin/env python3
"""Текст «что нового» для `version.json` — того, что читает самообновление.

Заметки прежних релизов начинались строкой-заголовком («🫦 Togetherly •
v1.27.0»), и попап её показывать не должен. Релизный воркфлоу поэтому срезал
первую строку ВСЕГДА — а заголовков в файлах давно нет, и вместе со строкой
уходил первый абзац: у 1.31.4 люди читали релиз со второго предложения.

Использование: `python3 tools/version_notes.py distribution/whatsnew/whatsnew-ru-RU`
"""

import pathlib
import re
import sys

# Заголовок — короткая строка с именем приложения или номером версии, а не
# предложение о том, что починили.
ЗАГОЛОВОК = re.compile(r"^\W*togetherly\b|^\W*v?\d+\.\d+", re.IGNORECASE)


def notes_body(text: str) -> str:
    lines = (text or "").splitlines()
    if lines and ЗАГОЛОВОК.match(lines[0].strip()):
        lines = lines[1:]
    return "\n".join(lines).strip()


def main() -> None:
    path = pathlib.Path(sys.argv[1])
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    print(notes_body(text))


if __name__ == "__main__":
    main()
