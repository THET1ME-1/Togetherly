"""Чтение коллекций PocketBase прямо из его SQLite (hotpath, 19.10.2026).

Для коллекций, которые пишут хуки PocketBase, а люди только читают: hotpath
отвечает на чтение своим соединением к той же базе и не стоит в очереди пула
PocketBase. Записи остаются за PocketBase. Ответ собирается по схеме
коллекции (`_collections.fields`), как его собрал бы сам PocketBase.
"""

import json


def load_fields(db, name: str) -> tuple[str, dict]:
    """id коллекции и её поля: имя -> (тип, «много значений»).

    Скрытые поля (`hidden`) PocketBase не отдаёт никому, кроме суперюзера,
    поэтому их тут нет вовсе: `serialize` пропускает всё, чего нет в карте.
    """
    collection_id, raw = db.execute(
        "SELECT id, fields FROM _collections WHERE name = ?", (name,)).fetchone()
    fields = {}
    for f in json.loads(raw):
        if f.get("hidden"):
            continue
        multi = f.get("type") in ("file", "relation", "select") and int(
            f.get("maxSelect") or 1) > 1
        fields[f["name"]] = (f.get("type") or "text", multi)
    return collection_id, fields


def _number(v):
    if v is None or v == "":
        return 0
    v = float(v)
    return int(v) if v.is_integer() else v


def _value(kind: str, multi: bool, v):
    if kind == "number":
        try:
            return _number(v)
        except (TypeError, ValueError):
            return 0
    if kind == "bool":
        # Значение, вписанное руками мимо PocketBase, бывает строкой 'false'.
        if isinstance(v, str):
            return v.strip().lower() in ("1", "true")
        return bool(v)
    if kind == "json":
        if v is None or (isinstance(v, str) and not v.strip()):
            return None
        if not isinstance(v, str):
            return v
        try:
            return json.loads(v)
        except ValueError:
            return v  # битое значение отдаём как есть, а не роняем ответ
    if multi:
        if v is None or v == "":
            return []
        parsed = json.loads(v) if isinstance(v, str) else v
        return parsed if isinstance(parsed, list) else [parsed]
    # Текст, даты, одиночные файл, связь и выбор: у PocketBase всегда строка.
    return "" if v is None else str(v)


def serialize(row, names: list, fields: dict, collection_id: str, name: str) -> dict:
    """Строку SQLite в запись ответа PocketBase."""
    out = {"collectionId": collection_id, "collectionName": name}
    for column, v in zip(names, row):
        if column not in fields:
            continue  # скрытое поле или колонка вне схемы коллекции
        kind, multi = fields[column]
        out[column] = _value(kind, multi, v)
    return out


def build_list(table: str, fields: dict, conds: list, groups: frozenset, sort: str,
               page: int, per_page: int, sortable: set, scope: str = "group",
               uid: str = ""):
    """SELECT и COUNT для списка.

    `conds` — разобранный фильтр: (поле, оператор SQL, значение). При
    `scope="group"` пары человека ставятся всегда, даже когда клиент прислал
    свой `group_id`: забытое условие отдало бы чужие записи. `scope="public"`
    — пустое правило PocketBase (каталог): видно всем. `scope="self"` —
    правило `id = @request.auth.id` (профиль): только своя запись.
    """
    if (scope == "group" and not groups) or (scope == "self" and not uid):
        return ("SELECT * FROM " + table + " WHERE 0", [],
                "SELECT COUNT(*) FROM " + table + " WHERE 0", [])
    where, args = [], []
    for field, op, val in conds:
        kind, _ = fields.get(field, ("text", False))
        if kind == "number" and isinstance(val, str):
            try:
                val = float(val)
            except ValueError:
                pass
        if kind == "bool":
            val = 1 if val in (True, "true") else 0
        if op == "~":
            where.append(f"{field} LIKE ?")
            val = f"%{val}%"
        else:
            where.append(f"{field} {op} ?")
        args.append(val)
    if scope == "group":
        marks = ", ".join("?" for _ in groups)
        where.append(f"group_id IN ({marks})")
        args.extend(sorted(groups))
    elif scope == "self":
        where.append("id = ?")
        args.append(uid)

    keys = []
    for k in (sort or "").split(","):
        k = k.strip()
        name = k.lstrip("+-")
        if name in sortable:
            keys.append(f"{name} {'DESC' if k.startswith('-') else 'ASC'}")
    # Сортировка ровно та, что просили: без `sort` PocketBase отдаёт записи в
    # естественном порядке базы, своя добавка разошлась бы с ним на первой же
    # странице («число подарков» с perPage=1).
    order = f" ORDER BY {', '.join(keys)}" if keys else ""
    where_sql = " AND ".join(where) or "1"
    sql = (f"SELECT * FROM {table} WHERE {where_sql}{order} "
           f"LIMIT {int(per_page)} OFFSET {(int(page) - 1) * int(per_page)}")
    return sql, args, f"SELECT COUNT(*) FROM {table} WHERE {where_sql}", list(args)
