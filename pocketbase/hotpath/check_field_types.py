#!/usr/bin/env python3
"""Сверка типов полей: как отдаёт PocketBase против того, как отдаёт hotpath.

Приложение у людей уже выпущено и читает ответы буквально: где стояло текстовое
поле, там `as String?`. Стоит сервису отдать то же поле объектом — и экран
падает прямо внутри setState, оставляя вечный спиннер. Ровно так 15.08.2026
слегли оба профиля из-за `miss_you.by_weekday`.

Скрипт читает схему коллекций PocketBase и карту COLLECTIONS в hotpath и
показывает поля, где вид ответа разошёлся.

    /opt/hotpath/venv/bin/python check_field_types.py
"""

import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")

# как тип поля PocketBase выглядит в ответе
ВИД = {
    "text": "строка", "editor": "строка", "email": "строка", "url": "строка",
    "date": "строка", "autodate": "строка", "select": "строка",
    "number": "число", "bool": "логическое", "json": "объект",
    "file": "строка", "relation": "список", "password": "строка",
}
ВИД_HOTPATH = {
    "text": "строка", "date": "строка", "auto": "строка",
    "num": "число", "bool": "логическое", "json": "объект",
    "jsontext": "строка",
}


def main() -> None:
    from hotpath import COLLECTIONS  # noqa: E402

    lite = sqlite3.connect(f"file:{SQLITE}?mode=ro", uri=True, timeout=30)
    расхождения = 0
    for имя, мета in COLLECTIONS.items():
        row = lite.execute(
            "SELECT fields FROM _collections WHERE name = ?", (имя,)).fetchone()
        if row is None:
            print(f"{имя}: коллекции в PocketBase нет (это нормально для новых)")
            continue
        схема = {f["name"]: f["type"] for f in json.loads(row[0])}
        for поле, тип in мета["columns"].items():
            было = ВИД.get(схема.get(поле, ""), "")
            стало = ВИД_HOTPATH.get(тип, "?")
            if не_совпало(было, стало):
                расхождения += 1
                print(f"  {имя}.{поле}: PocketBase отдавал {было}, "
                      f"hotpath отдаёт {стало}  (в схеме {схема.get(поле)!r}, "
                      f"в карте {тип!r})")
    lite.close()
    print(f"\nрасхождений: {расхождения}")
    if расхождения:
        print("Каждое — потенциальный вечный спиннер у выпущенной сборки.")


def не_совпало(было: str, стало: str) -> bool:
    if not было:
        return False          # поля нет в схеме — новое, сравнивать не с чем
    return было != стало


if __name__ == "__main__":
    main()
