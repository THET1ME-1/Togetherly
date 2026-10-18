#!/usr/bin/env python3
"""Чтение подарков hotpath'ом прямо из SQLite PocketBase (19.10.2026).

Подарки пишут хуки PocketBase, а читает приложение по 9 раз в секунду, и под
наплывом эти чтения стояли в очереди пула PocketBase. Копия в Postgres тут не
годится: приложение перечитывает подарки сразу после события в канале пары,
и копия с задержкой не показала бы только что пришедший подарок. Поэтому
hotpath читает ту же SQLite, своим соединением.

Проверяется, что ответ собирается как у PocketBase (числа, строки, json,
список файлов) и что запрос не выходит за пары человека.

    python3 test_sqlite_read.py
"""

import json
import sqlite3

from sqlite_read import build_list, load_fields, serialize

провалы = []


def проверить(имя, ok, подробно=""):
    print(("ОК   " if ok else "ПЛОХО") + f" {имя} {'' if ok else подробно}")
    if not ok:
        провалы.append(имя)


db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE _collections (id TEXT, name TEXT, fields TEXT)")
db.execute("INSERT INTO _collections VALUES (?, ?, ?)", ("pbc_1", "gifts", json.dumps([
    {"name": "id", "type": "text"}, {"name": "group_id", "type": "text"},
    {"name": "recipient_uid", "type": "text"}, {"name": "price", "type": "number"},
    {"name": "deliver_at", "type": "number"}, {"name": "state", "type": "text"},
    {"name": "meta", "type": "json"}, {"name": "seen", "type": "bool"},
    {"name": "files", "type": "file", "maxSelect": 5},
    {"name": "cover", "type": "file", "maxSelect": 1},
    {"name": "created", "type": "autodate"},
    {"name": "secret", "type": "text", "hidden": True},
])))
db.execute("CREATE TABLE gifts (id TEXT, group_id TEXT, recipient_uid TEXT, price NUMERIC, "
           "deliver_at NUMERIC, state TEXT, meta JSON, seen BOOLEAN, files JSON, cover TEXT, "
           "created TEXT, secret TEXT)")
rows = [
    ("g1", "pairA", "u1", 30, 1000, "sent", '{"k": 1}', 1, '["a.webp","b.webp"]', "c.webp",
     "2026-10-18 10:00:00.000Z", "s1"),
    ("g2", "pairA", "u1", 12.5, 5000, "reacted", "", 0, "[]", "", "2026-10-18 11:00:00.000Z",
     "s2"),
    ("g3", "pairB", "u1", 10, 1000, "sent", None, None, None, None, "2026-10-18 12:00:00.000Z",
     None),
]
db.executemany("INSERT INTO gifts VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", rows)

collection_id, fields = load_fields(db, "gifts")
проверить("поля берутся из схемы коллекции", collection_id == "pbc_1"
          and fields["files"] == ("file", True) and fields["cover"] == ("file", False),
          str(fields))

rec = serialize(db.execute("SELECT * FROM gifts WHERE id='g1'").fetchone(),
                [d[0] for d in db.execute("SELECT * FROM gifts LIMIT 0").description],
                fields, collection_id, "gifts")
проверить("скрытое поле не отдаётся", "secret" not in rec, json.dumps(rec))
проверить("запись как у PocketBase", rec == {
    "id": "g1", "collectionId": "pbc_1", "collectionName": "gifts",
    "group_id": "pairA", "recipient_uid": "u1", "price": 30, "deliver_at": 1000,
    "state": "sent", "meta": {"k": 1}, "seen": True, "files": ["a.webp", "b.webp"],
    "cover": "c.webp", "created": "2026-10-18 10:00:00.000Z"}, json.dumps(rec))

rec = serialize(db.execute("SELECT * FROM gifts WHERE id='g3'").fetchone(),
                [d[0] for d in db.execute("SELECT * FROM gifts LIMIT 0").description],
                fields, collection_id, "gifts")
проверить("пустые значения как у PocketBase", rec["meta"] is None and rec["seen"] is False
          and rec["files"] == [] and rec["cover"] == "", json.dumps(rec))

rec = serialize(db.execute("SELECT * FROM gifts WHERE id='g2'").fetchone(),
                [d[0] for d in db.execute("SELECT * FROM gifts LIMIT 0").description],
                fields, collection_id, "gifts")
проверить("дробное число остаётся дробным, пустой json — null",
          rec["price"] == 12.5 and rec["meta"] is None, json.dumps(rec))


def run(conds, groups, sort="-created", page=1, per_page=30, scope="group"):
    sql, args, count_sql, count_args = build_list(
        "gifts", fields, conds, groups, sort, page, per_page,
        sortable={"created", "id"}, scope=scope)
    got = [r[0] for r in db.execute(sql, args).fetchall()]
    total = db.execute(count_sql, count_args).fetchone()[0]
    return got, total


got, total = run([], frozenset(), scope="public")
проверить("общедоступная коллекция видна и без пары", got == ["g3", "g2", "g1"] and total == 3,
          f"{got} {total}")


got, total = run([("recipient_uid", "=", "u1")], frozenset({"pairA"}))
проверить("чужая пара не попадает в выдачу", got == ["g2", "g1"] and total == 2,
          f"{got} {total}")
got, _ = run([("group_id", "=", "pairA"), ("recipient_uid", "=", "u1"), ("state", "=", "sent"),
              ("deliver_at", "<=", 2000.0)], frozenset({"pairA", "pairB"}))
проверить("фильтр входящих подарков", got == ["g1"], str(got))
got, total = run([], frozenset())
проверить("человек без пары не видит ничего", got == [] and total == 0, f"{got} {total}")
got, _ = run([("recipient_uid", "=", "u1")], frozenset({"pairA", "pairB"}), sort="created",
             per_page=1, page=2)
проверить("страницы и сортировка", got == ["g2"], str(got))
got, _ = run([("state", "<>", "sent")], frozenset({"pairA", "pairB"}))
проверить("неравенство", got == ["g2"], str(got))

print(f"итог: провалов {len(провалы)}" + (f" — {провалы}" if провалы else ""))
raise SystemExit(1 if провалы else 0)
