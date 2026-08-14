#!/usr/bin/env python3
"""Догнать «Скучаю», записанное в SQLite между переносом и переключением.

Пока Caddy ещё вёл запросы в PocketBase, нажатия продолжали ложиться в SQLite.
Берём оттуда счётчик и поднимаем в Postgres, если там меньше: после
переключения новые нажатия идут уже в Postgres, и затирать их нельзя.
"""
import asyncio, os, sqlite3
import asyncpg

SQLITE = os.environ.get("PB_DB", "/opt/pocketbase/pb_data/data.db")
PG_DSN = os.environ["HOTPATH_PG_DSN"]


async def main() -> None:
    lite = sqlite3.connect("file:%s?mode=ro" % SQLITE, uri=True, timeout=30)
    rows = lite.execute(
        "SELECT group_id, user_uid, count, by_weekday, by_vibe, updated_at,"
        " last_vibe, last_vibe_text FROM miss_you"
    ).fetchall()
    lite.close()
    pg = await asyncpg.connect(PG_DSN)
    raised = 0
    for gid, uid, cnt, week, vibes, upd, lv, lvt in rows:
        try:
            n = float(cnt or 0)
        except (TypeError, ValueError):
            continue
        res = await pg.execute(
            """
            UPDATE miss_you SET
                count = $3::double precision,
                by_weekday = COALESCE(NULLIF($4, '')::jsonb, by_weekday),
                by_vibe = COALESCE(NULLIF($5, '')::jsonb, by_vibe),
                updated_at = COALESCE(NULLIF($6, ''), updated_at),
                last_vibe = COALESCE(NULLIF($7, ''), last_vibe),
                last_vibe_text = COALESCE(NULLIF($8, ''), last_vibe_text)
            WHERE group_id = $1 AND user_uid = $2 AND count < $3::double precision
            """,
            gid or "", uid or "", n, week or "", vibes or "", upd or "", lv or "", lvt or "",
        )
        if res.endswith("1"):
            raised += 1
    await pg.close()
    print("сверено строк: %d, подняли счётчик: %d" % (len(rows), raised))


if __name__ == "__main__":
    asyncio.run(main())
