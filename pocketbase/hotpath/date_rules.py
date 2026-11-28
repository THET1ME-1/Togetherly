# -*- coding: utf-8 -*-
"""Даты пары: повтор, когда напомнить и что написать в напоминании.

Чистые функции без базы и сети — их зовёт hotpath (`_даты_*`), а проверяет
`test_date_rules.py`. Повтор раскладывает dateutil: правило — тело RRULE из
RFC 5545 (`FREQ=YEARLY`, `FREQ=WEEKLY;BYDAY=WE,SU;UNTIL=20261215`), счёт
идёт в днях от полуночи дня начала. Время дня у даты со временем
прибавляется уже к готовому дню в поясе автора даты.

Напоминание — число минут до начала. У даты на весь день начало — полночь
человека, и минуты читаются по часам на стене: 900 — «за день в 9:00»,
−540 — «в этот день в 9:00», 9540 — «за неделю в 9:00». Так «в 9:00» остаётся
девятью утра и в неделю перехода на зимнее время. У даты со временем минуты —
просто промежуток до начала.
"""
from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta, timezone, tzinfo
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dateutil.rrule import rrulestr

from push_texts import пуш

# Какие правила мы понимаем. Остальное (почасовые, посекундные, BYMONTH)
# приложение завести не может, а чужое — дата без повтора, но не падение.
ЧАСТОТЫ = {"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}
КЛЮЧИ = {"FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "UNTIL", "COUNT", "WKST"}

# Сколько повторов перебирать в поисках ближайшего напоминания. Раз в день
# на сто лет вперёд — это 36 тысяч, но «ближайшее» находится на первых шагах;
# предел нужен только против правила, которое не даёт ни одного дня.
ПРЕДЕЛ_ПЕРЕБОРА = 4000

ПОЯС_ПО_УМОЛЧАНИЮ = "Europe/Moscow"

_СМЕЩЕНИЕ = re.compile(r"^([+-])(\d{2}):(\d{2})$")


def день(строка: str) -> date | None:
    try:
        return date.fromisoformat((строка or "")[:10])
    except ValueError:
        return None


def правило(текст: str, начало: date):
    """Разобранное правило или None (нет повтора, незнакомое, сломанное)."""
    текст = (текст or "").strip()
    if not текст:
        return None
    if текст.upper().startswith("RRULE:"):
        текст = текст[6:]
    части = dict(
        часть.split("=", 1) for часть in текст.upper().split(";") if "=" in часть
    )
    if части.get("FREQ") not in ЧАСТОТЫ or not set(части) <= КЛЮЧИ:
        return None
    try:
        return rrulestr(текст, dtstart=datetime.combine(начало, time()))
    except (ValueError, TypeError):
        return None


def повторы(начало_день: str, текст_правила: str, выброшены, с: date, по: date) -> list[date]:
    """Дни даты в окне [с, по] включительно, без выброшенных."""
    начало = день(начало_день)
    if начало is None:
        return []
    лишние = set(выброшены or [])
    r = правило(текст_правила, начало)
    if r is None:
        дни = [начало] if с <= начало <= по else []
    else:
        дни = [d.date() for d in r.between(datetime.combine(с, time()),
                                           datetime.combine(по, time()), inc=True)]
    return [d for d in дни if d.isoformat() not in лишние]


def _повторы_с(запись: dict, с: date):
    """Дни даты начиная с [с], по порядку, без выброшенных."""
    начало = день(запись.get("day") or "")
    if начало is None:
        return
    лишние = set(запись.get("exdates") or [])
    r = правило(запись.get("rrule") or "", начало)
    if r is None:
        if начало >= с and начало.isoformat() not in лишние:
            yield начало
        return
    for i, d in enumerate(r.xafter(datetime.combine(с, time()), inc=True)):
        if i >= ПРЕДЕЛ_ПЕРЕБОРА:
            return
        if d.date().isoformat() not in лишние:
            yield d.date()


def пояс(имя: str | None) -> tzinfo | None:
    """IANA-пояс (`Europe/Kyiv`) или смещение (`+03:00`); мусор — None."""
    имя = (имя or "").strip()
    if not имя:
        return None
    совпало = _СМЕЩЕНИЕ.match(имя)
    if совпало:
        знак = -1 if совпало.group(1) == "-" else 1
        return timezone(знак * timedelta(hours=int(совпало.group(2)),
                                          minutes=int(совпало.group(3))))
    try:
        return ZoneInfo(имя)
    except (ZoneInfoNotFoundError, ValueError):
        return None


def пояс_человека(данные_виджета, запасной: str | None) -> tzinfo:
    """Пояс человека из его записи виджета: имя, потом смещение, потом запасной."""
    данные = данные_виджета if isinstance(данные_виджета, dict) else {}
    return (пояс(данные.get("tzn")) or пояс(данные.get("tz")) or пояс(запасной)
            or ZoneInfo(ПОЯС_ПО_УМОЛЧАНИЮ))


def _время(запись: dict) -> time | None:
    """Время дня у даты со временем, None у даты на весь день."""
    текст = (запись.get("start_time") or "").strip()
    try:
        часы, минуты = текст.split(":")
        return time(int(часы), int(минуты))
    except ValueError:
        return None


def по_стене(минуты: int) -> tuple[int, int]:
    """Минуты до полуночи → (за сколько дней, минута дня по часам на стене)."""
    if минуты <= 0:
        return 0, min(-минуты, 1439)
    дней = -(-минуты // 1440)
    return дней, дней * 1440 - минуты


def начало_повтора(запись: dict, повтор: date, пояс_ч: tzinfo) -> datetime:
    """Когда начинается этот повтор, в UTC."""
    в_день = _время(запись)
    if в_день is None:
        местное = datetime.combine(повтор, time(), tzinfo=пояс_ч)
    else:
        пояс_даты = пояс(запись.get("tz")) or пояс_ч
        местное = datetime.combine(повтор, в_день, tzinfo=пояс_даты)
    return местное.astimezone(timezone.utc)


def когда_напомнить(запись: dict, минуты: int, повтор: date, пояс_ч: tzinfo) -> datetime:
    """Момент напоминания за [минуты] до этого повтора, в UTC."""
    if _время(запись) is None:
        # Часы на стене: перевод времени между днями не двигает «9:00».
        дней, минута_дня = по_стене(минуты)
        стена = datetime.combine(повтор - timedelta(days=дней),
                                 time(минута_дня // 60, минута_дня % 60), tzinfo=пояс_ч)
        return стена.astimezone(timezone.utc)
    return начало_повтора(запись, повтор, пояс_ч) - timedelta(minutes=минуты)


def следующее(запись: dict, минуты: int, пояс_ч: tzinfo, сейчас: datetime) -> tuple[datetime, date] | None:
    """Ближайшее напоминание позже [сейчас]: (момент в UTC, день повтора)."""
    сегодня = сейчас.astimezone(пояс_ч).date()
    # Напоминание бывает и после начала («в этот день в 9:00»), и до него на
    # дни и недели — ищем от вчерашнего дня, лишнее отсеет сравнение.
    for повтор in _повторы_с(запись, сегодня - timedelta(days=1)):
        момент = когда_напомнить(запись, минуты, повтор, пояс_ч)
        if момент > сейчас:
            return момент, повтор
    return None


def _форма(n: int, язык: str) -> str:
    """Форма числа: one, few, many (few бывает только у ru и uk)."""
    if язык in ("ru", "uk"):
        хвост = n % 100
        if 11 <= хвост <= 14:
            return "many"
        if n % 10 == 1:
            return "one"
        if 2 <= n % 10 <= 4:
            return "few"
        return "many"
    return "one" if n == 1 else "many"


def _сколько_дней(n: int, язык: str) -> str:
    """«Через 3 дня» с верной формой числа."""
    return пуш("date_in_days_" + _форма(n, язык), язык, n=str(n))


def _сколько_минут(n: int, язык: str) -> str:
    """«Через 30 минут» или ровные часы: «Через 2 часа»."""
    if n >= 60 and n % 60 == 0:
        часов = n // 60
        return пуш("date_in_hours_" + _форма(часов, язык), язык, n=str(часов))
    return пуш("date_in_minutes_" + _форма(n, язык), язык, n=str(n))


def текст_напоминания(запись: dict, повтор: date, пояс_ч: tzinfo, язык: str,
                      сейчас: datetime) -> tuple[str, str]:
    """Заголовок и текст пуша-напоминания на языке получателя."""
    заголовок = (запись.get("title") or "").strip() or пуш("date_untitled", язык)
    сегодня = сейчас.astimezone(пояс_ч).date()
    if _время(запись) is None:
        осталось = (повтор - сегодня).days
        if осталось <= 0:
            return заголовок, пуш("date_today", язык)
        if осталось == 1:
            return заголовок, пуш("date_tomorrow", язык)
        return заголовок, _сколько_дней(осталось, язык)

    начало = начало_повтора(запись, повтор, пояс_ч)
    местное = начало.astimezone(пояс_ч)
    часы = местное.strftime("%H:%M")
    до = начало - сейчас
    if до <= timedelta(minutes=1):
        return заголовок, пуш("date_now", язык)
    # Близко — промежутком («Через 30 минут», «Через 2 часа»), дальше — часами
    # на стене: «Сегодня в 19:00» понятнее, чем «Через 10 часов».
    if до < timedelta(hours=1) or (до <= timedelta(hours=3) and до.total_seconds() % 3600 == 0):
        return заголовок, _сколько_минут(round(до.total_seconds() / 60), язык)
    дней = (местное.date() - сегодня).days
    if дней <= 0:
        return заголовок, пуш("date_today_at", язык, time=часы)
    if дней == 1:
        return заголовок, пуш("date_tomorrow_at", язык, time=часы)
    return заголовок, пуш("date_in_days_at", язык, days=_сколько_дней(дней, язык), time=часы)
