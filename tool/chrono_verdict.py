#!/usr/bin/env python3
"""Честный приговор: сколько НАШИХ виджетов система реально зарегистрировала.

Зачем. Прошлый приговор в `ios-widget-registry.yml` считал две вещи, и обе
мимо:

* «аварийные завершения» — `grep -ciE "SIGTRAP|...|exited with context"` по
  системному журналу. Строка «exited with context» пишется и при НОРМАЛЬНОМ
  завершении расширения, поэтому счётчик краснел всегда — и у рабочей 1.25.0,
  и у сломанной. На этом основании стенд объявили негодным;
* «строки про Togetherly в базе chronod» — `grep -ci togetherly` по дампу
  таблиц. Но `kind` наших виджетов — `LoveWidgetProvider`, `MoodWidgetProvider`
  и так далее: слова «togetherly» в них нет вовсе. Считались случайные
  совпадения по идентификатору бандла.

Здесь считается ровно то, что видит человек в галерее: список `kind`, которые
chronod знает от нашего расширения, против списка `kind`, объявленных в
исходниках. «7 из 22» и «22 из 22» — это разные приговоры, а прошлый счётчик
их не различал.

Запуск:
    python3 tool/chrono_verdict.py <путь к data симулятора> [журнал.txt]
"""

import plistlib
import re
import sqlite3
import sys
from pathlib import Path

def _widgets_dir() -> Path:
    """Папка расширения: рядом со скриптом или в текущем каталоге.

    Проверка на симуляторе копирует разборщики в /tmp (в старом коммите их нет),
    и путь «рядом со скриптом» тогда указывает в пустоту: приговор напечатал
    «объявлено в исходниках: 0» и сравнивать стало нечего.
    """
    for root in (Path(__file__).resolve().parent.parent, Path.cwd()):
        candidate = root / "ios" / "TogetherlyWidget"
        if candidate.is_dir():
            return candidate
    raise SystemExit("не нашёл ios/TogetherlyWidget ни рядом со скриптом, ни в текущем каталоге")


WIDGETS = _widgets_dir()
KIND_RE = re.compile(r'kind:\s*"([^"]+)"')
LOG_KIND_RE = re.compile(r"kind:\s*([A-Za-z0-9._]+)")


def declared_kinds() -> set[str]:
    """Что объявлено в исходниках расширения."""
    kinds: set[str] = set()
    for swift in sorted(WIDGETS.glob("*.swift")):
        kinds |= set(KIND_RE.findall(swift.read_text(encoding="utf-8")))
    return kinds


def _strings(obj) -> list[str]:
    """Все строки внутри разобранного plist, на любой глубине."""
    if isinstance(obj, str):
        return [obj]
    if isinstance(obj, dict):
        out = []
        for k, v in obj.items():
            out.append(str(k))
            out += _strings(v)
        return out
    if isinstance(obj, (list, tuple)):
        out = []
        for v in obj:
            out += _strings(v)
        return out
    return []


def kinds_in_db(data_dir: Path) -> set[str]:
    """Что лежит в базе chronod: дескрипторы разбираются из вложенных bplist."""
    db = data_dir / "Library" / "chronod" / "chrono.sql"
    if not db.exists():
        return set()
    found: set[str] = set()
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.text_factory = bytes
    try:
        tables = [
            r[0].decode("utf-8", "replace")
            for r in con.execute(
                "select name from sqlite_master where type='table'"
            ).fetchall()
        ]
        for table in tables:
            try:
                rows = con.execute(f'select * from "{table}"').fetchall()
            except sqlite3.DatabaseError:
                continue
            for row in rows:
                for cell in row:
                    if not isinstance(cell, (bytes, bytearray)):
                        continue
                    start = cell.find(b"bplist00")
                    if start < 0:
                        continue
                    try:
                        plist = plistlib.loads(bytes(cell[start:]))
                    except Exception:
                        continue
                    found |= set(_strings(plist))
    finally:
        con.close()
    return found


def kinds_in_log(log: Path) -> set[str]:
    """Что chronod проговорил вслух: `<CHSWidgetDescriptor: … kind: X …>`."""
    if not log.exists():
        return set()
    text = log.read_text(encoding="utf-8", errors="replace")
    return set(LOG_KIND_RE.findall(text))


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    data_dir = Path(sys.argv[1])
    log = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/nonexistent")

    declared = declared_kinds()
    seen = (kinds_in_db(data_dir) | kinds_in_log(log)) & declared
    missing = sorted(declared - seen)

    print("=" * 62)
    print("ПРИГОВОР: сколько наших виджетов знает система")
    print("=" * 62)
    print(f"объявлено в исходниках: {len(declared)}")
    print(f"система знает:          {len(seen)}")
    print()
    if seen:
        print("дошли:")
        for k in sorted(seen):
            print(f"  ✓ {k}")
    if missing:
        print("НЕ дошли:")
        for k in missing:
            print(f"  ✗ {k}")
    print()
    if not seen:
        print("НИ ОДНОГО виджета система не увидела — галерея пуста.")
    elif missing:
        print(f"Дошла часть: {len(seen)} из {len(declared)}.")
    else:
        print("Все виджеты на месте.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
