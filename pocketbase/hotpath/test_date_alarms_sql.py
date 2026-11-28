# -*- coding: utf-8 -*-
"""Пересчёт будильников дат не стирает созревшие: на сервере, с Postgres.

    set -a; . /opt/hotpath/env; set +a
    /opt/hotpath/venv/bin/python test_date_alarms_sql.py

Пересчёт идёт при каждом запуске hotpath. До 28.11.2026 он удалял все
будильники даты и ставил только будущие — напоминание, созревшее в минуту
перезапуска, пропадало неотправленным. Проверка гоняет те же строки SQL из
hotpath.py во временной таблице сессии: боевые данные не трогаются.
"""
import asyncio
import os
from datetime import datetime, timedelta, timezone

import asyncpg

источник = open(os.path.join(os.path.dirname(__file__), "hotpath.py"), encoding="utf-8").read()
начало = источник.index("ДАТЫ_СНЯТЬ_БУДУЩИЕ = (")
конец = источник.index("\n\n\n", начало)
пространство: dict = {}
exec(источник[начало:конец], пространство)
СНЯТЬ = пространство["ДАТЫ_СНЯТЬ_БУДУЩИЕ"]
ПОСТАВИТЬ = пространство["ДАТЫ_ПОСТАВИТЬ"]


async def main() -> int:
    c = await asyncpg.connect(os.environ["HOTPATH_PG_DSN"])
    ошибок = 0
    try:
        # Временная таблица сессии заслоняет боевую с тем же именем.
        await c.execute(
            "CREATE TEMP TABLE date_alarms (id bigserial PRIMARY KEY, kind text NOT NULL, "
            "ref_id text NOT NULL, group_id text NOT NULL DEFAULT '', uid text NOT NULL, "
            "minutes integer NOT NULL DEFAULT 0, occ text NOT NULL DEFAULT '', "
            "fire_at timestamptz NOT NULL, UNIQUE (kind, ref_id, uid, minutes))")
        сейчас = datetime.now(timezone.utc)
        await c.execute(
            "INSERT INTO date_alarms (kind, ref_id, uid, minutes, occ, fire_at) VALUES "
            "('pair_date', 'd', 'созрел', 900, '2026-11-28', $1), "
            "('pair_date', 'd', 'будущий', 900, '2026-12-01', $2)",
            сейчас - timedelta(seconds=30), сейчас + timedelta(days=3))

        # Пересчёт: оба получают «следующий» будильник через неделю.
        следующий = сейчас + timedelta(days=7)
        async with c.transaction():
            await c.execute(СНЯТЬ, "d")
            await c.executemany(ПОСТАВИТЬ, [
                ("d", "g", "созрел", 900, "2026-12-05", следующий),
                ("d", "g", "будущий", 900, "2026-12-05", следующий),
            ])
        строки = {r["uid"]: r for r in await c.fetch("SELECT * FROM date_alarms")}

        def проверка(имя: str, ок: bool) -> None:
            nonlocal ошибок
            print(("ОК   " if ок else "ПЛОХО") + " " + имя)
            ошибок += 0 if ок else 1

        проверка("созревший пережил пересчёт и ждёт рассылки",
                 строки["созрел"]["occ"] == "2026-11-28" and строки["созрел"]["fire_at"] < сейчас)
        проверка("будущий заменён свежим",
                 строки["будущий"]["occ"] == "2026-12-05")
        проверка("копий нет", len(строки) == 2)
    finally:
        await c.close()
    print(f"итог: провалов {ошибок}")
    return ошибок


if __name__ == "__main__":
    raise SystemExit(1 if asyncio.run(main()) else 0)
