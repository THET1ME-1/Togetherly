# -*- coding: utf-8 -*-
"""Закрепление в чате: python3 pocketbase/hotpath/test_chat_pin_guard.py

Закрепить сообщение может любой из пары (06.11.2026, как в Telegram), а
переписать чужое — только автор. Страж смотрит, какие поля прислали в теле;
поля закрепления обязаны быть и в карте колонок: незнакомую колонку hotpath
выбрасывает молча и отвечает 200, и закрепление пропадало бы без ошибки.
"""
import ast
import os

источник = open(os.path.join(os.path.dirname(__file__), "hotpath.py"), encoding="utf-8").read()
начало = источник.index("ЧАТ_ЧУЖОЕ_МОЖНО")
строка = источник[начало:источник.index("\n", источник.index(")", начало))]
пространство: dict = {}
exec(строка, пространство)
можно = пространство["ЧАТ_ЧУЖОЕ_МОЖНО"]

дерево = ast.parse(источник)
колонки = поиск = None
for узел in ast.walk(дерево):
    if isinstance(узел, ast.Assign) and any(getattr(t, "id", "") == "COLLECTIONS" for t in узел.targets):
        for k, v in zip(узел.value.keys, узел.value.values):
            if getattr(k, "value", "") == "chat_messages":
                for kk, vv in zip(v.keys, v.values):
                    имя = getattr(kk, "value", "")
                    if имя == "columns":
                        колонки = ast.literal_eval(vv)
                    if имя == "filterable":
                        поиск = ast.literal_eval(vv)

ok = True


def check(имя, условие):
    global ok
    print(("  ✓ " if условие else "  ✗ ") + имя)
    if not условие:
        ok = False


print("закрепление в чате")
check("не автор может закрепить", {"pinned_at", "pinned_by"} <= можно)
check("реакции и отметки просмотра по-прежнему можно", {"reactions", "voice_heard_at", "note_seen_at", "note_hearts"} <= можно)
check("чужой текст переписать нельзя", not ({"text", "deleted", "color", "face", "user_uid"} & можно))
check("колонки закрепления в карте", колонки is not None and колонки.get("pinned_at") == "num" and колонки.get("pinned_by") == "text")
check("закреплённые можно выбрать фильтром", поиск is not None and "pinned_at" in поиск)
check("страж читает список, а не свой перечень", "f not in ЧАТ_ЧУЖОЕ_МОЖНО" in источник)

raise SystemExit(0 if ok else 1)
