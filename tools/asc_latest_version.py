#!/usr/bin/env python3
"""Самая свежая версия приложения в App Store Connect — по её id.

Нужна затем, чтобы спросить у Apple, какие страницы («что нового», описание,
ключевые слова) у версии вообще заведены: `whatsNew` обязателен КАЖДОЙ из них,
и пустая английская валит заявку целиком.

Сортировать на стороне Apple нельзя: `GET /v1/apps/{id}/appStoreVersions`
отвечает «The parameter 'sort' can not be used with this request», а порядок в
ответе не обещан. Поэтому список читается целиком и сортируется здесь.

Использование: `app-store-connect apps app-store-versions <id> --json |
python3 tools/asc_latest_version.py`
"""

import datetime
import json
import sys


def момент(created: str):
    """Дата создания версии как момент времени, а не как строка.

    Смещение приезжает и как `-07:00`, и как `Z`, поэтому посимвольное
    сравнение врёт: «03:15-07:00» выглядит старше «09:00Z», хотя случилось
    позже.
    """
    created = (created or "").strip()
    if not created:
        return None
    try:
        stamp = datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=datetime.timezone.utc)
    return stamp


def latest_id(data) -> str:
    if isinstance(data, dict):
        data = [data]
    newest = ""
    newest_at = None
    for item in data or []:
        stamp = момент((item.get("attributes") or {}).get("createdDate"))
        if stamp is None or (newest_at is not None and stamp <= newest_at):
            continue
        newest_at = stamp
        newest = item.get("id", "")
    return newest


def main() -> None:
    print(latest_id(json.load(sys.stdin)))


if __name__ == "__main__":
    main()
