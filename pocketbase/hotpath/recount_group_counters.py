#!/usr/bin/env python3
"""Пересчёт счётчиков пары по фактическим записям в Postgres.

Счётчики `messages_count` и `memories_count` пара показывает в профиле, по ним
же считаются достижения. Копировать их между базами бессмысленно — вернее
посчитать по самим записям, тем более что и сообщения, и воспоминания лежат
здесь же.

Заодно закрывает историческое расхождение: пока цифру вёл клиент отдельной
операцией очереди, она расходилась у каждой четвёртой пары.

    /opt/hotpath/venv/bin/python recount_group_counters.py            # показать
    /opt/hotpath/venv/bin/python recount_group_counters.py --commit   # записать
"""

import argparse
import asyncio
import os

import asyncpg

PG_DSN = os.environ["HOTPATH_PG_DSN"]

СЧЁТЧИКИ = {
    "messages_count": "SELECT count(*) FROM chat_messages m "
                      "WHERE m.group_id = g.id AND NOT m.deleted",
    "memories_count": "SELECT count(*) FROM memories m "
                      "WHERE m.group_id = g.id AND NOT m.deleted",
}


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true")
    args = ap.parse_args()

    pg = await asyncpg.connect(PG_DSN)
    try:
        for поле, подсчёт in СЧЁТЧИКИ.items():
            разошлось = await pg.fetchval(
                f"SELECT count(*) FROM groups g WHERE g.{поле} <> ({подсчёт})")
            print(f"{поле}: расходится у {разошлось} пар")
            if args.commit and разошлось:
                # updated двигаем намеренно: по нему зеркало донесёт новую цифру до
                # SQLite, откуда её читают отчёты админки.
                await pg.execute(
                    f"UPDATE groups g SET {поле} = ({подсчёт}), "
                    "updated = to_char(now() at time zone 'utc', "
                    "'YYYY-MM-DD HH24:MI:SS.MS') || 'Z' "
                    f"WHERE g.{поле} <> ({подсчёт})")
                осталось = await pg.fetchval(
                    f"SELECT count(*) FROM groups g WHERE g.{поле} <> ({подсчёт})")
                print(f"  пересчитано, осталось расхождений: {осталось}")
        if not args.commit:
            print("(прогон без --commit, ничего не записано)")
    finally:
        await pg.close()


if __name__ == "__main__":
    asyncio.run(main())
