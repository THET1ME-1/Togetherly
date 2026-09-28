#!/usr/bin/env python3
"""Поиск по переписке: разбор `text ~ '…'` и экранирование шаблона.

Запуск: python3 pocketbase/hotpath/test_chat_search.py
"""
import importlib.util
import json
import re
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("hotpath_src", Path(__file__).parent / "hotpath.py")
источник = spec.loader.get_source("hotpath_src")
пространство: dict = {"re": re, "json": json}
начало = источник.index("_COND = re.compile(")
конец = источник.index("\ndef _coerce(", начало)
exec(compile(источник[начало:конец], "hotpath.py", "exec"), пространство)
разбор = пространство["_parse_filter"]
шаблон = пространство["_like_pattern"]


class Поиск(unittest.TestCase):
    def test_текст_ищется_подстрокой(self):
        conds = разбор("group_id = 'g1' && text ~ 'кафе'", {"group_id", "text"})
        self.assertEqual(conds[1], ("text", "~", "кафе"))

    def test_members_по_прежнему_строкой(self):
        conds = разбор("members ~ 'u1'", {"members"})
        self.assertEqual(conds, [("members", "~", "u1")])

    def test_проценты_и_подчёркивания_буквами(self):
        self.assertEqual(шаблон("100%_да"), "%100\\%\\_да%")
        self.assertEqual(шаблон("a\\b"), "%a\\\\b%")

    def test_незнакомое_поле_отказ(self):
        with self.assertRaises(ValueError):
            разбор("password ~ 'x'", {"text"})

    def test_коллекция_сообщений_разрешает_поиск_только_по_тексту(self):
        блок = источник[источник.index('"chat_messages": {'):]
        блок = блок[:блок.index("},\n    \"", 10)]
        self.assertIn('"searchable": {"text"}', блок)


if __name__ == "__main__":
    unittest.main()
