# -*- coding: utf-8 -*-
"""Запись не уходит в чужую пару и не меняет автора:
python3 pocketbase/hotpath/test_record_move_guard.py

До 10.11.2026 правка принимала любой `group_id` и любого автора, а чат,
настроения и «Скучаю» создавались от чужого имени: при переезде из PocketBase
в hotpath потерялась проверка `user_uid = @request.auth.id`. Список «кто в
сети» читал любой вошедший. Живая проверка — pocketbase/record_guard.test.py.
"""
import ast
import os

источник = open(os.path.join(os.path.dirname(__file__), "hotpath.py"), encoding="utf-8").read()
кусок = источник[источник.index("def поле_автора"):источник.index("# Типы колонок")]
мир: dict = {}
exec(кусок, мир)
поле_автора = мир["поле_автора"]
запрет = мир["переезд_запрещён"]
свои = мир["свои_люди_sql"]

коллекции = {}
for узел in ast.walk(ast.parse(источник)):
    if isinstance(узел, ast.Assign) and any(getattr(t, "id", "") == "COLLECTIONS" for t in узел.targets):
        for k, v in zip(узел.value.keys, узел.value.values):
            поля = {}
            for kk, vv in zip(v.keys, v.values):
                имя = getattr(kk, "value", "")
                if имя in ("columns", "create_owner_field", "scope"):
                    try:
                        поля[имя] = ast.literal_eval(vv)
                    except ValueError:
                        pass
            коллекции[k.value] = поля

ok = True


def check(имя, условие):
    global ok
    print(("  ✓ " if условие else "  ✗ ") + имя)
    if not условие:
        ok = False


МОИ = frozenset({"g1", "g2"})

print("создание: автор — только сам")
for имя in ("chat_messages", "mood_entries", "miss_you", "widget_data", "chat_reads",
            "chat_typing", "cycle_entries", "love_tests", "user_presence", "live_location"):
    check(f"{имя}: автор сверяется по user_uid",
          коллекции[имя].get("create_owner_field") == "user_uid")
for имя in ("memories", "wishes", "wish_categories"):
    check(f"{имя}: автор сверяется по author_uid",
          коллекции[имя].get("create_owner_field") == "author_uid")
без_проверки = sorted(
    имя for имя, поля in коллекции.items()
    if поля.get("create_owner_field") is None and поле_автора(поля.get("columns", {})))
check("коллекций с автором и без проверки не осталось", без_проверки == [])

print("правка: пара")
check("в чужую пару нельзя",
      запрет("group", {"group_id": "чужая"}, МОИ, "я", "user_uid", None) is not None)
check("пустая пара тоже отказ",
      запрет("group", {"group_id": ""}, МОИ, "я", "user_uid", None) is not None)
check("та же пара проходит",
      запрет("group", {"group_id": "g1", "text": "привет"}, МОИ, "я", "user_uid", None) is None)
check("другая своя пара проходит",
      запрет("group", {"group_id": "g2"}, МОИ, "я", "user_uid", None) is None)
check("правка без пары в теле проходит",
      запрет("group", {"reactions": {}}, МОИ, "я", "user_uid", None) is None)
check("отметки цикла: в чужую пару нельзя",
      запрет("own_or_shared", {"group_id": "чужая"}, МОИ, "я", "user_uid", "я") is not None)
check("запись пары этой проверкой не задета",
      запрет("members", {"start_date": "2026-01-01"}, МОИ, "я", None, None) is None)
check("геопозиция: чужой канал нельзя",
      запрет("channel", {"channel": "g9"}, МОИ, "я", "user_uid", "я") is not None)
check("геопозиция: канал своей пары проходит",
      запрет("channel", {"channel": "g1"}, МОИ, "я", "user_uid", "я") is None)
check("геопозиция: личный канал проходит",
      запрет("channel", {"channel": "live_я"}, МОИ, "я", "user_uid", "я") is None)

print("правка: автор")
check("автора на партнёра сменить нельзя",
      запрет("group", {"user_uid": "партнёр"}, МОИ, "я", "user_uid", "я") is not None)
check("чужую запись себе не присвоить",
      запрет("group", {"author_uid": "я"}, МОИ, "я", "author_uid", "партнёр") is not None)
check("тот же автор проходит (приложение шлёт запись целиком)",
      запрет("group", {"group_id": "g1", "user_uid": "я"}, МОИ, "я", "user_uid", "я") is None)
check("партнёр правит запись с её прежним автором",
      запрет("group", {"author_uid": "автор"}, МОИ, "партнёр", "author_uid", "автор") is None)
check("запись без автора принимает только самого себя",
      запрет("group", {"user_uid": "я"}, МОИ, "я", "user_uid", "") is None
      and запрет("group", {"user_uid": "кто-то"}, МОИ, "я", "user_uid", "") is not None)
check("записи нет — решает сама правка (ответит 404)",
      запрет("group", {"user_uid": "кто-то"}, МОИ, "я", "user_uid", None) is None)

print("кто в сети")
условие = свои(2, 3)
check("условие берёт людей из своих пар", "members" in условие and "ANY($2)" in условие)
check("распущенные пары не в счёт", "disbanded" in условие)
check("себя видно всегда", "$3::text" in условие)
check("поиск идёт по индексу user_uid", условие.startswith("user_uid = ANY(ARRAY("))
чтение = источник[источник.index("async def list_records"):источник.index("def _read_only")]
check("список и чтение одной записи зовут это условие", чтение.count("свои_люди_sql(") == 2)
check("«любой вошедший видит всё» в чтении не осталось",
      'scope in ("authed", "public")' not in чтение)

print("\nИТОГ:", "всё прошло" if ok else "ЕСТЬ ПРОВАЛЫ")
raise SystemExit(0 if ok else 1)
